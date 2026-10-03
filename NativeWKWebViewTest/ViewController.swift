import UIKit
import WebKit

/// Main Test Harness UI hosting the V4.3 Multi-Tab NativeBrowser engine
class ViewController: UIViewController, UITextFieldDelegate, BrowserUIDialogPresenter {

    // MARK: - Core Browser Engine & Tab Management
    private var tabManager: BrowserTabManager!
    private let webContainerView = UIView()

    private var activeBrowser: NativeBrowser? {
        return tabManager.activeTab?.browser
    }

    // MARK: - UI Components
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let urlTextField = UITextField()
    private let goButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let sslBadgeLabel = UILabel()
    private let statusLabel = UILabel()

    // Multi-Tab Bar UI
    private let tabBarScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let newTabButton = UIButton(type: .system)

    // Control Bars
    private let testUrlsScrollView = UIScrollView()
    private let actionsScrollView = UIScrollView()

    // Log Console
    private let logToggleBtn = UIButton(type: .system)
    private let clearLogBtn = UIButton(type: .system)
    private let filterLogBtn = UIButton(type: .system)
    private let logTextView = UITextView()

    // Policies & State Display
    private var activeFilter: LogCategory? = nil
    private var isLogExpanded = false
    private var logHeightConstraint: NSLayoutConstraint?

    // Quick Test Sites
    private let testURLs = [
        "https://local-suite.poc",
        "https://example.com",
        "https://www.google.com",
        "https://www.youtube.com",
        "https://mega.nz",
        "https://github.com"
    ]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native WKWebView V4.3 Engine"
        view.backgroundColor = .systemBackground

        setupBrowserTabManager()
        setupTopControls()
        setupTabBarUI()
        setupQuickTestBar()
        setupActionToolbar()
        setupLogConsole()
        setupLayout()
        setupLoggerBinding()

        BrowserLogger.shared.log(.state, "V4.3 Multi-Tab Browser Engine initialized.")
        BrowserLogger.shared.log(.state, "Shared persistent WKWebsiteDataStore.default() active across tabs.")
        BrowserLogger.shared.log(.state, "Offline local test suite available at https://local-suite.poc/")

