import Foundation
import WebKit

/// Manager responsible for handling WKDownload instances and file system persistence
public final class BrowserDownloadManager: NSObject, WKDownloadDelegate {

    // MARK: - Properties
    private let lock = NSLock()
    private var downloads: [UUID: BrowserDownload] = [:]
    private var activeWKDownloads: [UUID: WKDownload] = [:]
    private var downloadIDMap: [ObjectIdentifier: UUID] = [:]
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]

    public weak var browser: NativeBrowser?

    public var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    public var onDownloadUpdated: ((BrowserDownload) -> Void)?

    // MARK: - Initialization
    public init(browser: NativeBrowser? = nil) {
        self.browser = browser
        super.init()
    }

    // MARK: - Registration
    @discardableResult
    public func registerDownload(_ wkDownload: WKDownload, from response: URLResponse?) -> BrowserDownload {
        wkDownload.delegate = self

        let id = UUID()
        let sourceURL = response?.url ?? wkDownload.originalRequest?.url
        let mimeType = response?.mimeType
        let suggested = response?.suggestedFilename ?? "download"
        let totalExpected = response?.expectedContentLength ?? -1

        var downloadItem = BrowserDownload(
            id: id,
            sourceURL: sourceURL,
            suggestedFilename: suggested,
            destinationURL: nil,
            mimeType: mimeType,
            progress: 0.0,
            totalBytesExpected: totalExpected,
            bytesReceived: 0,
            state: .pending,
            startDate: Date()
        )

        lock.lock()
        downloads[id] = downloadItem
        activeWKDownloads[id] = wkDownload
        downloadIDMap[ObjectIdentifier(wkDownload)] = id
        lock.unlock()

        BrowserLogger.shared.log(.nav, "[DOWNLOAD] Registered download: \(suggested) (URL: \(sourceURL?.absoluteString ?? "unknown"))")
        browser?.emitEvent(.downloadStarted(id: id, filename: suggested, url: sourceURL))
        notifyUpdate(downloadItem)

        return downloadItem
    }

    // MARK: - Query & Control
    public func getAllDownloads() -> [BrowserDownload] {
        lock.lock()
        defer { lock.unlock() }
        return Array(downloads.values).sorted(by: { $0.startDate > $1.startDate })
    }

    public func getDownload(id: UUID) -> BrowserDownload? {
        lock.lock()
        defer { lock.unlock() }
        return downloads[id]
    }

    public func cancelDownload(id: UUID) {
        lock.lock()
        guard let wkDownload = activeWKDownloads[id], var item = downloads[id] else {
            lock.unlock()
            return
        }
        lock.unlock()

        BrowserLogger.shared.log(.nav, "[DOWNLOAD] Cancelling download: \(item.suggestedFilename)")
        wkDownload.cancel { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            item.state = .cancelled
            self.downloads[id] = item
            self.activeWKDownloads.removeValue(forKey: id)
            self.progressObservations.removeValue(forKey: id)?.invalidate()
            self.lock.unlock()

            // Remove partially written file if destination was set
            if let dest = item.destinationURL, FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }

            self.browser?.emitEvent(.downloadCancelled(id: id))
            self.notifyUpdate(item)
        }
    }

    // MARK: - WKDownloadDelegate

    // 1. Destination Resolution & Security
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let objID = ObjectIdentifier(download)
        lock.lock()
        guard let id = downloadIDMap[objID], var item = downloads[id] else {
            lock.unlock()
            BrowserLogger.shared.log(.error, "[DOWNLOAD] Unknown download instance encountered.")
            completionHandler(nil)
            return
        }
        lock.unlock()

        // Sanitize filename & guarantee safe sandbox path
        let sanitizedName = sanitizeFilename(suggestedFilename)
        let destinationURL = generateUniqueDestination(filename: sanitizedName)

        // Security check: must strictly be inside downloadsDirectory
        guard destinationURL.standardizedFileURL.path.hasPrefix(downloadsDirectory.standardizedFileURL.path) else {
            BrowserLogger.shared.log(.error, "[DOWNLOAD] SECURITY BLOCKED: Destination escapes sandbox downloads directory: \(destinationURL.path)")
            completionHandler(nil)
            return
        }

        lock.lock()
        item.destinationURL = destinationURL
        item.suggestedFilename = sanitizedName
        item.mimeType = response.mimeType
        item.totalBytesExpected = response.expectedContentLength
        item.state = .downloading
        downloads[id] = item

        // Setup Progress Observer on NSProgress
        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, _ in
            guard let self = self else { return }
            let frac = prog.fractionCompleted
            self.lock.lock()
            if var d = self.downloads[id] {
                d.progress = frac
                d.bytesReceived = prog.completedUnitCount
                self.downloads[id] = d
                self.lock.unlock()
                self.browser?.emitEvent(.downloadProgressChanged(id: id, progress: frac))
                self.notifyUpdate(d)
            } else {
                self.lock.unlock()
            }
        }
        progressObservations[id] = observation
        lock.unlock()

        BrowserLogger.shared.log(.nav, "[DOWNLOAD] Starting: \(sanitizedName) -> \(destinationURL.lastPathComponent) [MIME: \(response.mimeType ?? "unknown")]")
        notifyUpdate(item)
        completionHandler(destinationURL)
    }

    // 2. Completion
    public func downloadDidFinish(_ download: WKDownload) {
        let objID = ObjectIdentifier(download)
        lock.lock()
        guard let id = downloadIDMap[objID], var item = downloads[id] else {
            lock.unlock()
            return
        }
        item.state = .completed
        item.progress = 1.0
        downloads[id] = item
        activeWKDownloads.removeValue(forKey: id)
        progressObservations.removeValue(forKey: id)?.invalidate()
        lock.unlock()

        let destStr = item.destinationURL?.lastPathComponent ?? item.suggestedFilename
        BrowserLogger.shared.log(.nav, "[DOWNLOAD] SUCCESS: \(destStr) downloaded to Documents/Downloads")
        if let dest = item.destinationURL {
            browser?.emitEvent(.downloadCompleted(id: id, filename: item.suggestedFilename, fileURL: dest))
        }
        notifyUpdate(item)
    }

    // 3. Failure
    public func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let objID = ObjectIdentifier(download)
        lock.lock()
        guard let id = downloadIDMap[objID], var item = downloads[id] else {
            lock.unlock()
            return
        }
        item.state = .failed
        item.errorDescription = error.localizedDescription
        downloads[id] = item
        activeWKDownloads.removeValue(forKey: id)
        progressObservations.removeValue(forKey: id)?.invalidate()
        lock.unlock()

        BrowserLogger.shared.log(.error, "[DOWNLOAD] FAILED: \(item.suggestedFilename) - Error: \(error.localizedDescription)")
        browser?.emitEvent(.downloadFailed(id: id, error: error.localizedDescription))
        notifyUpdate(item)
    }

    // 4. Redirection
    public func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        let objID = ObjectIdentifier(download)
        let redirectURL = request.url?.absoluteString ?? "unknown"
        BrowserLogger.shared.log(.nav, "[DOWNLOAD] REDIRECT: HTTP \(response.statusCode) -> \(redirectURL)")

        lock.lock()
        if let id = downloadIDMap[objID], var item = downloads[id] {
            item.sourceURL = request.url
            downloads[id] = item
        }
        lock.unlock()

        decisionHandler(.allow)
    }

    // 5. Authentication Challenge
    public func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        BrowserLogger.shared.log(.nav, "[DOWNLOAD] SSL/Auth challenge received for download.")
        completionHandler(.performDefaultHandling, nil)
    }

    // MARK: - Filename Sanitization & Collision Prevention
    public func sanitizeFilename(_ rawName: String) -> String {
        // Strip path traversal indicators
        var cleaned = rawName.replacingOccurrences(of: "..", with: "")
        cleaned = cleaned.replacingOccurrences(of: "/", with: "_")
        cleaned = cleaned.replacingOccurrences(of: "\\", with: "_")

        // Strip illegal / control characters
        let invalidCharacters = CharacterSet(charactersIn: ":*?\"<>|\0")
        cleaned = cleaned.components(separatedBy: invalidCharacters).joined(separator: "_")

        // Strip leading dots to prevent creating hidden files
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return "download.bin"
        }
        return cleaned
    }

    private func generateUniqueDestination(filename: String) -> URL {
        let baseDir = downloadsDirectory
        let fileExtension = (filename as NSString).pathExtension
        let nameWithoutExtension = (filename as NSString).deletingPathExtension

        var destination = baseDir.appendingPathComponent(filename)
        var counter = 1

        while FileManager.default.fileExists(atPath: destination.path) {
            let newName: String
            if fileExtension.isEmpty {
                newName = "\(nameWithoutExtension) (\(counter))"
            } else {
                newName = "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
            }
            destination = baseDir.appendingPathComponent(newName)
            counter += 1
        }

        return destination
    }

    private func notifyUpdate(_ download: BrowserDownload) {
        DispatchQueue.main.async { [weak self] in
            self?.onDownloadUpdated?(download)
        }
    }
}
