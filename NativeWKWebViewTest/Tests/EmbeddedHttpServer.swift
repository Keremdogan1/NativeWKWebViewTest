import Foundation
import Network

/// Minimal embedded HTTP server running on 127.0.0.1 (loopback) to verify POST body preservation in WKWebView
public final class EmbeddedHttpServer {

    public static let shared = EmbeddedHttpServer()

    public private(set) var isRunning = false
    public private(set) var port: UInt16 = 0
    public var serverURL: URL? {
        guard isRunning, port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/verify-post")
    }

    public var onPostPayloadReceived: ((String, Bool) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.nativebrowser.httpserver", qos: .userInitiated)
    private var activeConnections: [NWConnection] = []

    public static let expectedTestKey = "V4_3_POST_TEST"
    public static let expectedTestValue = "POST_BODY_PRESERVED"

    private init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle
    public func start(preferredPort: UInt16 = 8089, completion: ((Result<UInt16, Error>) -> Void)? = nil) {
        guard !isRunning else {
            completion?(.success(port))
            return
        }

        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            // Try preferred port first, or ephemeral port
            let portToUse = NWEndpoint.Port(rawValue: preferredPort) ?? .any
            let newListener = try NWListener(using: params, on: portToUse)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let actualPort = self.listener?.port?.rawValue {
                        self.port = actualPort
                        self.isRunning = true
                        BrowserLogger.shared.log(.test, "EmbeddedHttpServer READY on http://127.0.0.1:\(actualPort)")
                        completion?(.success(actualPort))
                    }
                case .failed(let error):
                    BrowserLogger.shared.log(.error, "EmbeddedHttpServer FAILED: \(error.localizedDescription)")
                    self.stop()
                    completion?(.failure(error))
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            self.listener = newListener
            newListener.start(queue: queue)

        } catch {
            BrowserLogger.shared.log(.error, "Failed to start NWListener: \(error.localizedDescription)")
            completion?(.failure(error))
        }
    }

    public func stop() {
        guard isRunning || listener != nil else { return }
        BrowserLogger.shared.log(.test, "Stopping EmbeddedHttpServer...")

        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()

        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0
        BrowserLogger.shared.log(.test, "EmbeddedHttpServer stopped.")
    }

    // MARK: - Connection Handling
    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if state == .cancelled || state == .failed(NWError.posix(.ECANCELED)) {
                if let conn = connection {
                    self?.activeConnections.removeAll(where: { $0 === conn })
                }
            }
        }

        connection.start(queue: queue)
        receiveData(from: connection, accumulated: Data())
    }

    private func receiveData(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let conn = connection else { return }

            var buffer = accumulated
            if let data = data, !data.isEmpty {
                buffer.append(data)
            }

            if let requestString = String(data: buffer, encoding: .utf8), requestString.contains("\r\n\r\n") || requestString.contains("\n\n") {
                // Header boundary found; process request
                self.processHTTPRequest(requestString, connection: conn)
            } else if isComplete || error != nil {
                // Connection closed prematurely
                conn.cancel()
            } else {
                // Continue accumulating data
                self.receiveData(from: conn, accumulated: buffer)
            }
        }
    }

    // MARK: - HTTP Request Parsing & Verification
    private func processHTTPRequest(_ rawRequest: String, connection: NWConnection) {
        let delimiter = rawRequest.contains("\r\n\r\n") ? "\r\n\r\n" : "\n\n"
        let parts = rawRequest.components(separatedBy: delimiter)
        let headerPart = parts.first ?? ""
        let bodyPart = parts.dropFirst().joined(separator: delimiter)

        let lines = headerPart.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Empty request\"}")
            return
        }

        let requestTokens = requestLine.components(separatedBy: " ")
        guard requestTokens.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Malformed request line\"}")
            return
        }

        let method = requestTokens[0]
        let path = requestTokens[1]

        BrowserLogger.shared.log(.test, "[HTTP] \(method) \(path) | Body length: \(bodyPart.utf8.count) bytes")

        if method == "POST" && path.starts(with: "/verify-post") {
            let receivedBody = bodyPart.trimmingCharacters(in: .whitespacesAndNewlines)
            BrowserLogger.shared.log(.test, "POST body received: \(receivedBody)")

            // Check deterministic payload
            let hasKey = receivedBody.contains("testKey=\(EmbeddedHttpServer.expectedTestKey)")
            let hasVal = receivedBody.contains("testValue=\(EmbeddedHttpServer.expectedTestValue)")
            let isVerified = (hasKey && hasVal)

            let resultStatus = isVerified ? "PASS" : "FAIL"
            let evidence = "POST body parsed: \(receivedBody) (KeyMatch=\(hasKey), ValMatch=\(hasVal))"

            DispatchQueue.main.async { [weak self] in
                self?.onPostPayloadReceived?(receivedBody, isVerified)
                TestHarnessEngine.shared.record(
                    id: "C",
                    status: isVerified ? .passRuntime : .fail,
                    evidence: "[LOCAL HTTP SERVER] \(evidence)"
                )
            }

            let jsonResponse = """
            {
                "status": "\(resultStatus)",
                "verified": \(isVerified),
                "receivedBody": "\(receivedBody)",
                "expectedKey": "\(EmbeddedHttpServer.expectedTestKey)",
                "expectedValue": "\(EmbeddedHttpServer.expectedTestValue)",
                "server": "Network.framework NWListener embedded"
            }
            """
            sendResponse(connection: connection, statusCode: 200, body: jsonResponse)
        } else {
            // Fallback for non-POST or other paths
            sendResponse(connection: connection, statusCode: 200, body: "{\"server\":\"V4.3 Embedded Server Active\",\"method\":\"\(method)\"}")
        }
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let responseHeader = "HTTP/1.1 \(statusCode) OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var fullData = responseHeader.data(using: .utf8) ?? Data()
        fullData.append(bodyData)

        connection.send(content: fullData, completion: .contentProcessed({ [weak connection] _ in
            connection?.cancel()
        }))
    }
}
