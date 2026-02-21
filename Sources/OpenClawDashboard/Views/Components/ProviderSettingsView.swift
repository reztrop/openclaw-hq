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

private func providerDisplayName(for id: String) -> String {
    knownProviders.first(where: { $0.id == id })?.displayName
        ?? id.replacingOccurrences(of: "-", with: " ").capitalized
}

private func providerIcon(for id: String) -> String {
    knownProviders.first(where: { $0.id == id })?.icon ?? "cpu"
}

// MARK: - Provider Settings View

/// Shown at the bottom of the main sidebar.
/// Reads auth.json to discover installed providers; lets the user toggle
/// which are active so the Chat model picker only shows relevant models.
struct ProviderSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Passed directly from ContentView — avoids environment object lookup issues
    /// inside safeAreaInset / sidebar list containers on macOS.
    @ObservedObject var settingsService: SettingsService

    @State private var detectedProviders: [String] = []
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Theme.darkBorder)

            // Collapsible header row
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if detectedProviders.isEmpty {
                    EmptyStateView(
                        icon: "key",
                        title: "No providers found",
                        subtitle: "Check auth.json",
                        alignment: .leading,
                        textAlignment: .leading,
                        maxWidth: .infinity,
                        iconSize: 14,
                        contentPadding: 6,
                        showPanel: false
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                } else {
                    VStack(spacing: 2) {
                        ForEach(detectedProviders, id: \.self) { pid in
                            providerRow(pid)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Theme.darkSurface.opacity(0.5))
        .onAppear { reload() }
    }

    // MARK: - Row

    @ViewBuilder
    private func providerRow(_ pid: String) -> some View {
        let enabled = isEnabled(pid)
        HStack(spacing: 8) {
            Image(systemName: providerIcon(for: pid))
                .font(.caption)
                .foregroundColor(enabled ? Theme.jarvisBlue : Theme.textMuted)
                .frame(width: 16)
            Text(providerDisplayName(for: pid))
                .font(.caption)
                .foregroundColor(enabled ? .white : Theme.textMuted)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled(pid) },
                set: { _ in toggleProvider(pid) }
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
        .onTapGesture { toggleProvider(pid) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: enabled)
    }

    // MARK: - Helpers

    private func isEnabled(_ pid: String) -> Bool {
        guard let list = settingsService.settings.enabledProviders else { return true }
        return list.contains(pid)
    }

    private func toggleProvider(_ pid: String) {
        settingsService.update { s in
            var current = s.enabledProviders ?? detectedProviders
            if current.contains(pid) {
                current.removeAll { $0 == pid }
            } else {
                current.append(pid)
            }
            s.enabledProviders = current
        }
    }

    private func reload() {
        detectedProviders = readAuthProviders()
        if settingsService.settings.enabledProviders == nil {
            settingsService.update { s in s.enabledProviders = detectedProviders }
        }
    }

    private func readAuthProviders() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.openclaw/agents/main/agent/auth.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return json.keys.sorted()
    }
}
