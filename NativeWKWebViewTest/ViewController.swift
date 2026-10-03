import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate {

    // MARK: - UI Components
    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let urlTextField = UITextField()
    private let goButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let logToggleBtn = UIButton(type: .system)
    private let clearLogBtn = UIButton(type: .system)
    private let testUrlsScrollView = UIScrollView()
    private let logTextView = UITextView()

    // MARK: - State
    private var progressObserver: NSKeyValueObservation?
    private var titleObserver: NSKeyValueObservation?
    private var isLogExpanded = false
    private var logHeightConstraint: NSLayoutConstraint?

    // MARK: - Test URLs
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
        title = "Native WKWebView PoC"
        view.backgroundColor = .systemBackground

        setupWebView()
        setupTopControls()
        setupQuickTestBar()
        setupLogConsole()
        setupLayout()
        setupObservers()

        log("PoC initialized. Ready for tests.")
        // Initial load
        loadURLString("https://example.com")
    }

    deinit {
        progressObserver?.invalidate()
        titleObserver?.invalidate()
    }

    // MARK: - Setup Views
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = WKWebsiteDataStore.default()

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

        // Navigation buttons
        backButton.setTitle("◀", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)

        forwardButton.setTitle("▶", for: .normal)
        forwardButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .touchUpInside)

        reloadButton.setTitle("⟳", for: .normal)
        reloadButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        reloadButton.addTarget(self, action: #selector(didTapReload), for: .touchUpInside)

        // URL Field
        urlTextField.borderStyle = .roundedRect
        urlTextField.keyboardType = .URL
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.placeholder = "Enter HTTPS URL..."
        urlTextField.font = .systemFont(ofSize: 14)
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false

        goButton.setTitle("Go", for: .normal)
        goButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        goButton.addTarget(self, action: #selector(didTapGo), for: .touchUpInside)
    }

    private func setupQuickTestBar() {
        testUrlsScrollView.showsHorizontalScrollIndicator = false
        testUrlsScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(testUrlsScrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
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
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.backgroundColor = .secondarySystemBackground
            btn.layer.cornerRadius = 6
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            btn.addAction(UIAction { [weak self] _ in
                self?.loadURLString(urlStr)
            }, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    private func setupLogConsole() {
        logTextView.isEditable = false
        logTextView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        logTextView.textColor = .systemGreen
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.layer.cornerRadius = 8
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logTextView)

        logToggleBtn.setTitle("Logs ▼", for: .normal)
        logToggleBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        logToggleBtn.addTarget(self, action: #selector(toggleLogHeight), for: .touchUpInside)

        clearLogBtn.setTitle("Clear", for: .normal)
        clearLogBtn.titleLabel?.font = .systemFont(ofSize: 12)
        clearLogBtn.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)
    }

    private func setupLayout() {
        let navBarStack = UIStackView(arrangedSubviews: [backButton, forwardButton, reloadButton, urlTextField, goButton])
        navBarStack.axis = .horizontal
        navBarStack.spacing = 6
        navBarStack.alignment = .center
        navBarStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBarStack)

        let logHeaderStack = UIStackView(arrangedSubviews: [logToggleBtn, clearLogBtn])
        logHeaderStack.axis = .horizontal
        logHeaderStack.spacing = 12
        logHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logHeaderStack)

        let safeArea = view.safeAreaLayoutGuide

        logHeightConstraint = logTextView.heightAnchor.constraint(equalToConstant: 130)

        NSLayoutConstraint.activate([
            // Top Nav Bar
            navBarStack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 4),
            navBarStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 8),
            navBarStack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -8),
            navBarStack.heightAnchor.constraint(equalToConstant: 40),

            // Progress bar
            progressView.topAnchor.constraint(equalTo: navBarStack.bottomAnchor, constant: 2),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            // Quick test URL bar
            testUrlsScrollView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 4),
            testUrlsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            testUrlsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            testUrlsScrollView.heightAnchor.constraint(equalToConstant: 32),

            // WKWebView
            webView.topAnchor.constraint(equalTo: testUrlsScrollView.bottomAnchor, constant: 4),
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: logHeaderStack.topAnchor, constant: -4),

            // Log header
            logHeaderStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 10),
            logHeaderStack.bottomAnchor.constraint(equalTo: logTextView.topAnchor, constant: -2),

            // Log console
            logTextView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 8),
            logTextView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -8),
            logTextView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -4),
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
        logHeightConstraint?.constant = isLogExpanded ? 260 : 130
        logToggleBtn.setTitle(isLogExpanded ? "Logs ▲" : "Logs ▼", for: .normal)
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    @objc private func clearLogs() {
        logTextView.text = ""
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
            log("[ERROR] Invalid URL: \(string)")
            return
        }
        log("Loading request: \(formatted)")
        webView.load(URLRequest(url: url))
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SS"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logTextView.text.append(line)
            let bottom = NSRange(location: self.logTextView.text.count - 1, length: 1)
            self.logTextView.scrollRangeToVisible(bottom)
            print(line)
        }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let urlStr = navigationAction.request.url?.absoluteString ?? "unknown"
        let scheme = navigationAction.request.url?.scheme ?? "none"
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

        log("NAVIGATION: type=\(navTypeStr) scheme=\(scheme) mainFrame=\(isMainFrame) targetNil=\(isTargetNil)")
        log(" ↳ URL: \(urlStr)")

        // Observe custom scheme vs universal link vs http
        if scheme != "http" && scheme != "https" {
            log("[CUSTOM SCHEME] Non-HTTP scheme detected: \(scheme)")
        }

        // We allow the navigation to observe true iOS behavior
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log("[EVENT] didStartProvisionalNavigation")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("[EVENT] didFinish: \(webView.url?.absoluteString ?? "")")
        urlTextField.text = webView.url?.absoluteString
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("[EVENT] didFail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("[EVENT] didFailProvisionalNavigation: \(error.localizedDescription)")
    }

    // MARK: - WKUIDelegate (target="_blank" & window.open interception)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let targetUrl = navigationAction.request.url?.absoluteString ?? "unknown"
        log("[WKUIDelegate] Intercepted window.open/target=_blank request for: \(targetUrl)")

        // If targetFrame is nil (target="_blank"), route it back into our existing webView!
        if navigationAction.targetFrame == nil {
            log("[WKUIDelegate] Re-routing target=_blank to same WKWebView")
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler() }))
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completionHandler(false) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler(true) }))
        present(alert, animated: true)
    }
}
