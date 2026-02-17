import Foundation
import Combine
import CryptoKit

// MARK: - Connection State

enum ConnectionState: Equatable {
    case connecting
    case connected
    case disconnected(String?)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.disconnected(let a), .disconnected(let b)): return a == b
        default: return false
        }
    }

    var isConnected: Bool { self == .connected }

    var errorMessage: String? {
        if case .disconnected(let msg) = self { return msg }
        return nil
    }
}

// MARK: - Device Identity

private struct DeviceIdentity {
    let deviceId: String
    let privateKeyPem: String
    let publicKeyPem: String
}

private struct DeviceAuth {
    let token: String
    let role: String
    let scopes: [String]
}

// MARK: - Gateway Service
@MainActor
class GatewayService: ObservableObject {
    @Published var connectionState: ConnectionState = .connecting
    @Published var lastError: String?

    /// Convenience accessor for views that only need a bool
    var isConnected: Bool { connectionState.isConnected }

    // Event publishers
    let agentEventSubject    = PassthroughSubject<[String: Any], Never>()
    let presenceEventSubject = PassthroughSubject<[String: Any], Never>()
    let tickEventSubject     = PassthroughSubject<[String: Any], Never>()
    let healthEventSubject   = PassthroughSubject<[String: Any], Never>()

    private var webSocketTask: URLSessionWebSocketTask?
    private var pendingRequests: [String: CheckedContinuation<AnyCodable?, Error>] = [:]
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var isReconnecting = false
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var currentHost: String = Constants.gatewayHost
    private var currentPort: Int    = Constants.gatewayPort
    private var currentToken: String = ""

    private var deviceIdentity: DeviceIdentity?
    private var deviceAuth: DeviceAuth?

    // MARK: - Init

    init() {
        loadDeviceCredentials()
    }

    private func loadDeviceCredentials() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let devicePath = "\(home)/.openclaw/identity/device.json"
        let authPath   = "\(home)/.openclaw/identity/device-auth.json"

        if let data = FileManager.default.contents(atPath: devicePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            deviceIdentity = DeviceIdentity(
                deviceId:      json["deviceId"]      as? String ?? "",
                privateKeyPem: json["privateKeyPem"] as? String ?? "",
                publicKeyPem:  json["publicKeyPem"]  as? String ?? ""
            )
        }

        if let data = FileManager.default.contents(atPath: authPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokens = json["tokens"] as? [String: Any],
           let op = tokens["operator"] as? [String: Any] {
            deviceAuth = DeviceAuth(
                token:  op["token"]  as? String ?? "",
                role:   op["role"]   as? String ?? "operator",
                scopes: op["scopes"] as? [String] ?? ["operator.admin"]
            )
        }
    }

    // MARK: - Connection

    func connect(host: String? = nil, port: Int? = nil, token: String? = nil) {
        guard !connectionState.isConnected, !isReconnecting else { return }

        if let host  = host  { currentHost  = host }
        if let port  = port  { currentPort  = port }
        if let token = token { currentToken = token }

        let urlStr = "ws://\(currentHost):\(currentPort)"
        guard let url = URL(string: urlStr) else { return }

        // The gateway uses its own challenge-response auth — no bearer header needed for WS
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        connectionState = .connecting
        lastError = nil

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        connectionState = .disconnected(nil)
        lastError = nil
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        for (_, cont) in pendingRequests {
            cont.resume(throwing: GatewayError(code: -3, message: "Disconnected"))
        }
        pendingRequests.removeAll()
    }

