import SwiftUI
import Combine

// MARK: - Onboarding Steps
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case connection = 1
    case agentDiscovery = 2
    case avatarSetup = 3
    case done = 4
}

// MARK: - Connection Test Status
enum TestStatus: Equatable {
    case idle
    case testing
    case success
    case failed(String)

    static func == (lhs: TestStatus, rhs: TestStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.testing, .testing), (.success, .success): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }

    var isSuccess: Bool { self == .success }
    var isTesting: Bool { self == .testing }

    var errorMessage: String? {
        if case .failed(let msg) = self { return msg }
        return nil
    }
}

// MARK: - Connection Mode
enum ConnectionMode {
    case local   // OpenClaw running on this Mac
    case remote  // Remote / Manual
}

// MARK: - OnboardingViewModel
@MainActor
class OnboardingViewModel: ObservableObject {
    // Navigation
    @Published var step: OnboardingStep = .welcome

    // Connection
    @Published var connectionMode: ConnectionMode = .local
    @Published var host = "127.0.0.1"
    @Published var port = "18789"
    @Published var token = ""
    @Published var testStatus: TestStatus = .idle
    @Published var tokenFoundInConfig = false
    @Published var generatingToken = false
    @Published var generateTokenError: String?

    // Agent Discovery
    @Published var discoveredAgents: [Agent] = []
    @Published var defaultAgentId: String?
    @Published var mainAgent: Agent?
    @Published var agentName: String = ""
    @Published var agentEmoji: String = "🤖"
    @Published var isLoadingAgents = false
    @Published var agentDiscoveryError: String?

    // Avatar Setup
    @Published var activeImagePath: String? = nil
    @Published var idleImagePath: String? = nil

    // Shared gateway service for testing / discovery
    private var gatewayService: GatewayService?
    private var cancellables = Set<AnyCancellable>()

    init() {
        tryAutoImportToken()
    }

    // MARK: - Token Auto-Import

    func tryAutoImportToken() {
        let configPath = Constants.openclawConfigPath
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = json["gateway"] as? [String: Any],
              let auth = gateway["auth"] as? [String: Any],
              let foundToken = auth["token"] as? String,
              !foundToken.isEmpty else {
            return
        }
        token = foundToken
        tokenFoundInConfig = true
    }

    // MARK: - Generate Token via CLI

    func generateToken() async {
        generatingToken = true
        generateTokenError = nil
        defer { generatingToken = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["openclaw", "doctor", "--generate-gateway-token", "--non-interactive", "--yes"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Re-read config to pick up new token
                tryAutoImportToken()
                if token.isEmpty {
                    generateTokenError = "Token generated but not found in config. Try again."
                }
            } else {
                let errData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
                let errMsg = errData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                generateTokenError = "Command failed: \(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        } catch {
            generateTokenError = "Could not run openclaw: \(error.localizedDescription). Make sure OpenClaw is installed."
        }
    }

    // MARK: - Test Connection

    func testConnection() async {
        testStatus = .testing
        let portNum = Int(port) ?? 18789

        // Create a temporary gateway service for testing
        let testService = GatewayService()
        gatewayService = testService
        testService.connect(host: host, port: portNum, token: token)

        // Wait up to 8 seconds for connected state
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(100))
            if testService.connectionState.isConnected {
                testStatus = .success
                return
            }
            if case .disconnected(let msg) = testService.connectionState, let msg = msg {
                if msg.contains("failed") || msg.contains("error") || msg.contains("Handshake") {
                    testStatus = .failed(msg)
                    testService.disconnect()
                    gatewayService = nil
                    return
                }
            }
        }

        testStatus = .failed("Connection timed out. Check gateway is running and token is correct.")
        testService.disconnect()
        gatewayService = nil
    }

    // MARK: - Agent Discovery

    func discoverAgents() async {
        guard let svc = gatewayService, svc.isConnected else {
            agentDiscoveryError = "Not connected to gateway"
            return
        }

        isLoadingAgents = true
        agentDiscoveryError = nil
        defer { isLoadingAgents = false }

        do {
            let (defaultId, _, rawAgents) = try await svc.fetchAgentsListFull()
            defaultAgentId = defaultId

            discoveredAgents = rawAgents.map { raw -> Agent in
                let id    = raw["id"]   as? String ?? UUID().uuidString
                let ident = raw["identity"] as? [String: Any]
                let rawName = (ident?["name"] as? String) ?? (raw["name"] as? String) ?? id
                let emoji = (ident?["emoji"] as? String) ?? "🤖"
                return Agent(
                    id: id,
                    name: rawName.isEmpty ? id : rawName,
                    emoji: emoji,
                    role: id == defaultId ? "Main Agent" : "Agent",
                    status: .offline,
                    totalTokens: 0,
                    sessionCount: 0,
                    isDefaultAgent: id == defaultId
                )
            }

            // Pre-populate name/emoji from the main agent
            if let main = discoveredAgents.first(where: { $0.isDefaultAgent }) {
                mainAgent = main
                agentName = main.name
                agentEmoji = main.emoji
            } else if let first = discoveredAgents.first {
                mainAgent = first
                agentName = first.name
                agentEmoji = first.emoji
            }
        } catch {
            agentDiscoveryError = error.localizedDescription
        }
    }

    // MARK: - Complete Onboarding

    func completeOnboarding(settingsService: SettingsService) async {
        guard let svc = gatewayService else { return }

        // Update main agent name/emoji if changed
        if let main = mainAgent {
            let nameTrimmed = agentName.trimmingCharacters(in: .whitespaces)
            if !nameTrimmed.isEmpty && (nameTrimmed != main.name || agentEmoji != main.emoji) {
                _ = try? await svc.updateAgent(agentId: main.id, name: nameTrimmed, emoji: agentEmoji)
            }

            // Save avatar paths into settings
            var localAgents = settingsService.settings.localAgents
            var config = localAgents.first(where: { $0.id == main.id }) ?? LocalAgentConfig(id: main.id)
            config.activeAvatarPath = activeImagePath
            config.idleAvatarPath = idleImagePath
            config.displayName = nameTrimmed.isEmpty ? nil : nameTrimmed
            if let idx = localAgents.firstIndex(where: { $0.id == main.id }) {
                localAgents[idx] = config
            } else {
                localAgents.append(config)
            }
            settingsService.settings.localAgents = localAgents
        }

        // Save connection settings + mark onboarding complete
        let portNum = Int(port) ?? 18789
        settingsService.settings.gatewayHost = host
        settingsService.settings.gatewayPort = portNum
        settingsService.settings.authToken   = token
        settingsService.settings.onboardingComplete = true
        settingsService.save()

        // Hand off the authenticated gateway service to the shared one
        // (AppViewModel will call its own connect after onboarding completes)
        svc.disconnect()
        gatewayService = nil
    }

    // MARK: - Navigation

    func goNext() {
        guard let current = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            step = current
        }
    }

    func goBack() {
        guard step.rawValue > 0,
              let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            step = prev
        }
    }
}
