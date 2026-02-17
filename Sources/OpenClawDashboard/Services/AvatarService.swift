import AppKit
import SwiftUI

// MARK: - Avatar State
enum AvatarState {
    case active
    case idle

    var suffix: String {
        switch self {
        case .active: return "active"
        case .idle: return "idle"
        }
    }
}

// MARK: - Avatar Service
class AvatarService {
    static let shared = AvatarService()

    private var cache: [String: NSImage] = [:]
    private let directory: String

    init(directory: String = Constants.avatarDirectory) {
        self.directory = directory
    }

    // MARK: - Load Avatar

    func loadAvatar(for agentName: String, state: AvatarState) -> NSImage? {
        let cacheKey = "\(agentName)_\(state.suffix)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let fileName = "\(agentName)_\(state.suffix).png"
        let filePath = "\(directory)/\(fileName)"

        guard FileManager.default.fileExists(atPath: filePath),
              let image = NSImage(contentsOfFile: filePath) else {
            return nil
        }

        cache[cacheKey] = image
        return image
    }

    // MARK: - Preload

    func preloadAllAvatars() {
        let agents = ["Jarvis", "Matrix", "Prism", "Scope", "Atlas"]
        for agent in agents {
            _ = loadAvatar(for: agent, state: .active)
            _ = loadAvatar(for: agent, state: .idle)
        }
    }

    // MARK: - SwiftUI Image

    func avatarImage(for agentName: String, state: AvatarState) -> Image {
        if let nsImage = loadAvatar(for: agentName, state: state) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "person.crop.circle.fill")
    }

    // MARK: - Clear Cache

    func clearCache() {
        cache.removeAll()
    }
}
