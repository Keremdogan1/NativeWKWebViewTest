import Foundation

/// Policy for handling target="_blank" and window.open requests
public enum TargetBlankPolicy: String, CaseIterable {
    case rerouteSameView = "Reroute"
    case block = "Block"
}

/// Policy for handling custom app URL schemes (e.g. vnd.youtube:, googlesearch:)
public enum CustomSchemePolicy: String, CaseIterable {
    case observeOnly = "Allow/Log"
    case blockExternal = "Block Apps"
}

/// Consolidated, observable browser state
public struct BrowserState: Equatable {
    public var url: URL?
    public var title: String?
    public var isLoading: Bool
    public var progress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isSecure: Bool
    public var targetBlankPolicy: TargetBlankPolicy
    public var customSchemePolicy: CustomSchemePolicy
    public var lastError: String?

    public init(
        url: URL? = nil,
        title: String? = nil,
        isLoading: Bool = false,
        progress: Double = 0.0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isSecure: Bool = false,
        targetBlankPolicy: TargetBlankPolicy = .rerouteSameView,
        customSchemePolicy: CustomSchemePolicy = .observeOnly,
        lastError: String? = nil
    ) {
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.progress = progress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isSecure = isSecure
        self.targetBlankPolicy = targetBlankPolicy
        self.customSchemePolicy = customSchemePolicy
        self.lastError = lastError
    }

    public static let initial = BrowserState()
}

/// Observable browser events for loose coupling
public enum BrowserEvent {
    case navigationStarted(url: URL?)
    case navigationFinished(url: URL?, title: String?)
    case navigationFailed(error: Error)
    case serverRedirect(url: URL?)
    case urlChanged(URL?)
    case titleChanged(String?)
    case loadingChanged(Bool)
    case progressChanged(Double)
    case canGoBackChanged(Bool)
    case canGoForwardChanged(Bool)
    case securityChanged(isSecure: Bool)
    case webContentProcessTerminated(reloaded: Bool)
    case popupRequested(url: URL?, policy: TargetBlankPolicy)
    case schemeRequested(scheme: String, url: URL?, allowed: Bool)
    case jsMessageReceived(level: String, message: String)
    case downloadStarted(id: UUID, filename: String, url: URL?)
    case downloadProgressChanged(id: UUID, progress: Double)
    case downloadCompleted(id: UUID, filename: String, fileURL: URL)
    case downloadFailed(id: UUID, error: String)
    case downloadCancelled(id: UUID)
}
