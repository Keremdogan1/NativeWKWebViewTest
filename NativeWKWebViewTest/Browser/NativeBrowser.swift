import Foundation
import UIKit
import WebKit

/// Weak proxy to break retain cycles in WKUserContentController
private class WeakScriptMessageHandlerProxy: NSObject, WKScriptMessageHandler {
    private weak var handler: WKScriptMessageHandler?

    init(handler: WKScriptMessageHandler) {
        self.handler = handler
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}

/// Core Native Browser Engine abstraction wrapping WebKit
public final class NativeBrowser: NSObject, WKScriptMessageHandler {

    // MARK: - Public Properties
    public private(set) var webView: WKWebView!
    public var view: UIView { return webView }
    public private(set) var state: BrowserState = .initial

    public var onStateChanged: ((BrowserState) -> Void)?
    public var onEvent: ((BrowserEvent) -> Void)?

    public var dialogPresenter: BrowserUIDialogPresenter? {
        get { return uiDelegate.dialogPresenter }
        set { uiDelegate.dialogPresenter = newValue }
    }

    // MARK: - Internal Delegates & Observers
    private var navigationDelegate: BrowserNavigationDelegate!
    private var uiDelegate: BrowserUIDelegate!

    private var progressObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var secureObserver: NSKeyValueObservation?
    private var canGoBackObserver: NSKeyValueObservation?
    private var canGoForwardObserver: NSKeyValueObservation?
    private var loadingObserver: NSKeyValueObservation?

    private var lastTerminationDate: Date?

    // MARK: - Initialization & Lifecycle
    public init(frame: CGRect = .zero, configuration: WKWebViewConfiguration? = nil) {
        super.init()

        let config = configuration ?? WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = WKWebsiteDataStore.default()

        // JS Diagnostic & Console Bridge
        let userContentController = config.userContentController
        let consoleForwarderScript = """
        (function() {
            if (window.__diagnosticBridgeInjected) return;
            window.__diagnosticBridgeInjected = true;

            const send = (level, args) => {
                try {
                    const msg = Array.from(args).map(a => {
                        try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                        catch(e) { return String(a); }
                    }).join(' ');
                    window.webkit.messageHandlers.diagnosticBridge.postMessage({ level: level, message: msg });
                } catch(e) {}
            };

            const origLog = console.log;
            console.log = function() { send('LOG', arguments); origLog.apply(console, arguments); };

            const origWarn = console.warn;
            console.warn = function() { send('WARN', arguments); origWarn.apply(console, arguments); };

            const origError = console.error;
            console.error = function() { send('ERROR', arguments); origError.apply(console, arguments); };

            window.NativeEngine = {
                postMessage: function(data) {
                    window.webkit.messageHandlers.diagnosticBridge.postMessage({ level: 'CLIENT', message: JSON.stringify(data) });
                }
            };
        })();
        """

        let userScript = WKUserScript(source: consoleForwarderScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        userContentController.add(WeakScriptMessageHandlerProxy(handler: self), name: "diagnosticBridge")

        config.userContentController = userContentController

        self.webView = WKWebView(frame: frame, configuration: config)
        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.translatesAutoresizingMaskIntoConstraints = false

        self.navigationDelegate = BrowserNavigationDelegate(browser: self)
        self.uiDelegate = BrowserUIDelegate(browser: self)

        self.webView.navigationDelegate = self.navigationDelegate
        self.webView.uiDelegate = self.uiDelegate

        setupObservers()
        BrowserLogger.shared.log(.state, "NativeBrowser V3 engine initialized.")
    }

    deinit {
        progressObserver?.invalidate()
        titleObserver?.invalidate()
        urlObserver?.invalidate()
        secureObserver?.invalidate()
        canGoBackObserver?.invalidate()
        canGoForwardObserver?.invalidate()
        loadingObserver?.invalidate()

        webView.configuration.userContentController.removeScriptMessageHandler(forName: "diagnosticBridge")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        BrowserLogger.shared.log(.state, "NativeBrowser deallocated cleanly.")
    }

    // MARK: - Observers
    private func setupObservers() {
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.progress = wv.estimatedProgress
            self.notifyStateChanged()
            self.emitEvent(.progressChanged(wv.estimatedProgress))
        }

        titleObserver = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.title = wv.title
            self.notifyStateChanged()
            self.emitEvent(.titleChanged(wv.title))
        }

        urlObserver = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.url = wv.url
            self.notifyStateChanged()
            self.emitEvent(.urlChanged(wv.url))
        }

