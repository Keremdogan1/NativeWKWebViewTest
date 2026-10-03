import Foundation
import UIKit
import WebKit

/// Model and container representing an open browser tab
public final class BrowserTab: Identifiable, Equatable {
    public let id: UUID
    public let browser: NativeBrowser
    public var isActive: Bool = false
    public let createdAt: Date

    public var title: String? {
        return browser.state.title
    }

    public var url: URL? {
        return browser.state.url
    }

    public var displayTitle: String {
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        if let host = url?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        if let u = url?.absoluteString, !u.isEmpty && u != "about:blank" {
            return u
        }
        return "New Tab"
    }

    public var isLoading: Bool {
        return browser.state.isLoading
    }

    public var canGoBack: Bool {
        return browser.state.canGoBack
    }

    public var canGoForward: Bool {
        return browser.state.canGoForward
    }

    public var progress: Double {
        return browser.state.progress
    }

    public init(id: UUID = UUID(), browser: NativeBrowser, isActive: Bool = false) {
        self.id = id
        self.browser = browser
        self.isActive = isActive
        self.createdAt = Date()
    }

    public static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        return lhs.id == rhs.id
    }
}
