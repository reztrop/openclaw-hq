import Foundation

enum Constants {
    static let gatewayHost = "127.0.0.1"
    static let gatewayPort = 18789
    static let gatewayURL = "ws://\(gatewayHost):\(gatewayPort)"
    // No authToken constant — token is set during onboarding and stored in AppSettings

    static let avatarDirectory = NSString(string: "~/.openclaw/workspace/avatars/avatar_pictures").expandingTildeInPath
    static let tasksFilePath = NSString(string: "~/.openclaw/workspace/tasks.json").expandingTildeInPath
    static let openclawConfigPath = NSString(string: "~/.openclaw/openclaw.json").expandingTildeInPath

    static let appName = "OpenClaw HQ"
    static let windowWidth: CGFloat = 1400
    static let windowHeight: CGFloat = 900
}
