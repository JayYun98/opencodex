import Foundation
import Network
import CryptoKit

// A loopback-only bridge for the existing dashboard. It never exports proxy credentials.
struct MonitorHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) throws -> Self? {
        guard data.count <= 131_072 else { throw CocoaError(.fileReadTooLarge) }
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            guard data.count <= 8192 else { throw CocoaError(.fileReadTooLarge) }
            return nil
        }
        guard separator.lowerBound <= 8192,
              let text = String(data: data[..<separator.lowerBound], encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1" else { throw CocoaError(.fileReadCorruptFile) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw CocoaError(.fileReadCorruptFile) }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { throw CocoaError(.fileReadCorruptFile) }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let count = Int(headers["content-length"] ?? "0"), (0...122_880).contains(count) else { throw CocoaError(.fileReadCorruptFile) }
        let body = data[separator.upperBound...]
        guard body.count >= count else { return nil }
        guard body.count == count else { throw CocoaError(.fileReadCorruptFile) }
        return Self(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(body))
    }

    var allowedOrigin: String? {
        guard headers["host"] == "127.0.0.1:10101",
              let origin = headers["origin"],
              ["http://127.0.0.1:10100", "http://localhost:10100"].contains(origin) else { return nil }
        return origin
    }
}

private struct WebSnapshot: Encodable {
    struct Account: Encodable {
        let id: String
        let name: String
        let email: String?
        let plan: String?
    }
    let config: MonitorConfig
    let revision: String
    let graph: GraphSnapshot?
    let usage: Usage?
    let accounts: [Account]
    let quotas: [String: Quota]
    let providerNames: [String]
    let providerWindows: [String: [ProviderWindow]]
    let providerErrors: [String: String]
    let updated: Date?
    let failure: String?
    let graphError: String?
    let quotaError: String?
}

@MainActor
final class MonitorWebBridge {
    let listener: NWListener
    let state: MonitorState
    let saved: () -> Void
    private var connections: [UUID: NWConnection] = [:]

    init(state: MonitorState, saved: @escaping () -> Void) throws {
        self.state = state
        self.saved = saved
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 10101)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] status in
            if case .failed = status {
                Task { @MainActor in self?.state.configError = "대시보드 연결 포트 10101을 사용할 수 없습니다." }
            }
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, data: Data())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.connections.removeValue(forKey: id)?.cancel()
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] chunk, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var data = data
                if let chunk { data.append(chunk) }
                do {
                    if let request = try MonitorHTTPRequest.parse(data) {
                        self.respond(connection, id: id, request: request)
                    } else if complete || error != nil {
                        self.connections.removeValue(forKey: id)?.cancel()
                    } else { self.receive(connection, id: id, data: data) }
                } catch { self.send(connection, id: id, status: 400, body: Data()) }
            }
        }
    }

    private func revision() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(state.config)).map { String(format: "%02x", $0) }.joined()
    }

    private func respond(_ connection: NWConnection, id: UUID, request: MonitorHTTPRequest) {
        guard let origin = request.allowedOrigin else { send(connection, id: id, status: 403, body: Data()); return }
        do {
            if request.method == "OPTIONS", ["/state", "/config"].contains(request.path) {
                send(connection, id: id, status: 204, origin: origin, body: Data()); return
            }
            if request.method == "POST", request.path == "/config" {
                guard request.headers["x-monitor-request"] == "1",
                      request.headers["content-type"]?.split(separator: ";").first == "application/json",
                      let envelope = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let config = envelope["config"] as? [String: Any] else {
                    send(connection, id: id, status: 400, origin: origin, body: Data()); return
                }
                guard envelope["revision"] as? String == (try revision()) else {
                    send(connection, id: id, status: 409, origin: origin, body: Data()); return
                }
                let next: MonitorConfig
                do { next = try MonitorConfig.decode(JSONSerialization.data(withJSONObject: config)) }
                catch { send(connection, id: id, status: 400, origin: origin, body: Data()); return }
                // Save before publishing so a disk failure cannot masquerade as a successful edit.
                try next.save()
                state.config = next
                saved()
            } else if request.method != "GET" || request.path != "/state" {
                send(connection, id: id, status: 404, origin: origin, body: Data()); return
            }
            let snapshot = WebSnapshot(config: state.config, revision: try revision(), graph: state.graph, usage: state.usage,
                accounts: state.accounts.map { .init(id: $0.id, name: $0.name(state.config.locale), email: $0.email, plan: $0.plan) },
                quotas: state.quotas, providerNames: state.providerNames, providerWindows: state.providerWindows,
                providerErrors: state.providerErrors, updated: state.updated, failure: state.failure,
                graphError: state.graphError, quotaError: state.quotaError)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            send(connection, id: id, status: 200, origin: origin, body: try encoder.encode(snapshot))
        } catch { send(connection, id: id, status: 500, origin: origin, body: Data()) }
    }

    private func send(_ connection: NWConnection, id: UUID, status: Int, origin: String? = nil, body: Data) {
        var headers = "HTTP/1.1 \(status) Response\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n"
        if let origin {
            headers += "Access-Control-Allow-Origin: \(origin)\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Monitor-Request\r\n"
        }
        connection.send(content: Data((headers + "\r\n").utf8) + body, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { @MainActor in self?.connections.removeValue(forKey: id) }
        })
    }
}
