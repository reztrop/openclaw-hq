import SwiftUI

// MARK: - Provider Display Info

private struct ProviderInfo {
    let id: String
    let displayName: String
    let icon: String
}

private let knownProviders: [ProviderInfo] = [
    ProviderInfo(id: "openai-codex",  displayName: "OpenAI Codex",  icon: "sparkles"),
    ProviderInfo(id: "anthropic",     displayName: "Anthropic",      icon: "brain"),
    ProviderInfo(id: "openai",        displayName: "OpenAI",         icon: "bolt.fill"),
    ProviderInfo(id: "google",        displayName: "Google",         icon: "globe"),
    ProviderInfo(id: "mistral",       displayName: "Mistral",        icon: "wind"),
    ProviderInfo(id: "deepseek",      displayName: "DeepSeek",       icon: "water.waves"),
    ProviderInfo(id: "cohere",        displayName: "Cohere",         icon: "link"),
    ProviderInfo(id: "groq",          displayName: "Groq",           icon: "bolt"),
    ProviderInfo(id: "xai",           displayName: "xAI / Grok",     icon: "xmark.circle"),
    ProviderInfo(id: "meta",          displayName: "Meta / Llama",   icon: "theatermasks"),
]

private func displayName(for providerId: String) -> String {
    knownProviders.first(where: { $0.id == providerId })?.displayName
        ?? providerId
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
}

private func icon(for providerId: String) -> String {
    knownProviders.first(where: { $0.id == providerId })?.icon ?? "cpu"
}

// MARK: - Provider Settings View

/// Shown at the bottom of the main sidebar.
/// Reads auth.json to discover which providers are installed, then lets
/// the user toggle which ones are active for the Chat model picker.
struct ProviderSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService

    /// All provider IDs found in auth.json
    @State private var detectedProviders: [String] = []
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.darkBorder)

            // Collapse / expand header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    Text("API Connections")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if detectedProviders.isEmpty {
                    Text("No API connections found in auth.json")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    VStack(spacing: 2) {
                        ForEach(detectedProviders, id: \.self) { providerId in
                            providerRow(providerId)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Theme.darkSurface.opacity(0.5))
        .onAppear { reload() }
    }

    // MARK: - Row

    private func providerRow(_ providerId: String) -> some View {
        let enabled = isEnabled(providerId)
        return HStack(spacing: 8) {
            Image(systemName: icon(for: providerId))
                .font(.caption)
                .foregroundColor(enabled ? Theme.jarvisBlue : Theme.textMuted)
                .frame(width: 16)
            Text(displayName(for: providerId))
                .font(.caption)
                .foregroundColor(enabled ? .white : Theme.textMuted)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled(providerId) },
                set: { _ in toggle(providerId) }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.7)
            .labelsHidden()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(enabled ? Theme.jarvisBlue.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggle(providerId) }
        .animation(.easeOut(duration: 0.15), value: enabled)
    }

    // MARK: - Helpers

    private func isEnabled(_ providerId: String) -> Bool {
        guard let list = settingsService.settings.enabledProviders else {
            // nil = first launch, treat all as enabled
            return true
        }
        return list.contains(providerId)
    }

    private func toggle(_ providerId: String) {
        settingsService.update { s in
            // Initialise from detected providers if first toggle
            var current = s.enabledProviders ?? detectedProviders
            if current.contains(providerId) {
                current.removeAll { $0 == providerId }
            } else {
                current.append(providerId)
            }
            s.enabledProviders = current
        }
    }

    private func reload() {
        detectedProviders = loadDetectedProviders()
        // If enabledProviders hasn't been set yet, seed it from detected list
        if settingsService.settings.enabledProviders == nil {
            settingsService.update { s in
                s.enabledProviders = detectedProviders
            }
        }
    }

    private func loadDetectedProviders() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let authPath = "\(home)/.openclaw/agents/main/agent/auth.json"
        guard let data = FileManager.default.contents(atPath: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return json.keys.sorted()
    }
}