    private func startPeriodicPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.sendWsPing()
            }
        }
    }

    // MARK: - Handshake (connect.challenge response)

    private func sendConnectRequest(nonce: String) async {
        let role:   String   = deviceAuth?.role   ?? "operator"
        let scopes: [String] = deviceAuth?.scopes ?? ["operator.admin"]
        let authToken: String = deviceAuth?.token ?? currentToken
        let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let clientId   = "openclaw-macos"
        let clientMode = "ui"

        var device: [String: Any]? = nil
        if let identity = deviceIdentity {
            // Payload: v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
            let payload = ["v2", identity.deviceId, clientId, clientMode, role,
                           scopes.joined(separator: ","), String(signedAtMs),
                           authToken, nonce].joined(separator: "|")
            let signature = signEd25519(privateKeyPem: identity.privateKeyPem, payload: payload)
            let pubKeyB64 = extractRawPublicKeyBase64Url(from: identity.publicKeyPem)

            device = [
                "id":        identity.deviceId,
                "publicKey": pubKeyB64,
                "signature": signature,
                "signedAt":  signedAtMs,
                "nonce":     nonce
            ]
        }

        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id":      clientId,
                "version": "1.0.0",
                "platform": "darwin",
                "mode":    clientMode
            ],
            "caps":   [],
            "auth":   ["token": authToken],
            "role":   role,
            "scopes": scopes
        ]
        if let device = device {
            params["device"] = device
        }

        do {
            let result = try await sendRPC("connect", params: params)
            // hello-ok — authenticated
            connectionState = .connected
            lastError = nil
            reconnectAttempts = 0
            isReconnecting = false
            startPeriodicPing()

            // Dispatch snapshot data from hello-ok payload
            if let dict = result?.dictionary {
                if let health = dict["health"] as? [String: Any] {
                    healthEventSubject.send(health)
                }
                if let presence = dict["presence"] as? [[String: Any]] {
                    for p in presence { presenceEventSubject.send(p) }
                }
            }
        } catch {
            let msg = "Handshake failed: \(error.localizedDescription)"
            connectionState = .disconnected(msg)
            lastError = msg
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            await scheduleReconnect()
        }
    }

    // MARK: - Ed25519 Signing

    private func signEd25519(privateKeyPem: String, payload: String) -> String {
        // Strip PEM headers and base64-decode the DER blob
        let b64 = privateKeyPem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let der = Data(base64Encoded: b64), der.count >= 34 else { return "" }

        // PKCS#8 Ed25519 DER layout: the raw 32-byte key is at the end
        let rawKey = der.suffix(32)

        do {
            let privKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
            let sig = try privKey.signature(for: Data(payload.utf8))
            return base64UrlEncode(sig)
        } catch {
            print("[GatewayService] Signing error: \(error)")
            return ""
        }
    }

    private func extractRawPublicKeyBase64Url(from pem: String) -> String {
        let b64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let der = Data(base64Encoded: b64), der.count >= 12 else { return b64 }
        // SubjectPublicKeyInfo DER for Ed25519: last 32 bytes are the raw key
        return base64UrlEncode(der.suffix(32))
    }

    private func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=",  with: "")
    }

    // MARK: - RPC

    func sendRPC(_ method: String, params: [String: Any]? = nil) async throws -> AnyCodable? {
        guard let ws = webSocketTask else {
            throw GatewayError(code: -1, message: "Not connected to gateway")
        }

        let id = UUID().uuidString
        var frame: [String: Any] = ["type": "req", "id": id, "method": method]
        if let params = params { frame["params"] = params }

        let data = try JSONSerialization.data(withJSONObject: frame)
        let msg  = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            ws.send(msg) { error in
                if let error = error {
                    Task { @MainActor in self.pendingRequests.removeValue(forKey: id) }
                    continuation.resume(throwing: error)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run {
                    if let cont = self.pendingRequests.removeValue(forKey: id) {
                        cont.resume(throwing: GatewayError(code: -2, message: "Timed out: \(method)"))
                    }
                }
            }
        }
    }

    private func sendRPCWithTimeout(_ method: String, params: [String: Any]?, timeout seconds: Int) async throws -> AnyCodable? {
        guard let ws = webSocketTask else {
            throw GatewayError(code: -1, message: "Not connected to gateway")
        }

        let id = UUID().uuidString
        var frame: [String: Any] = ["type": "req", "id": id, "method": method]
        if let params = params { frame["params"] = params }

        let data = try JSONSerialization.data(withJSONObject: frame)
        let msg  = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            ws.send(msg) { error in
                if let error = error {
                    Task { @MainActor in self.pendingRequests.removeValue(forKey: id) }
                    continuation.resume(throwing: error)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(seconds))
                await MainActor.run {
                    if let cont = self.pendingRequests.removeValue(forKey: id) {
                        cont.resume(throwing: GatewayError(code: -2, message: "Timed out: \(method)"))
                    }
                }
            }
        }
    }

    // MARK: - Convenience RPC Methods

    func fetchStatus() async throws -> [String: Any]? {
        try await sendRPC("status")?.dictionary
    }

    func fetchAgentsList() async throws -> [[String: Any]] {
        let result = try await sendRPC("agents.list")
        if let agents = result?.dictionary?["agents"] as? [[String: Any]] { return agents }
        if let arr = result?.array as? [[String: Any]] { return arr }
        return []
    }

    func fetchAgentIdentity(_ agentId: String) async throws -> [String: Any]? {
        try await sendRPC("agent.identity.get", params: ["agentId": agentId])?.dictionary
    }

    func fetchSessionsList(agentId: String? = nil) async throws -> [[String: Any]] {
        var params: [String: Any] = [:]
        if let agentId = agentId { params["agentId"] = agentId }
        let result = try await sendRPC("sessions.list", params: params.isEmpty ? nil : params)
        if let sessions = result?.dictionary?["sessions"] as? [[String: Any]] { return sessions }
        if let arr = result?.array as? [[String: Any]] { return arr }
        return []
    }

    func fetchUsageStatus() async throws -> [String: Any]? {
        try await sendRPC("usage.status")?.dictionary
    }

    func fetchUsageCost(from: Date? = nil, to: Date? = nil) async throws -> [String: Any]? {
        var params: [String: Any] = [:]
        if let from = from { params["from"] = ISO8601DateFormatter().string(from: from) }
        if let to   = to   { params["to"]   = ISO8601DateFormatter().string(from: to) }
        return try await sendRPC("usage.cost", params: params.isEmpty ? nil : params)?.dictionary
    }

    func fetchHealth() async throws -> [String: Any]? {
        try await sendRPC("health")?.dictionary
    }

    func sendAgentCommand(_ agentId: String, message: String) async throws -> [String: Any]? {
        try await sendRPCWithTimeout("agent.wait", params: ["agentId": agentId, "message": message], timeout: 120)?.dictionary
    }

    // MARK: - Agent Management RPCs

    /// Create a new agent on the gateway
    func createAgent(name: String, workspace: String, emoji: String? = nil) async throws -> [String: Any]? {
        var params: [String: Any] = ["name": name, "workspace": workspace]
        if let emoji = emoji { params["emoji"] = emoji }
        return try await sendRPC("agents.create", params: params)?.dictionary
    }

    /// Update an existing agent's metadata (name, model, avatar, emoji, etc.)
    func updateAgent(agentId: String, name: String? = nil, model: String? = nil, avatar: String? = nil, emoji: String? = nil) async throws -> [String: Any]? {
        var params: [String: Any] = ["agentId": agentId]
        if let name   = name   { params["name"]   = name }
        if let model  = model  { params["model"]  = model }
        if let avatar = avatar { params["avatar"] = avatar }
        if let emoji  = emoji  { params["emoji"]  = emoji }
        return try await sendRPC("agents.update", params: params)?.dictionary
    }

    /// Delete an agent from the gateway
    func deleteAgent(agentId: String, deleteFiles: Bool = true) async throws -> [String: Any]? {
        let params: [String: Any] = ["agentId": agentId, "deleteFiles": deleteFiles]
        return try await sendRPC("agents.delete", params: params)?.dictionary
    }

    /// Write a file into an agent's workspace (e.g. IDENTITY.md for system prompt)
    func setAgentFile(agentId: String, name: String, content: String) async throws -> [String: Any]? {
        let params: [String: Any] = ["agentId": agentId, "name": name, "content": content]
        return try await sendRPC("agents.files.set", params: params)?.dictionary
    }

    /// Fetch all available models from the gateway
    func fetchModels() async throws -> [[String: Any]] {
        let result = try await sendRPC("models.list")
        if let models = result?.dictionary?["models"] as? [[String: Any]] { return models }
        return []
    }

    /// Fetch agents list including defaultId, mainKey, and full identity fields
    func fetchAgentsListFull() async throws -> (defaultId: String?, mainKey: String?, agents: [[String: Any]]) {
        let result = try await sendRPC("agents.list")
        guard let dict = result?.dictionary else { return (nil, nil, []) }
        let defaultId = dict["defaultId"] as? String
        let mainKey   = dict["mainKey"]   as? String
        let agents    = dict["agents"]    as? [[String: Any]] ?? []
        return (defaultId, mainKey, agents)
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        guard let ws = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                await handleMessage(message)
            } catch {
                // Only reconnect if we're not already in a deliberate disconnect state
                if connectionState != .disconnected(nil) {
                    let msg = connectionState.isConnected
                        ? "Connection lost: \(error.localizedDescription)"
                        : "Connection failed: \(error.localizedDescription)"
                    connectionState = .disconnected(msg)
                    lastError = msg
                    for (_, cont) in pendingRequests {
                        cont.resume(throwing: GatewayError(code: -3, message: "Disconnected"))
                    }
                    pendingRequests.removeAll()
                    await scheduleReconnect()
                }
                return
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:    return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let frameType = json["type"] as? String ?? ""

        // Response frame: {"type":"res","id":"...","ok":bool,"payload":{...},"error":{...}}
        if frameType == "res", let id = json["id"] as? String {
            guard let cont = pendingRequests.removeValue(forKey: id) else { return }
            if json["ok"] as? Bool == true {
                let payload = json["payload"].map { AnyCodable($0) }
                cont.resume(returning: payload)
            } else {
                let errMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                cont.resume(throwing: GatewayError(code: -4, message: errMsg))
            }
            return
        }

        // Event frame: {"type":"event","event":"...","payload":{...},"seq":N}
        if frameType == "event", let eventName = json["event"] as? String {
            let payload = json["payload"] as? [String: Any] ?? [:]

            if eventName == "connect.challenge" {
                let nonce = payload["nonce"] as? String ?? ""
                Task { await self.sendConnectRequest(nonce: nonce) }
                return
            }

            switch eventName {
            case "agent", "agent.update":
                agentEventSubject.send(payload)
            case "presence":
                presenceEventSubject.send(payload)
            case "tick":
                tickEventSubject.send(payload)
            case "health":
                healthEventSubject.send(payload)
            default:
                break
            }
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() async {
        guard !isReconnecting else { return }
        isReconnecting = true
        reconnectAttempts += 1

        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), maxReconnectDelay)
        let msg = "Reconnecting in \(Int(delay))s…"
        connectionState = .disconnected(msg)
        lastError = msg

        try? await Task.sleep(for: .seconds(delay))
        isReconnecting = false
        connect()
    }

    // MARK: - Ping

    private func sendWsPing() async {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                Task { @MainActor [weak self] in
                    guard let self, self.connectionState.isConnected else { return }
                    let msg = "Ping failed: \(error.localizedDescription)"
                    self.connectionState = .disconnected(msg)
                    self.lastError = msg
                    self.pingTask?.cancel()
                    self.pingTask = nil
                    self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                    self.webSocketTask = nil
                    await self.scheduleReconnect()
                }
            }
        }
    }
}