        secureObserver = webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.isSecure = wv.hasOnlySecureContent
            self.notifyStateChanged()
            self.emitEvent(.securityChanged(isSecure: wv.hasOnlySecureContent))
        }

        canGoBackObserver = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.canGoBack = wv.canGoBack
            self.notifyStateChanged()
            self.emitEvent(.canGoBackChanged(wv.canGoBack))
        }

        canGoForwardObserver = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.canGoForward = wv.canGoForward
            self.notifyStateChanged()
            self.emitEvent(.canGoForwardChanged(wv.canGoForward))
        }

        loadingObserver = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            self.state.isLoading = wv.isLoading
            self.notifyStateChanged()
            self.emitEvent(.loadingChanged(wv.isLoading))
        }
    }

    // MARK: - Script Message Handler
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "diagnosticBridge" else { return }
        if let body = message.body as? [String: Any],
           let level = body["level"] as? String,
           let msg = body["message"] as? String {
            BrowserLogger.shared.log(.js, "[\(level)] \(msg)")
            emitEvent(.jsMessageReceived(level: level, message: msg))
        } else {
            BrowserLogger.shared.log(.js, "Raw message received: \(message.body)")
            emitEvent(.jsMessageReceived(level: "RAW", message: "\(message.body)"))
        }
    }

    // MARK: - Public Control Operations
    public func open(_ url: URL) {
        let request = URLRequest(url: url)
        BrowserLogger.shared.log(.nav, "Loading URL: \(url.absoluteString)")
        webView.load(request)
    }

    public func open(_ urlString: String) {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") && !trimmed.hasPrefix("about:") {
            trimmed = "https://" + trimmed
        }
        if let url = URL(string: trimmed) {
            open(url)
        } else {
            BrowserLogger.shared.log(.error, "Invalid URL string: \(urlString)")
        }
    }

    public func load(_ request: URLRequest) {
        webView.load(request)
    }

    public func loadHTMLString(_ string: String, baseURL: URL? = nil) {
        webView.loadHTMLString(string, baseURL: baseURL)
    }

    public func close() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        BrowserLogger.shared.log(.state, "NativeBrowser closed / stopped.")
    }

    public func back() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    public func forward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    public func reload() {
        webView.reload()
    }

    public func getState() -> BrowserState {
        return state
    }

    public func setFrame(_ frame: CGRect) {
        webView.frame = frame
    }

    public func setVisible(_ visible: Bool) {
        webView.isHidden = !visible
    }

    public func setTargetBlankPolicy(_ policy: TargetBlankPolicy) {
        state.targetBlankPolicy = policy
        BrowserLogger.shared.log(.ui, "target=_blank policy set to: \(policy.rawValue)")
        notifyStateChanged()
    }

    public func setCustomSchemePolicy(_ policy: CustomSchemePolicy) {
        state.customSchemePolicy = policy
        BrowserLogger.shared.log(.scheme, "CustomScheme policy set to: \(policy.rawValue)")
        notifyStateChanged()
    }

    public func evaluateJavaScript(_ script: String, completion: ((Result<Any?, Error>) -> Void)? = nil) {
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                completion?(.failure(error))
            } else {
                completion?(.success(result))
            }
        }
    }

    public func inspectCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        BrowserLogger.shared.log(.cookie, "Inspecting WKHTTPCookieStore...")
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            BrowserLogger.shared.log(.cookie, "Total cookies stored: \(cookies.count)")
            for c in cookies {
                BrowserLogger.shared.log(.cookie, "Cookie: [\(c.domain)] \(c.name)=\(c.value.prefix(20))... secure=\(c.isSecure) httpOnly=\(c.isHTTPOnly)")
            }
            completion(cookies)
        }
    }

    public func clearWebsiteData(completion: (() -> Void)? = nil) {
        BrowserLogger.shared.log(.cookie, "Clearing all website data (cookies, cache, storage)...")
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { [weak self] in
            guard let self = self else { return }
            BrowserLogger.shared.log(.cookie, "WebsiteDataStore cleared successfully.")
            self.reload()
            completion?()
        }
    }

    // MARK: - Internal Coordination
    func handleProcessTermination() {
        BrowserLogger.shared.log(.error, "CRITICAL: WebContent process terminated (OOM/Crash).")
        let now = Date()
        if let last = lastTerminationDate, now.timeIntervalSince(last) < 3.0 {
            BrowserLogger.shared.log(.error, "RAPID CRASH LOOP DETECTED: Suppressing auto-reload to prevent CPU lockup.")
            updateError("Process Crash Loop: Reload paused.")
            emitEvent(.webContentProcessTerminated(reloaded: false))
            return
        }
        lastTerminationDate = now
        updateError("Process Terminated. Reloading...")
        emitEvent(.webContentProcessTerminated(reloaded: true))
        webView.reload()
    }

    func updateLoadingState(isLoading: Bool) {
        state.isLoading = isLoading
        if isLoading { state.lastError = nil }
        notifyStateChanged()
    }

    func updateError(_ message: String) {
        state.lastError = message
        notifyStateChanged()
    }

    func updateStateFromWebView() {
        state.url = webView.url
        state.title = webView.title
        state.canGoBack = webView.canGoBack
        state.canGoForward = webView.canGoForward
        state.isLoading = webView.isLoading
        state.isSecure = webView.hasOnlySecureContent
        notifyStateChanged()
    }

    func emitEvent(_ event: BrowserEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func notifyStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChanged?(self.state)
        }
    }
}
