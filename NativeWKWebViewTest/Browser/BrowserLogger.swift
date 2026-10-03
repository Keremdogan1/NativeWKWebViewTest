import Foundation

/// Diagnostic Log Categories for granular filtering
public enum LogCategory: String, CaseIterable {
    case nav = "[NAV]"
    case resp = "[RESP]"
    case ui = "[UI]"
    case js = "[JS]"
    case cookie = "[COOKIE]"
    case scheme = "[SCHEME]"
    case error = "[ERROR]"
    case state = "[STATE]"
    case test = "[TEST]"
}

/// A structured entry in the browser diagnostic log
public struct LogEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let category: LogCategory
    public let message: String
    public let formatted: String

    public init(category: LogCategory, message: String) {
        self.timestamp = Date()
        self.category = category
        self.message = message

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SS"
        let tsStr = formatter.string(from: self.timestamp)
        self.formatted = "[\(tsStr)] \(category.rawValue) \(message)"
    }
}

/// Thread-safe central logger for Browser engine diagnostics
public final class BrowserLogger {
    public static let shared = BrowserLogger()

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    public var onLogAdded: ((LogEntry) -> Void)?

    private init() {}

    public func log(_ category: LogCategory, _ message: String) {
        let entry = LogEntry(category: category, message: message)

        lock.lock()
        entries.append(entry)
        lock.unlock()

        print(entry.formatted)

        DispatchQueue.main.async { [weak self] in
            self?.onLogAdded?(entry)
        }
    }

    public func getAllEntries() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func getFilteredEntries(category: LogCategory?) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let category = category else { return entries }
        return entries.filter { $0.category == category }
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
