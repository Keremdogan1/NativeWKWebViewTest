import Foundation

/// Lifecycle states of a browser download operation
public enum DownloadState: String, CaseIterable, Equatable {
    case pending = "Pending"
    case downloading = "Downloading"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

/// Model representing a single file download task
public struct BrowserDownload: Identifiable, Equatable {
    public let id: UUID
    public var sourceURL: URL?
    public var suggestedFilename: String
    public var destinationURL: URL?
    public var mimeType: String?
    public var progress: Double // Normalized 0.0 ... 1.0
    public var totalBytesExpected: Int64
    public var bytesReceived: Int64
    public var state: DownloadState
    public var errorDescription: String?
    public let startDate: Date

    public init(
        id: UUID = UUID(),
        sourceURL: URL?,
        suggestedFilename: String,
        destinationURL: URL? = nil,
        mimeType: String? = nil,
        progress: Double = 0.0,
        totalBytesExpected: Int64 = 0,
        bytesReceived: Int64 = 0,
        state: DownloadState = .pending,
        errorDescription: String? = nil,
        startDate: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.suggestedFilename = suggestedFilename
        self.destinationURL = destinationURL
        self.mimeType = mimeType
        self.progress = progress
        self.totalBytesExpected = totalBytesExpected
        self.bytesReceived = bytesReceived
        self.state = state
        self.errorDescription = errorDescription
        self.startDate = startDate
    }
}
