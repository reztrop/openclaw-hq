import Foundation

// Stores per-agent local overrides (avatar paths etc.)
struct LocalAgentConfig: Codable, Identifiable {
    var id: String           // agentId
    var displayName: String?
    var activeAvatarPath: String?
    var idleAvatarPath: String?
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
        enabledProviders: nil
    )

    static let filePath: String = {
        NSString(string: "~/.openclaw/workspace/dashboard_settings.json").expandingTildeInPath
    }()
}
