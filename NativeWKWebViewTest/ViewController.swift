import UIKit
import WebKit

// MARK: - Enums & Supporting Structures

/// Policy for handling target="_blank" and window.open requests
enum TargetBlankPolicy: String, CaseIterable {
    case rerouteSameView = "Reroute"
    case block = "Block"
}

/// Policy for handling custom app URL schemes (e.g. vnd.youtube:, googlesearch:)
enum CustomSchemePolicy: String, CaseIterable {
    case observeOnly = "Allow/Log"
    case blockExternal = "Block Apps"
}

/// Log Categories for clear diagnostic filtering
enum LogCategory: String {
    case nav = "[NAV]"
    case resp = "[RESP]"
    case ui = "[UI]"
    case js = "[JS]"
    case cookie = "[COOKIE]"
    case scheme = "[SCHEME]"
    case error = "[ERROR]"
    case state = "[STATE]"
}

/// Weak proxy to avoid retain cycle in WKUserContentController
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - ViewController (V2 Native Browser Engine)

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate, WKScriptMessageHandler {

    // MARK: - UI Components
    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let urlTextField = UITextField()
    private let goButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let sslBadgeLabel = UILabel()
    private let statusLabel = UILabel()

    // Control Bars
    private let testUrlsScrollView = UIScrollView()
    private let actionsScrollView = UIScrollView()

    // Log Console
    private let logToggleBtn = UIButton(type: .system)
    private let clearLogBtn = UIButton(type: .system)
    private let filterLogBtn = UIButton(type: .system)
    private let logTextView = UITextView()

    // MARK: - Policies & State
    private var targetBlankPolicy: TargetBlankPolicy = .rerouteSameView
    private var customSchemePolicy: CustomSchemePolicy = .observeOnly
    private var activeFilter: LogCategory? = nil

    private var progressObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var secureObserver: NSKeyValueObservation?

    private var isLogExpanded = false
    private var logHeightConstraint: NSLayoutConstraint?
    private var allLogEntries: [(category: LogCategory, text: String)] = []

    // MARK: - Quick Test Sites
    private let testURLs = [
        "https://example.com",
        "https://www.google.com",
        "https://www.youtube.com",
        "https://mega.nz",
        "https://github.com"
    ]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native WKWebView V2 Engine"
        view.backgroundColor = .systemBackground

        setupWebView()
        setupTopControls()
        setupQuickTestBar()
        setupActionToolbar()
        setupLogConsole()
        setupLayout()
        setupObservers()

        log(.state, "V2 Browser-Engine PoC initialized.")
        log(.state, "WebsiteDataStore: persistent (cookies & storage active).")
        log(.state, "JS Bridge active: capturing console.log & NativeEngine messages.")

        loadURLString("https://example.com")
    }

    deinit {
        progressObserver?.invalidate()
        titleObserver?.invalidate()
        urlObserver?.invalidate()
        secureObserver?.invalidate()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "diagnosticBridge")
    }

    // MARK: - Setup Views
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = WKWebsiteDataStore.default()

        // JS Bridge: Inject diagnostic script to forward console.log to native
        let userContentController = WKUserContentController()
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
        userContentController.add(WeakScriptMessageHandler(delegate: self), name: "diagnosticBridge")

        config.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
    }

    private func setupTopControls() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemBlue
        view.addSubview(progressView)

        backButton.setTitle("◀", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)

        forwardButton.setTitle("▶", for: .normal)
        forwardButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .touchUpInside)

        reloadButton.setTitle("⟳", for: .normal)
        reloadButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        reloadButton.addTarget(self, action: #selector(didTapReload), for: .touchUpInside)

        sslBadgeLabel.text = "🔒"
        sslBadgeLabel.font = .systemFont(ofSize: 14)
        sslBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        urlTextField.borderStyle = .roundedRect
        urlTextField.keyboardType = .URL
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.placeholder = "Enter HTTPS URL..."
        urlTextField.font = .systemFont(ofSize: 13)
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false

        goButton.setTitle("Go", for: .normal)
        goButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        goButton.addTarget(self, action: #selector(didTapGo), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Ready"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
    }

    private func setupQuickTestBar() {
        testUrlsScrollView.showsHorizontalScrollIndicator = false
        testUrlsScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(testUrlsScrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        testUrlsScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: testUrlsScrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: testUrlsScrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: testUrlsScrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: testUrlsScrollView.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: testUrlsScrollView.heightAnchor)
        ])

        for urlStr in testURLs {
            let btn = UIButton(type: .system)
            let host = URL(string: urlStr)?.host ?? urlStr
            btn.setTitle(host.replacingOccurrences(of: "www.", with: ""), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            btn.backgroundColor = .secondarySystemBackground
            btn.layer.cornerRadius = 6
            btn.contentEdgeInsets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
            btn.addAction(UIAction { [weak self] _ in
                self?.loadURLString(urlStr)
            }, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    private func setupActionToolbar() {
        actionsScrollView.showsHorizontalScrollIndicator = false
        actionsScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionsScrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        actionsScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: actionsScrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: actionsScrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: actionsScrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: actionsScrollView.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: actionsScrollView.heightAnchor)
        ])

        // Test _blank
        addActionButton(to: stack, title: "Test _blank", color: .systemOrange) { [weak self] in
            self?.loadTestBlankHTML()
        }

        // Test window.open
        addActionButton(to: stack, title: "Test window.open", color: .systemOrange) { [weak self] in
            self?.loadTestWindowOpenHTML()
        }

        // Test Schemes
        addActionButton(to: stack, title: "Test Schemes", color: .systemPurple) { [weak self] in
            self?.loadTestSchemesHTML()
        }

        // Test Storage & Cookies
        addActionButton(to: stack, title: "Test Storage", color: .systemTeal) { [weak self] in
            self?.loadTestStorageHTML()
        }

        // Inspect Cookies
        addActionButton(to: stack, title: "Inspect Cookies", color: .systemGreen) { [weak self] in
            self?.inspectCookies()
        }

        // Eval JS
        addActionButton(to: stack, title: "Eval JS", color: .systemIndigo) { [weak self] in
            self?.promptEvaluateJavaScript()
        }

        // Clear Storage
        addActionButton(to: stack, title: "Clear Cache", color: .systemRed) { [weak self] in
            self?.clearWebsiteData()
        }
    }

    private func addActionButton(to stack: UIStackView, title: String, color: UIColor, action: @escaping () -> Void) {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        btn.setTitleColor(color, for: .normal)
        btn.backgroundColor = color.withAlphaComponent(0.12)
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stack.addArrangedSubview(btn)
    }

    private func setupLogConsole() {
        logTextView.isEditable = false
        logTextView.backgroundColor = UIColor(white: 0.08, alpha: 0.95)
        logTextView.textColor = .systemGreen
        logTextView.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        logTextView.layer.cornerRadius = 8
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logTextView)

        logToggleBtn.setTitle("Logs ▼", for: .normal)
        logToggleBtn.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        logToggleBtn.addTarget(self, action: #selector(toggleLogHeight), for: .touchUpInside)

        filterLogBtn.setTitle("Filter: All", for: .normal)
        filterLogBtn.titleLabel?.font = .systemFont(ofSize: 11)
        filterLogBtn.addTarget(self, action: #selector(cycleLogFilter), for: .touchUpInside)

        clearLogBtn.setTitle("Clear", for: .normal)
        clearLogBtn.titleLabel?.font = .systemFont(ofSize: 11)
        clearLogBtn.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)
    }

    private func setupLayout() {
        let navBarStack = UIStackView(arrangedSubviews: [backButton, forwardButton, reloadButton, sslBadgeLabel, urlTextField, goButton])
        navBarStack.axis = .horizontal
        navBarStack.spacing = 5
        navBarStack.alignment = .center
        navBarStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBarStack)

        let logHeaderStack = UIStackView(arrangedSubviews: [logToggleBtn, filterLogBtn, clearLogBtn])
        logHeaderStack.axis = .horizontal
        logHeaderStack.spacing = 10
        logHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logHeaderStack)

        let safeArea = view.safeAreaLayoutGuide
        logHeightConstraint = logTextView.heightAnchor.constraint(equalToConstant: 140)

        NSLayoutConstraint.activate([
            // Top Nav
            navBarStack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 2),
            navBarStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 6),
            navBarStack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -6),
            navBarStack.heightAnchor.constraint(equalToConstant: 36),

            // Progress bar
            progressView.topAnchor.constraint(equalTo: navBarStack.bottomAnchor, constant: 2),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            // Quick Test Sites Bar
            testUrlsScrollView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 2),
            testUrlsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            testUrlsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            testUrlsScrollView.heightAnchor.constraint(equalToConstant: 28),

            // V2 Action Suites Toolbar
            actionsScrollView.topAnchor.constraint(equalTo: testUrlsScrollView.bottomAnchor, constant: 2),
            actionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionsScrollView.heightAnchor.constraint(equalToConstant: 28),

            // Status bar
            statusLabel.topAnchor.constraint(equalTo: actionsScrollView.bottomAnchor, constant: 1),
            statusLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -8),
            statusLabel.heightAnchor.constraint(equalToConstant: 14),

            // WKWebView
            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: logHeaderStack.topAnchor, constant: -2),

            // Log header
            logHeaderStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 8),
            logHeaderStack.bottomAnchor.constraint(equalTo: logTextView.topAnchor, constant: -2),

            // Log text console
            logTextView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 6),
            logTextView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -6),
            logTextView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -2),
            logHeightConstraint!
        ])
    }

    private func setupObservers() {
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.progressView.progress = Float(webView.estimatedProgress)
            self.progressView.isHidden = webView.estimatedProgress >= 1.0
        }

        titleObserver = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            if let title = webView.title, !title.isEmpty {
                self.title = title
            }
        }

        urlObserver = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            if let url = webView.url {
                self.urlTextField.text = url.absoluteString
                self.updateSecurityBadge(for: url)
            }
        }

        secureObserver = webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.sslBadgeLabel.text = webView.hasOnlySecureContent ? "🔒" : "🔓"
        }
    }

    private func updateSecurityBadge(for url: URL) {
        if url.scheme?.lowercased() == "https" {
            sslBadgeLabel.text = "🔒"
            sslBadgeLabel.textColor = .systemGreen
        } else {
            sslBadgeLabel.text = "⚠️"
            sslBadgeLabel.textColor = .systemOrange
        }
    }

    // MARK: - Actions
    @objc private func didTapBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func didTapForward() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func didTapReload() {
        webView.reload()
    }

    @objc private func didTapGo() {
        urlTextField.resignFirstResponder()
        if let text = urlTextField.text, !text.isEmpty {
            loadURLString(text)
        }
    }

    @objc private func toggleLogHeight() {
        isLogExpanded.toggle()
        logHeightConstraint?.constant = isLogExpanded ? 280 : 140
        logToggleBtn.setTitle(isLogExpanded ? "Logs ▲" : "Logs ▼", for: .normal)
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    @objc private func clearLogs() {
        allLogEntries.removeAll()
        logTextView.text = ""
    }

    @objc private func cycleLogFilter() {
        let filters: [LogCategory?] = [nil, .nav, .resp, .ui, .js, .cookie, .scheme]
        if let currentIdx = filters.firstIndex(of: activeFilter) {
            let nextIdx = (currentIdx + 1) % filters.count
            activeFilter = filters[nextIdx]
        } else {
            activeFilter = .nav
        }

        let title = activeFilter == nil ? "Filter: All" : "Filter: \(activeFilter!.rawValue)"
        filterLogBtn.setTitle(title, for: .normal)
        rebuildLogDisplay()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapGo()
        return true
    }

    private func loadURLString(_ string: String) {
        var formatted = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.lowercased().hasPrefix("http://") && !formatted.lowercased().hasPrefix("https://") {
            formatted = "https://" + formatted
        }
        guard let url = URL(string: formatted) else {
            log(.error, "Invalid URL string: \(string)")
            return
        }
        log(.nav, "Initiating loadRequest: \(formatted)")
        statusLabel.text = "Loading: \(url.host ?? formatted)"
        webView.load(URLRequest(url: url))
    }

    // MARK: - Logging System
    private func log(_ category: LogCategory, _ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SS"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(category.rawValue) \(message)\n"

        allLogEntries.append((category: category, text: line))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.activeFilter == nil || self.activeFilter == category {
                self.logTextView.text.append(line)
                let bottom = NSRange(location: self.logTextView.text.count - 1, length: 1)
                self.logTextView.scrollRangeToVisible(bottom)
            }
            print(line)
        }
    }

    private func rebuildLogDisplay() {
        let filtered = allLogEntries.filter { activeFilter == nil || $0.category == activeFilter! }
        logTextView.text = filtered.map { $0.text }.joined()
        if !logTextView.text.isEmpty {
            let bottom = NSRange(location: logTextView.text.count - 1, length: 1)
            logTextView.scrollRangeToVisible(bottom)
        }
    }

    // MARK: - WKScriptMessageHandler (JS Console & NativeEngine Bridge)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "diagnosticBridge" else { return }
        if let body = message.body as? [String: Any],
           let level = body["level"] as? String,
           let msg = body["message"] as? String {
            log(.js, "[\(level)] \(msg)")
        } else {
            log(.js, "Raw message received: \(message.body)")
        }
    }

    // MARK: - WKNavigationDelegate

    // 1. Navigation Action Decision
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let urlStr = url?.absoluteString ?? "unknown"
        let scheme = url?.scheme?.lowercased() ?? "none"
        let navTypeStr: String
        switch navigationAction.navigationType {
        case .linkActivated: navTypeStr = "linkActivated"
        case .formSubmitted: navTypeStr = "formSubmitted"
        case .backForward: navTypeStr = "backForward"
        case .reload: navTypeStr = "reload"
        case .formResubmitted: navTypeStr = "formResubmitted"
        case .other: navTypeStr = "other"
        @unknown default: navTypeStr = "unknown"
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let isTargetNil = (navigationAction.targetFrame == nil)
        let method = navigationAction.request.httpMethod ?? "GET"

        log(.nav, "ACTION: type=\(navTypeStr) method=\(method) scheme=\(scheme) mainFrame=\(isMainFrame) targetNil=\(isTargetNil)")
        log(.nav, " ↳ URL: \(urlStr)")

        // Custom App Schemes Check
        if scheme != "http" && scheme != "https" && scheme != "about" && scheme != "data" {
            log(.scheme, "Non-HTTP Scheme intercepted: \(scheme) (URL: \(urlStr))")
            if customSchemePolicy == .blockExternal && ["vnd.youtube", "googlesearch", "googlechrome", "reddit", "twitter", "fb"].contains(scheme) {
                log(.scheme, "Policy BLOCK: External app scheme denied: \(scheme)")
                decisionHandler(.cancel)
                return
            }
        }

        // Programmatic / Direct Navigation Policy
        decisionHandler(.allow)
    }

    // 2. Navigation Response & Header Inspection
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            let mimeType = httpResponse.mimeType ?? "unknown"
            let xFrameOptions = httpResponse.value(forHTTPHeaderField: "X-Frame-Options") ?? "none"
            let csp = httpResponse.value(forHTTPHeaderField: "Content-Security-Policy") != nil ? "present" : "none"
            let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") != nil ? "present" : "none"

            log(.resp, "HTTP \(statusCode) [\(mimeType)] X-Frame: \(xFrameOptions) CSP: \(csp) Set-Cookie: \(setCookie)")
            log(.resp, " ↳ URL: \(httpResponse.url?.absoluteString ?? "")")
        }
        decisionHandler(.allow)
    }

    // 3. Provisional & Finished Events
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log(.nav, "EVENT: didStartProvisionalNavigation")
        statusLabel.text = "Connecting..."
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        log(.nav, "REDIRECT: Server redirected to: \(webView.url?.absoluteString ?? "")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let finalUrl = webView.url?.absoluteString ?? ""
        log(.nav, "EVENT: didFinish -> \(finalUrl)")
        statusLabel.text = "Loaded: \(webView.title ?? finalUrl)"
        urlTextField.text = finalUrl
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log(.error, "didFail: \(error.localizedDescription)")
        statusLabel.text = "Error: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log(.error, "didFailProvisional: \(error.localizedDescription)")
        statusLabel.text = "Connection Failed"
    }

    // 4. SSL Authentication Challenges
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        let host = challenge.protectionSpace.host
        log(.nav, "SSL/Auth Challenge: host=\(host) method=\(authMethod)")
        completionHandler(.performDefaultHandling, nil)
    }

    // 5. Crash Resiliency
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log(.error, "CRITICAL: WebContent process terminated (OOM/Crash). Reloading...")
        statusLabel.text = "Process Terminated. Reloading..."
        webView.reload()
    }

    // MARK: - WKUIDelegate (target="_blank", window.open & Dialogs)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let targetUrl = navigationAction.request.url?.absoluteString ?? "unknown"
        log(.ui, "Intercepted window.open / target=_blank for URL: \(targetUrl)")

        if navigationAction.targetFrame == nil {
            if targetBlankPolicy == .rerouteSameView {
                log(.ui, "Policy REROUTE: Loading target=_blank in same WKWebView")
                webView.load(navigationAction.request)
            } else {
                log(.ui, "Policy BLOCK: Blocked target=_blank request")
            }
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        log(.ui, "EVENT: window.close() invoked by web content")
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        log(.ui, "alert(\"\(message)\")")
        let alert = UIAlertController(title: "Page Alert", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler() }))
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        log(.ui, "confirm(\"\(message)\")")
        let alert = UIAlertController(title: "Page Confirm", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completionHandler(false) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler(true) }))
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        log(.ui, "prompt(\"\(prompt)\")")
        let alert = UIAlertController(title: "Page Prompt", message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completionHandler(nil) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler(alert.textFields?.first?.text)
        }))
        present(alert, animated: true)
    }

    // MARK: - Diagnostic Test Suites (Local HTML Injections)

    private func loadTestBlankHTML() {
        log(.ui, "Loading test suite: target=\"_blank\"")
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Test _blank</title></head>
        <body style="font-family: -apple-system; padding: 20px;">
            <h2>Test target="_blank"</h2>
            <p>Clicking this link requests a new browsing context (target=_blank):</p>
            <p><a href="https://example.com" target="_blank" style="display:inline-block; padding:10px 18px; background:#007aff; color:#fff; text-decoration:none; border-radius:8px;">Open example.com (_blank)</a></p>
            <p><a href="https://www.google.com" target="_blank" style="display:inline-block; padding:10px 18px; background:#34c759; color:#fff; text-decoration:none; border-radius:8px;">Open Google (_blank)</a></p>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    private func loadTestWindowOpenHTML() {
        log(.ui, "Loading test suite: window.open()")
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Test window.open</title></head>
        <body style="font-family: -apple-system; padding: 20px;">
            <h2>Test window.open()</h2>
            <p>Clicking below triggers window.open via JavaScript:</p>
            <button onclick="window.open('https://example.com')" style="padding:10px 18px; background:#5856d6; color:#fff; border:none; border-radius:8px; font-size:15px;">window.open('example.com')</button>
            <br><br>
            <button onclick="console.log('Test console message from web!'); alert('Native alert test');" style="padding:10px 18px; background:#ff9500; color:#fff; border:none; border-radius:8px; font-size:15px;">Test Console & Alert</button>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    private func loadTestSchemesHTML() {
        log(.scheme, "Loading test suite: URL Schemes & Universal Links")
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Test Schemes</title></head>
        <body style="font-family: -apple-system; padding: 20px;">
            <h2>Test Schemes & Links</h2>
            <p>1. Custom App Scheme:</p>
            <a href="vnd.youtube://dQw4w9WgXcQ" style="display:inline-block; padding:8px 14px; background:#ff3b30; color:#fff; border-radius:6px; text-decoration:none;">vnd.youtube://</a>
            <p>2. Universal Link candidate:</p>
            <a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ" style="display:inline-block; padding:8px 14px; background:#ff2d55; color:#fff; border-radius:6px; text-decoration:none;">youtube.com Link</a>
            <p>3. Mailto Scheme:</p>
            <a href="mailto:test@example.com?subject=PoC" style="display:inline-block; padding:8px 14px; background:#007aff; color:#fff; border-radius:6px; text-decoration:none;">mailto: Scheme</a>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    private func loadTestStorageHTML() {
        log(.cookie, "Loading test suite: Storage & Cookies")
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Test Storage</title></head>
        <body style="font-family: -apple-system; padding: 20px;">
            <h2>Test Cookies & Storage</h2>
            <button onclick="writeStorage()" style="padding:8px 14px; background:#34c759; color:#fff; border:none; border-radius:6px;">1. Write Storage & Cookie</button>
            <br><br>
            <button onclick="readStorage()" style="padding:8px 14px; background:#007aff; color:#fff; border:none; border-radius:6px;">2. Read Storage & Cookie</button>
            <div id="output" style="margin-top:15px; font-family:monospace; background:#eee; padding:10px; border-radius:6px;">Result will appear here</div>
            <script>
                function writeStorage() {
                    const ts = new Date().toISOString();
                    document.cookie = 'poc_cookie=' + encodeURIComponent(ts) + '; path=/; max-age=86400';
                    localStorage.setItem('poc_local_storage', 'saved_at_' + ts);
                    sessionStorage.setItem('poc_session_storage', 'active');
                    console.log('Wrote storage & cookie:', ts);
                    document.getElementById('output').innerText = 'Written: ' + ts;
                }
                function readStorage() {
                    const c = document.cookie;
                    const ls = localStorage.getItem('poc_local_storage');
                    const ss = sessionStorage.getItem('poc_session_storage');
                    const text = 'Cookie: ' + c + '\\nLS: ' + ls + '\\nSS: ' + ss;
                    console.log(text);
                    document.getElementById('output').innerText = text;
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    // MARK: - Cookie & Cache Inspection
    private func inspectCookies() {
        log(.cookie, "Inspecting WKHTTPCookieStore...")
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            self.log(.cookie, "Total cookies stored: \(cookies.count)")
            for c in cookies {
                self.log(.cookie, "Cookie: [\(c.domain)] \(c.name)=\(c.value.prefix(20))... secure=\(c.isSecure) httpOnly=\(c.isHTTPOnly)")
            }
        }
    }

    private func clearWebsiteData() {
        log(.cookie, "Clearing all website data (cookies, cache, storage)...")
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { [weak self] in
            guard let self = self else { return }
            self.log(.cookie, "WebsiteDataStore cleared successfully.")
            self.statusLabel.text = "Cache Cleared"
            self.webView.reload()
        }
    }

    private func promptEvaluateJavaScript() {
        let alert = UIAlertController(title: "Evaluate JavaScript", message: "Enter JS expression to execute in page context:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = "document.title + ' | Cookies: ' + document.cookie"
            tf.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Execute", style: .default, handler: { [weak self] _ in
            guard let self = self, let code = alert.textFields?.first?.text, !code.isEmpty else { return }
            self.log(.js, "Eval: \(code)")
            self.webView.evaluateJavaScript(code) { result, error in
                if let error = error {
                    self.log(.error, "JS Error: \(error.localizedDescription)")
                } else if let result = result {
                    self.log(.js, "Result: \(result)")
                } else {
                    self.log(.js, "Result: undefined / void")
                }
            }
        }))
        present(alert, animated: true)
    }
}