        // Create initial default tab loading local test suite
        tabManager.createTab(url: URL(string: "https://local-suite.poc/"), activate: true)
    }

    // MARK: - Setup Tab Manager & Browser Engine
    private func setupBrowserTabManager() {
        webContainerView.translatesAutoresizingMaskIntoConstraints = false
        webContainerView.backgroundColor = .systemBackground
        view.addSubview(webContainerView)

        tabManager = BrowserTabManager(containerView: webContainerView)
        tabManager.dialogPresenter = self

        tabManager.onTabsChanged = { [weak self] tabs in
            guard let self = self else { return }
            self.rebuildTabBar(tabs: tabs)
        }

        tabManager.onActiveTabChanged = { [weak self] activeTab in
            guard let self = self else { return }
            if let tab = activeTab {
                self.updateUI(with: tab.browser.state)
            }
            self.rebuildTabBar(tabs: self.tabManager.tabs)
        }

        tabManager.onDownloadUpdated = { [weak self] download in
            guard let self = self else { return }
            let pct = Int(download.progress * 100)
            switch download.state {
            case .downloading:
                self.statusLabel.text = "Downloading [\(download.suggestedFilename)]: \(pct)%"
            case .completed:
                self.statusLabel.text = "Downloaded: \(download.suggestedFilename) (Saved to Documents/Downloads)"
                TestHarnessEngine.shared.record(id: "M", status: .pass, evidence: "Download completed successfully: \(download.suggestedFilename)")
            case .failed:
                self.statusLabel.text = "Download Failed: \(download.suggestedFilename) (\(download.errorDescription ?? ""))"
            case .cancelled:
                self.statusLabel.text = "Download Cancelled: \(download.suggestedFilename)"
            case .pending:
                self.statusLabel.text = "Download Pending: \(download.suggestedFilename)"
            }
        }
    }

    private func updateUI(with state: BrowserState) {
        if !urlTextField.isFirstResponder {
            urlTextField.text = state.url?.absoluteString ?? ""
        }

        backButton.isEnabled = state.canGoBack
        forwardButton.isEnabled = state.canGoForward
        progressView.progress = Float(state.progress)
        progressView.isHidden = !state.isLoading && state.progress >= 1.0

        sslBadgeLabel.text = state.isSecure ? "🔒" : "🔓"
        sslBadgeLabel.textColor = state.isSecure ? .systemGreen : .systemGray

        if let error = state.lastError {
            statusLabel.text = "Error: \(error)"
            TestHarnessEngine.shared.record(id: "P", status: .pass, evidence: "Captured navigation error in BrowserState: \(error)")
        } else if state.isLoading {
            statusLabel.text = "Connecting..."
        } else {
            statusLabel.text = "Loaded: \(state.title ?? state.url?.absoluteString ?? "")"
        }
    }

    // MARK: - Setup Top Controls
    private func setupTopControls() {
        sslBadgeLabel.text = "🔓"
        sslBadgeLabel.font = .systemFont(ofSize: 13)
        sslBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        urlTextField.borderStyle = .roundedRect
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.keyboardType = .URL
        urlTextField.returnKeyType = .go
        urlTextField.placeholder = "Enter URL (e.g. https://google.com)"
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false

        goButton.setTitle("Go", for: .normal)
        goButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        goButton.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
        goButton.translatesAutoresizingMaskIntoConstraints = false

        backButton.setTitle("◀", for: .normal)
        backButton.isEnabled = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        forwardButton.setTitle("▶", for: .normal)
        forwardButton.isEnabled = false
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false

        reloadButton.setTitle("↻", for: .normal)
        reloadButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Ready"
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemBlue
    }

    // MARK: - Setup Multi-Tab Bar UI
    private func setupTabBarUI() {
        tabBarScrollView.showsHorizontalScrollIndicator = false
        tabBarScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabStackView.axis = .horizontal
        tabStackView.spacing = 6
        tabStackView.alignment = .center
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabBarScrollView.addSubview(tabStackView)

        newTabButton.setTitle(" ＋ ", for: .normal)
        newTabButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        newTabButton.backgroundColor = .secondarySystemBackground
        newTabButton.layer.cornerRadius = 6
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.addTarget(self, action: #selector(newTabTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            tabStackView.topAnchor.constraint(equalTo: tabBarScrollView.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabBarScrollView.bottomAnchor),
            tabStackView.leadingAnchor.constraint(equalTo: tabBarScrollView.leadingAnchor, constant: 6),
            tabStackView.trailingAnchor.constraint(equalTo: tabBarScrollView.trailingAnchor, constant: -6),
            tabStackView.heightAnchor.constraint(equalTo: tabBarScrollView.heightAnchor)
        ])
    }

    private func rebuildTabBar(tabs: [BrowserTab]) {
        for subview in tabStackView.arrangedSubviews {
            tabStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for tab in tabs {
            let tabPill = makeTabPill(for: tab)
            tabStackView.addArrangedSubview(tabPill)
        }

        // Add '+' button at the end
        tabStackView.addArrangedSubview(newTabButton)
    }

    private func makeTabPill(for tab: BrowserTab) -> UIView {
        let pillView = UIView()
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.layer.cornerRadius = 8
        pillView.layer.masksToBounds = true

        let isActive = (tab.id == tabManager.activeTab?.id)
        if isActive {
            pillView.backgroundColor = .systemBlue
        } else {
            pillView.backgroundColor = .secondarySystemBackground
        }

        // Title Button (Tapping switches tab)
        let titleButton = UIButton(type: .system)
        let titleText = tab.displayTitle.count > 16 ? String(tab.displayTitle.prefix(14)) + "…" : tab.displayTitle
        titleButton.setTitle(titleText, for: .normal)
        titleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular)
        titleButton.setTitleColor(isActive ? .white : .label, for: .normal)
        titleButton.contentHorizontalAlignment = .left
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        titleButton.addAction(UIAction { [weak self] _ in
            self?.tabManager.activateTab(id: tab.id)
        }, for: .touchUpInside)

        // Close Button ('✕')
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        closeButton.setTitleColor(isActive ? .white.withAlphaComponent(0.85) : .secondaryLabel, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.tabManager.closeTab(id: tab.id)
        }, for: .touchUpInside)

        pillView.addSubview(titleButton)
        pillView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            pillView.heightAnchor.constraint(equalToConstant: 28),

            titleButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 8),
            titleButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            titleButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20)
        ])

        return pillView
    }

    @objc private func newTabTapped() {
        tabManager.createTab(url: URL(string: "https://example.com"), activate: true)
    }

    // MARK: - Setup Quick Test Bar
    private func setupQuickTestBar() {
        testUrlsScrollView.showsHorizontalScrollIndicator = false
        testUrlsScrollView.translatesAutoresizingMaskIntoConstraints = false

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

        for url in testURLs {
            let btn = UIButton(type: .system)
            let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
            btn.setTitle(" \(host) ", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            btn.backgroundColor = .secondarySystemBackground
            btn.layer.cornerRadius = 6
            btn.addAction(UIAction { [weak self] _ in
                self?.urlTextField.text = url
                self?.activeBrowser?.open(url)
            }, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    // MARK: - Setup Action Toolbar
    private func setupActionToolbar() {
        actionsScrollView.showsHorizontalScrollIndicator = false
        actionsScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        actionsScrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: actionsScrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: actionsScrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: actionsScrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: actionsScrollView.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: actionsScrollView.heightAnchor)
        ])

        // 1. target="_blank" Policy Toggle
        let targetBlankBtn = UIButton(type: .system)
        targetBlankBtn.setTitle(" _blank Policy ", for: .normal)
        targetBlankBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        targetBlankBtn.backgroundColor = .secondarySystemBackground
        targetBlankBtn.layer.cornerRadius = 6
        targetBlankBtn.addAction(UIAction { [weak self, weak targetBlankBtn] _ in
            guard let self = self, let browser = self.activeBrowser else { return }
            let next: TargetBlankPolicy = (browser.state.targetBlankPolicy == .rerouteSameView) ? .block : .rerouteSameView
            browser.setTargetBlankPolicy(next)
            targetBlankBtn?.setTitle(" _blank: \(next.rawValue) ", for: .normal)
        }, for: .touchUpInside)
        stack.addArrangedSubview(targetBlankBtn)

        // 2. Custom Scheme Policy Toggle
        let schemeBtn = UIButton(type: .system)
        schemeBtn.setTitle(" Scheme Policy ", for: .normal)
        schemeBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        schemeBtn.backgroundColor = .secondarySystemBackground
        schemeBtn.layer.cornerRadius = 6
        schemeBtn.addAction(UIAction { [weak self, weak schemeBtn] _ in
            guard let self = self, let browser = self.activeBrowser else { return }
            let next: CustomSchemePolicy = (browser.state.customSchemePolicy == .observeOnly) ? .blockExternal : .observeOnly
            browser.setCustomSchemePolicy(next)
            schemeBtn?.setTitle(" Schemes: \(next.rawValue) ", for: .normal)
        }, for: .touchUpInside)
        stack.addArrangedSubview(schemeBtn)

        // 3. Inspect Cookies
        let cookiesBtn = UIButton(type: .system)
        cookiesBtn.setTitle(" 🍪 Inspect Cookies ", for: .normal)
        cookiesBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        cookiesBtn.backgroundColor = .secondarySystemBackground
        cookiesBtn.layer.cornerRadius = 6
        cookiesBtn.addAction(UIAction { [weak self] _ in
            self?.activeBrowser?.inspectCookies { _ in }
        }, for: .touchUpInside)
        stack.addArrangedSubview(cookiesBtn)

        // 4. Clear Cache & Cookies
        let clearDataBtn = UIButton(type: .system)
        clearDataBtn.setTitle(" 🗑 Clear Data ", for: .normal)
        clearDataBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        clearDataBtn.backgroundColor = .secondarySystemBackground
        clearDataBtn.layer.cornerRadius = 6
        clearDataBtn.addAction(UIAction { [weak self] _ in
            self?.activeBrowser?.clearWebsiteData()
        }, for: .touchUpInside)
        stack.addArrangedSubview(clearDataBtn)

        // 5. Eval JS Prompt
        let evalBtn = UIButton(type: .system)
        evalBtn.setTitle(" ⚡ Eval JS ", for: .normal)
        evalBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        evalBtn.backgroundColor = .secondarySystemBackground
        evalBtn.layer.cornerRadius = 6
        evalBtn.addAction(UIAction { [weak self] _ in
            self?.promptEvaluateJavaScript()
        }, for: .touchUpInside)
        stack.addArrangedSubview(evalBtn)

        // 6. Test Multi-Tab Suite (V4.3)
        let testMultiTabBtn = UIButton(type: .system)
        testMultiTabBtn.setTitle(" 📑 Test Multi-Tab ", for: .normal)
        testMultiTabBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        testMultiTabBtn.backgroundColor = .systemBlue.withAlphaComponent(0.15)
        testMultiTabBtn.layer.cornerRadius = 6
        testMultiTabBtn.addAction(UIAction { [weak self] _ in
            self?.loadMultiTabTestPage()
        }, for: .touchUpInside)
        stack.addArrangedSubview(testMultiTabBtn)

        // 7. Test LocalStorage & Cookies
        let testStorageBtn = UIButton(type: .system)
        testStorageBtn.setTitle(" 💾 Test Storage ", for: .normal)
        testStorageBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        testStorageBtn.backgroundColor = .secondarySystemBackground
        testStorageBtn.layer.cornerRadius = 6
        testStorageBtn.addAction(UIAction { [weak self] _ in
            self?.loadStorageTestPage()
        }, for: .touchUpInside)
        stack.addArrangedSubview(testStorageBtn)

        // 8. Test Downloads
        let testDownloadBtn = UIButton(type: .system)
        testDownloadBtn.setTitle(" 📥 Test Downloads ", for: .normal)
        testDownloadBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        testDownloadBtn.backgroundColor = .secondarySystemBackground
        testDownloadBtn.layer.cornerRadius = 6
        testDownloadBtn.addAction(UIAction { [weak self] _ in
            self?.loadDownloadTestPage()
        }, for: .touchUpInside)
        stack.addArrangedSubview(testDownloadBtn)

        // 9. Run Automated Local Sanity Suite
        let runSanityBtn = UIButton(type: .system)
        runSanityBtn.setTitle(" 🧪 Run Tests ", for: .normal)
        runSanityBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        runSanityBtn.backgroundColor = .systemGreen.withAlphaComponent(0.2)
        runSanityBtn.layer.cornerRadius = 6
        runSanityBtn.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.statusLabel.text = "Running local sanity tests..."
            TestHarnessEngine.shared.runAutomatedStorageAndSchemeTests(tabManager: self.tabManager) {
                DispatchQueue.main.async {
                    self.statusLabel.text = "Local sanity tests complete. Check Dashboard / Logs."
                }
            }
        }, for: .touchUpInside)
        stack.addArrangedSubview(runSanityBtn)

        // 10. Show Test Results Summary Dashboard
        let resultsDashboardBtn = UIButton(type: .system)
        resultsDashboardBtn.setTitle(" 📊 Test Dashboard ", for: .normal)
        resultsDashboardBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        resultsDashboardBtn.backgroundColor = .systemPurple.withAlphaComponent(0.2)
        resultsDashboardBtn.layer.cornerRadius = 6
        resultsDashboardBtn.addAction(UIAction { [weak self] _ in
            self?.showTestResultsModal()
        }, for: .touchUpInside)
        stack.addArrangedSubview(resultsDashboardBtn)
    }

    private func showTestResultsModal() {
        let cases = TestHarnessEngine.shared.testCases
        var report = "V4.3 WEBKIT TEST RESULTS SUMMARY\n\n"
        for tc in cases {
            report += "[\(tc.id)] \(tc.title): [\(tc.status.rawValue)]\n"
            report += "   Evidence: \(tc.evidence)\n"
            report += "   Real iPad: \(tc.requiresRealDevice ? "YES" : "NO")\n\n"
        }
        let alert = UIAlertController(title: "Test Suite Results", message: report, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Copy / OK", style: .default, handler: { _ in
            UIPasteboard.general.string = report
            BrowserLogger.shared.log(.test, "Test results copied to clipboard.")
        }))
        present(alert, animated: true)
    }

    // MARK: - Setup Diagnostic Log Console
    private func setupLogConsole() {
        logToggleBtn.setTitle("📋 Logs (Show)", for: .normal)
        logToggleBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        logToggleBtn.addTarget(self, action: #selector(toggleLogView), for: .touchUpInside)
        logToggleBtn.translatesAutoresizingMaskIntoConstraints = false

        clearLogBtn.setTitle("Clear", for: .normal)
        clearLogBtn.titleLabel?.font = .systemFont(ofSize: 12)
        clearLogBtn.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)
        clearLogBtn.translatesAutoresizingMaskIntoConstraints = false

        filterLogBtn.setTitle("Filter: ALL", for: .normal)
        filterLogBtn.titleLabel?.font = .systemFont(ofSize: 12)
        filterLogBtn.addTarget(self, action: #selector(cycleLogFilter), for: .touchUpInside)
        filterLogBtn.translatesAutoresizingMaskIntoConstraints = false

        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.backgroundColor = .black
        logTextView.textColor = .systemGreen
        logTextView.layer.cornerRadius = 6
        logTextView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLoggerBinding() {
        BrowserLogger.shared.onLogAdded = { [weak self] entry in
            guard let self = self else { return }
            if self.activeFilter == nil || self.activeFilter == entry.category {
                self.logTextView.text.append(entry.formatted + "\n")
                let bottom = NSRange(location: self.logTextView.text.count - 1, length: 1)
                self.logTextView.scrollRangeToVisible(bottom)
            }
        }
    }

    // MARK: - Layout
    private func setupLayout() {
        let topBarStack = UIStackView(arrangedSubviews: [backButton, forwardButton, reloadButton, sslBadgeLabel, urlTextField, goButton])
        topBarStack.axis = .horizontal
        topBarStack.spacing = 6
        topBarStack.alignment = .center
        topBarStack.translatesAutoresizingMaskIntoConstraints = false

        let logHeaderStack = UIStackView(arrangedSubviews: [logToggleBtn, filterLogBtn, clearLogBtn])
        logHeaderStack.axis = .horizontal
        logHeaderStack.spacing = 8
        logHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(topBarStack)
        view.addSubview(statusLabel)
        view.addSubview(progressView)
        view.addSubview(tabBarScrollView)
        view.addSubview(testUrlsScrollView)
        view.addSubview(actionsScrollView)
        view.addSubview(logHeaderStack)
        view.addSubview(logTextView)

        let safe = view.safeAreaLayoutGuide
        logHeightConstraint = logTextView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Top Control Bar
            topBarStack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            topBarStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            topBarStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            topBarStack.heightAnchor.constraint(equalToConstant: 36),

            backButton.widthAnchor.constraint(equalToConstant: 30),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),
            reloadButton.widthAnchor.constraint(equalToConstant: 30),
            goButton.widthAnchor.constraint(equalToConstant: 36),

            // Status & SSL Label
            statusLabel.topAnchor.constraint(equalTo: topBarStack.bottomAnchor, constant: 2),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),

            // Progress View
            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            // Multi-Tab Bar UI
            tabBarScrollView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 4),
            tabBarScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarScrollView.heightAnchor.constraint(equalToConstant: 32),

            // Quick Test URLs Bar
            testUrlsScrollView.topAnchor.constraint(equalTo: tabBarScrollView.bottomAnchor, constant: 4),
            testUrlsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            testUrlsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            testUrlsScrollView.heightAnchor.constraint(equalToConstant: 30),

            // Action Toolbar
            actionsScrollView.topAnchor.constraint(equalTo: testUrlsScrollView.bottomAnchor, constant: 4),
            actionsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionsScrollView.heightAnchor.constraint(equalToConstant: 30),

            // Web Container View (Hosting all active and hidden WKWebViews)
            webContainerView.topAnchor.constraint(equalTo: actionsScrollView.bottomAnchor, constant: 4),
            webContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webContainerView.bottomAnchor.constraint(equalTo: logHeaderStack.topAnchor, constant: -4),

            // Log Console Header
            logHeaderStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            logHeaderStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            logHeaderStack.heightAnchor.constraint(equalToConstant: 28),
            logHeaderStack.bottomAnchor.constraint(equalTo: logTextView.topAnchor, constant: -2),

            // Log Console Body
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            logTextView.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),
            logHeightConstraint!
        ])
    }

    // MARK: - Navigation Actions
    @objc private func goTapped() {
        urlTextField.resignFirstResponder()
        if let text = urlTextField.text {
            activeBrowser?.open(text)
        }
    }

    @objc private func backTapped() {
        activeBrowser?.back()
    }

    @objc private func forwardTapped() {
        activeBrowser?.forward()
    }

    @objc private func reloadTapped() {
        activeBrowser?.reload()
    }

    @objc private func toggleLogView() {
        isLogExpanded.toggle()
        logHeightConstraint?.constant = isLogExpanded ? 180 : 0
        logToggleBtn.setTitle(isLogExpanded ? "📋 Logs (Hide)" : "📋 Logs (Show)", for: .normal)
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func clearLogs() {
        BrowserLogger.shared.clear()
        logTextView.text = ""
    }

    @objc private func cycleLogFilter() {
        let allFilters: [LogCategory?] = [nil] + LogCategory.allCases.map { Optional($0) }
        let currentIndex = allFilters.firstIndex(where: { $0 == activeFilter }) ?? 0
        let nextIndex = (currentIndex + 1) % allFilters.count
        activeFilter = allFilters[nextIndex]

        let title = activeFilter == nil ? "Filter: ALL" : "Filter: \(activeFilter!.rawValue)"
        filterLogBtn.setTitle(title, for: .normal)
        rebuildLogDisplay()
    }

    private func rebuildLogDisplay() {
        let entries = BrowserLogger.shared.getFilteredEntries(category: activeFilter)
        logTextView.text = entries.map { $0.formatted }.joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
        if !logTextView.text.isEmpty {
            let bottom = NSRange(location: logTextView.text.count - 1, length: 1)
            logTextView.scrollRangeToVisible(bottom)
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
            BrowserLogger.shared.log(.js, "Eval: \(code)")
            self.activeBrowser?.evaluateJavaScript(code) { result in
                switch result {
                case .success(let val):
                    BrowserLogger.shared.log(.js, "Result: \(val ?? "undefined / void")")
                case .failure(let err):
                    BrowserLogger.shared.log(.error, "JS Error: \(err.localizedDescription)")
                }
            }
        }))
        present(alert, animated: true)
    }

    // MARK: - Test Suites
    private func loadMultiTabTestPage() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>V4.3 Multi-Tab Test Suite</title>
            <style>
                body { font-family: -apple-system, sans-serif; padding: 20px; line-height: 1.6; }
                .card { background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 14px; margin-bottom: 12px; }
                a.btn, button, input[type=submit] { display: inline-block; padding: 8px 14px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 13px; margin-top: 6px; cursor: pointer; }
                h4 { margin: 0 0 6px 0; }
                p { margin: 0; font-size: 13px; color: #555; }
                .result { margin-top: 8px; font-family: monospace; font-size: 12px; background: #eee; padding: 6px; border-radius: 4px; }
            </style>
        </head>
        <body>
            <h3>V4.3 Multi-Tab & Window Test Suite</h3>
            <p style="margin-bottom: 16px;">Test popup interception, target="_blank", POST body forwarding, shared cookies, and window.close().</p>

            <div class="card">
                <h4>1. target="_blank" Link</h4>
                <p>Standard hyperlink with target="_blank". Should open in a new browser tab.</p>
                <a class="btn" href="https://example.com" target="_blank">Open example.com in New Tab</a>
            </div>

            <div class="card">
                <h4>2. window.open() Immediate</h4>
                <p>JavaScript window.open call triggered synchronously by user tap.</p>
                <button onclick="window.open('https://example.com', '_blank')">Run window.open()</button>
            </div>

            <div class="card">
                <h4>3. window.open() Delayed (1000ms)</h4>
                <p>Testing popup creation after asynchronous delay (setTimeout).</p>
                <button onclick="delayedOpen()">Delayed window.open (1s)</button>
                <div id="delayStatus" class="result" style="display:none;">Waiting 1 second...</div>
            </div>

            <div class="card">
                <h4>4. Form POST to New Tab</h4>
                <p>Form submission with method="POST" and target="_blank". Verifies POST body preservation across tabs.</p>
                <form action="https://httpbin.org/post" method="POST" target="_blank">
                    <input type="hidden" name="testKey" value="V4.3_MultiTab_Form_Value">
                    <input type="hidden" name="submittedAt" value="Obsidian_Native_Browser">
                    <input type="submit" value="Submit POST Form to New Tab">
                </form>
            </div>

            <div class="card">
                <h4>5. Shared Storage & Cookies Across Tabs</h4>
                <p>Verify that localStorage and cookies are shared in real-time between tabs under the shared WKWebsiteDataStore.</p>
                <button onclick="writeSharedData()">Write Shared Token</button>
                <button onclick="readSharedData()">Read Shared Token</button>
                <div id="storageResult" class="result">Storage output will appear here</div>
            </div>

            <div class="card">
                <h4>6. window.close() Self-Termination</h4>
                <p>Attempts to close current tab via JavaScript window.close().</p>
                <button onclick="window.close()" style="background:#dc3545;">Execute window.close()</button>
            </div>

            <script>
                function delayedOpen() {
                    const st = document.getElementById('delayStatus');
                    st.style.display = 'block';
                    st.innerText = 'Timer started: window.open in 1s...';
                    setTimeout(function() {
                        st.innerText = 'Opening popup window now...';
                        window.open('https://example.com', '_blank');
                    }, 1000);
                }

                function writeSharedData() {
                    const stamp = 'tab_token_' + Date.now();
                    localStorage.setItem('v43_shared_token', stamp);
                    document.cookie = 'v43_cookie=' + encodeURIComponent(stamp) + '; path=/; max-age=86400';
                    document.getElementById('storageResult').innerText = 'Written: ' + stamp + '\\nNow open a new tab or switch tabs to read it!';
                    console.log('Wrote shared token:', stamp);
                }

                function readSharedData() {
                    const token = localStorage.getItem('v43_shared_token');
                    const cookie = document.cookie;
                    document.getElementById('storageResult').innerText = 'LS Token: ' + token + '\\nCookie: ' + cookie;
                    console.log('Read shared token:', token);
                }
            </script>
        </body>
        </html>
        """
        activeBrowser?.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    private func loadStorageTestPage() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Storage & Cookie Test</title>
        </head>
        <body style="font-family: -apple-system, sans-serif; padding: 20px; line-height: 1.5;">
            <h3>Storage & Cookie Persistence PoC</h3>
            <p>Write to document.cookie and localStorage, then inspect with native toolbar.</p>
            <button onclick="writeStorage()" style="padding:8px 14px; background:#007aff; color:#fff; border:none; border-radius:6px; margin-right:8px;">1. Write Storage & Cookie</button>
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
        activeBrowser?.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    private func loadDownloadTestPage() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>V4.2 Download Engine Test Suite</title>
            <style>
                body { font-family: -apple-system, sans-serif; padding: 20px; line-height: 1.6; }
                .card { background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 14px; margin-bottom: 12px; }
                a.btn, button { display: inline-block; padding: 8px 14px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 13px; margin-top: 6px; cursor: pointer; }
                h4 { margin: 0 0 6px 0; }
                p { margin: 0; font-size: 13px; color: #555; }
            </style>
        </head>
        <body>
            <h3>V4.2 Native Download Engine Test Suite</h3>
            <p style="margin-bottom: 16px;">Test WKDownload interception, filename sanitization, unicode, and sandbox persistence.</p>

            <div class="card">
                <h4>1. Plain Text File (.txt)</h4>
                <p>Data URI text download with suggested filename.</p>
                <a class="btn" href="data:text/plain;charset=utf-8,Hello%20from%20Obsidian%20Native%20Browser%20V4.2%20Download%20Engine!" download="notes.txt">Download notes.txt</a>
            </div>

            <div class="card">
                <h4>2. HTML Report Document (.html)</h4>
                <p>HTML formatted document download.</p>
                <a class="btn" href="data:text/html;charset=utf-8,%3Ch1%3EObsidian%20V4.2%20Report%3C%2Fh1%3E%3Cp%3EDownload%20engine%20test%20passed.%3C%2Fp%3E" download="report.html">Download report.html</a>
            </div>

            <div class="card">
                <h4>3. Unicode Filename (.txt)</h4>
                <p>Testing non-ASCII characters in filename.</p>
                <a class="btn" href="data:text/plain;charset=utf-8,Ogrenci%20belgesi%20ornek%20icerik" download="öğrenci_belgesi_2026.txt">Download öğrenci_belgesi_2026.txt</a>
            </div>

            <div class="card">
                <h4>4. Filename With Spaces (.txt)</h4>
                <p>Testing filenames containing spaces and parentheses.</p>
                <a class="btn" href="data:text/plain;charset=utf-8,Test%20Content" download="My Project Report (Draft 2026).txt">Download My Project Report (Draft 2026).txt</a>
            </div>

            <div class="card">
                <h4>5. Duplicate Filename Test (.txt)</h4>
                <p>Repeatedly click to test collision auto-indexing: notes.txt -> notes (1).txt</p>
                <a class="btn" href="data:text/plain;charset=utf-8,Duplicate%20Index%20Test" download="notes.txt">Download duplicate notes.txt</a>
            </div>

            <div class="card">
                <h4>6. Simulated Binary Blob (.bin)</h4>
                <p>Dynamically generated binary array blob.</p>
                <button onclick="downloadBlob()">Generate & Download binary.bin</button>
            </div>

            <script>
                function downloadBlob() {
                    const bytes = new Uint8Array([0x50, 0x4B, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x00]);
                    const blob = new Blob([bytes], { type: 'application/octet-stream' });
                    const url = URL.createObjectURL(blob);
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = 'archive.bin';
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    URL.revokeObjectURL(url);
                    console.log('Triggered blob download: archive.bin');
                }
            </script>
        </body>
        </html>
        """
        activeBrowser?.loadHTMLString(html, baseURL: URL(string: "https://local-test.poc/"))
    }

    // MARK: - UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        goTapped()
        return true
    }

    // MARK: - BrowserUIDialogPresenter
    func presentAlert(title: String, message: String, completion: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion() }))
        present(alert, animated: true)
    }

    func presentConfirm(title: String, message: String, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completion(false) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion(true) }))
        present(alert, animated: true)
    }

    func presentPrompt(title: String, prompt: String, defaultText: String?, completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: title, message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completion(nil) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] _ in
            completion(alert?.textFields?.first?.text)
        }))
        present(alert, animated: true)
    }
}
