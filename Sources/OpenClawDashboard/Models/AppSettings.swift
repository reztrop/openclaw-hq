import Foundation

// Stores per-agent local overrides (avatar paths etc.)
struct LocalAgentConfig: Codable, Identifiable {
    var id: String           // agentId
    var displayName: String? = nil
    var emoji: String? = nil
    var modelId: String? = nil
    var activeAvatarPath: String? = nil
    var idleAvatarPath: String? = nil
}

struct LocalChatConversationConfig: Codable, Identifiable {
    var id: String            // sessionKey
    var customTitle: String? = nil
    var isArchived: Bool = false
}

struct AppSettings: Codable {
    var gatewayHost: String
    var gatewayPort: Int
    var authToken: String
    var enableNotifications: Bool
    var refreshInterval: Int // seconds
    var showOfflineAgents: Bool
    var onboardingComplete: Bool
    var localAgents: [LocalAgentConfig]
    var localChats: [LocalChatConversationConfig]
    /// Provider IDs (matching auth.json keys) the user has enabled.
    /// nil = not yet set (treat as "all available providers enabled").
    var enabledProviders: [String]?

    var gatewayURL: String {
        "ws://\(gatewayHost):\(gatewayPort)"
    }

    static let `default` = AppSettings(
        gatewayHost: "127.0.0.1",
        gatewayPort: 18789,
        authToken: "",
        enableNotifications: true,
        refreshInterval: 30,
        showOfflineAgents: true,
        onboardingComplete: false,
        localAgents: [],
        localChats: [],
        enabledProviders: nil
    )

    static let filePath: String = {
        NSString(string: "~/.openclaw/workspace/dashboard_settings.json").expandingTildeInPath
    }()

    enum CodingKeys: String, CodingKey {
        case gatewayHost
        case gatewayPort
        case authToken
        case enableNotifications
        case refreshInterval
        case showOfflineAgents
        case onboardingComplete
        case localAgents
        case localChats
        case enabledProviders
    }

    init(
        gatewayHost: String,
        gatewayPort: Int,
        authToken: String,
        enableNotifications: Bool,
        refreshInterval: Int,
        showOfflineAgents: Bool,
        onboardingComplete: Bool,
        localAgents: [LocalAgentConfig],
        localChats: [LocalChatConversationConfig],
        enabledProviders: [String]?
    ) {
        self.gatewayHost = gatewayHost
        self.gatewayPort = gatewayPort
        self.authToken = authToken
        self.enableNotifications = enableNotifications
        self.refreshInterval = refreshInterval
        self.showOfflineAgents = showOfflineAgents
        self.onboardingComplete = onboardingComplete
        self.localAgents = localAgents
        self.localChats = localChats
        self.enabledProviders = enabledProviders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default

        gatewayHost = try c.decodeIfPresent(String.self, forKey: .gatewayHost) ?? d.gatewayHost
        gatewayPort = try c.decodeIfPresent(Int.self, forKey: .gatewayPort) ?? d.gatewayPort
        authToken = try c.decodeIfPresent(String.self, forKey: .authToken) ?? d.authToken
        enableNotifications = try c.decodeIfPresent(Bool.self, forKey: .enableNotifications) ?? d.enableNotifications
        refreshInterval = try c.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? d.refreshInterval
        showOfflineAgents = try c.decodeIfPresent(Bool.self, forKey: .showOfflineAgents) ?? d.showOfflineAgents
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? d.onboardingComplete
        localAgents = try c.decodeIfPresent([LocalAgentConfig].self, forKey: .localAgents) ?? d.localAgents
        localChats = try c.decodeIfPresent([LocalChatConversationConfig].self, forKey: .localChats) ?? d.localChats
        enabledProviders = try c.decodeIfPresent([String].self, forKey: .enabledProviders)
    }
}
