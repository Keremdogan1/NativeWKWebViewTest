import Foundation
import UIKit
import WebKit

/// Manager orchestrating multi-tab lifecycle, active tab selection, and popup windows
public final class BrowserTabManager: NSObject {

    // MARK: - Properties
    public private(set) var tabs: [BrowserTab] = []
    public private(set) var activeTab: BrowserTab?

    public weak var containerView: UIView?
    public weak var dialogPresenter: BrowserUIDialogPresenter?

    public var onTabsChanged: (([BrowserTab]) -> Void)?
    public var onActiveTabChanged: ((BrowserTab?) -> Void)?
    public var onDownloadUpdated: ((BrowserDownload) -> Void)?

    // MARK: - Initialization
    public init(containerView: UIView? = nil) {
        self.containerView = containerView
        super.init()
    }

    // MARK: - Tab Creation & Lifecycle
    @discardableResult
    public func createTab(
        url: URL? = nil,
        activate: Bool = true,
        customConfiguration: WKWebViewConfiguration? = nil
    ) -> BrowserTab {
        let config = customConfiguration ?? defaultConfiguration()

        let browser = NativeBrowser(configuration: config)
        browser.tabManager = self
        browser.dialogPresenter = dialogPresenter

        let tab = BrowserTab(browser: browser, isActive: false)
        tabs.append(tab)

        if let container = containerView {
            let bView = browser.view
            bView.translatesAutoresizingMaskIntoConstraints = false
            bView.isHidden = true
            container.addSubview(bView)

            NSLayoutConstraint.activate([
                bView.topAnchor.constraint(equalTo: container.topAnchor),
                bView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }

        // Forward state updates from individual tabs
        browser.onStateChanged = { [weak self, weak tab] _ in
            guard let self = self, let tab = tab else { return }
            self.onTabsChanged?(self.tabs)
            if tab == self.activeTab {
                self.onActiveTabChanged?(tab)
            }
        }

        browser.downloadManager.onDownloadUpdated = { [weak self] download in
            self?.onDownloadUpdated?(download)
        }

        if let targetURL = url {
            browser.open(targetURL)
        }

        BrowserLogger.shared.log(.state, "Created tab [\(tab.id.uuidString.prefix(6))] (Total tabs: \(tabs.count))")
        onTabsChanged?(tabs)

        if activate || activeTab == nil {
            activateTab(id: tab.id)
        }

        return tab
    }

    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingTab = tabs[index]
        let wasActive = (closingTab == activeTab)

        BrowserLogger.shared.log(.state, "Closing tab [\(closingTab.id.uuidString.prefix(6))] - '\(closingTab.displayTitle)'")

        // Clean up WebKit resources
        closingTab.browser.close()
        closingTab.browser.view.removeFromSuperview()

        tabs.remove(at: index)

        if wasActive {
            if !tabs.isEmpty {
                let nextIndex = min(index, tabs.count - 1)
                let nextTab = tabs[nextIndex]
                activateTab(id: nextTab.id)
            } else {
                activeTab = nil
                // If the last tab was closed, spawn a clean default tab so UI never breaks
                createTab(url: URL(string: "https://example.com"), activate: true)
                return
            }
        }

        onTabsChanged?(tabs)
    }

    public func activateTab(id: UUID) {
        guard let targetTab = tabs.first(where: { $0.id == id }) else { return }

        for tab in tabs {
            let isCurrent = (tab.id == id)
            tab.isActive = isCurrent
            tab.browser.setVisible(isCurrent)
        }

        activeTab = targetTab
        BrowserLogger.shared.log(.state, "Activated tab [\(targetTab.id.uuidString.prefix(6))] - '\(targetTab.displayTitle)'")
        onActiveTabChanged?(targetTab)
        onTabsChanged?(tabs)
    }

    public func tab(for id: UUID) -> BrowserTab? {
        return tabs.first(where: { $0.id == id })
    }

    // MARK: - Popup / Window.open Handling
    public func handlePopupRequest(
        configuration: WKWebViewConfiguration,
        navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let targetUrl = navigationAction.request.url?.absoluteString ?? "delayed"
        BrowserLogger.shared.log(.ui, "BrowserTabManager: Intercepted popup window for URL: \(targetUrl)")

        // WebKit requires returning a WKWebView initialized with the exact configuration supplied
        let newTab = createTab(url: nil, activate: true, customConfiguration: configuration)
        return newTab.browser.webView
    }

    // MARK: - Configuration Helper
    private func defaultConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        return config
    }
}
