import Foundation

@MainActor
class SettingsService: ObservableObject {
    @Published var settings: AppSettings

    init() {
        settings = Self.load()
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        save()
    }

    func resetToDefaults() {
        settings = .default
        save()
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: URL(fileURLWithPath: AppSettings.filePath))
        } catch {
            print("[Settings] Failed to save: \(error)")
        }
    }

    private static func load() -> AppSettings {
        let path = AppSettings.filePath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}
