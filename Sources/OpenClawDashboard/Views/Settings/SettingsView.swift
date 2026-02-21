import SwiftUI

// MARK: - Known Providers

private struct KnownProvider {
    let id: String
    let displayName: String
    let icon: String
}

private let knownProviders: [KnownProvider] = [
    KnownProvider(id: "openai-codex",  displayName: "OpenAI Codex",  icon: "sparkles"),
    KnownProvider(id: "anthropic",     displayName: "Anthropic",      icon: "brain"),
    KnownProvider(id: "openai",        displayName: "OpenAI",         icon: "bolt.fill"),
    KnownProvider(id: "google",        displayName: "Google",         icon: "globe"),
    KnownProvider(id: "mistral",       displayName: "Mistral",        icon: "wind"),
    KnownProvider(id: "deepseek",      displayName: "DeepSeek",       icon: "water.waves"),
    KnownProvider(id: "cohere",        displayName: "Cohere",         icon: "link"),
    KnownProvider(id: "groq",          displayName: "Groq",           icon: "bolt"),
    KnownProvider(id: "xai",           displayName: "xAI / Grok",     icon: "xmark.circle"),
    KnownProvider(id: "meta",          displayName: "Meta / Llama",   icon: "theatermasks"),
]

private func providerDisplayName(_ id: String) -> String {
    knownProviders.first { $0.id == id }?.displayName
        ?? id.replacingOccurrences(of: "-", with: " ").capitalized
}

private func providerIcon(_ id: String) -> String {
    knownProviders.first { $0.id == id }?.icon ?? "cpu"
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var gatewayService: GatewayService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Gateway fields
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var token: String = ""
    @State private var enableNotifications: Bool = true
    @State private var refreshInterval: Int = 30
    @State private var showOfflineAgents: Bool = true
    @State private var testResult: String?
    @State private var isTesting: Bool = false
    @State private var savedConfirmation: Bool = false

    @FocusState private var focusedField: SettingsField?
    @State private var hoveredField: SettingsField?

    // Provider detection
    @State private var detectedProviders: [String] = []

    private enum SettingsField: Hashable {
        case host
        case port
        case token
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: API Connections
                settingsSection("API Connections", icon: "key.fill") {
                    if detectedProviders.isEmpty {
                        Text("No providers found in ~/.openclaw/agents/main/agent/auth.json")
                            .font(.callout)
                            .foregroundColor(Theme.textMuted)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(detectedProviders, id: \.self) { pid in
                                providerRow(pid)
                                if pid != detectedProviders.last {
                                    Divider().background(Theme.darkBorder).padding(.leading, 40)
                                }
                            }
                        }
                        .background(Theme.darkSurface)
                        .cornerRadius(10)
                    }
                    Text("Only models from enabled providers will appear in the Chat model picker.")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                // MARK: Gateway Connection
                settingsSection("Gateway Connection", icon: "antenna.radiowaves.left.and.right") {
                    VStack(spacing: 10) {
                        labeledField("Host") {
                            settingsField("127.0.0.1", text: $host, field: .host)
                        }
                        labeledField("Port") {
                            settingsField("18789", text: $port, field: .port)
                        }
                        labeledField("Auth Token") {
                            settingsField("token", text: $token, field: .token, isSecure: true)
                        }
                        HStack(spacing: 10) {
                            Button("Test Connection") { testConnection() }
                                .disabled(isTesting)
                            if isTesting { ProgressView().scaleEffect(0.7) }
                            if let result = testResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result.contains("Success") ? .green : .red)
                            }
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Theme.darkSurface)
                    .cornerRadius(10)
                }

                // MARK: Display
                settingsSection("Display", icon: "paintbrush") {
                    VStack(spacing: 0) {
                        Toggle("Enable Notifications", isOn: $enableNotifications)
                            .padding(14)
                        Divider().background(Theme.darkBorder)
                        Toggle("Show Offline Agents", isOn: $showOfflineAgents)
                            .padding(14)
                        Divider().background(Theme.darkBorder)
                        HStack {
                            Text("Auto-Refresh Interval")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $refreshInterval) {
                                Text("15 sec").tag(15)
                                Text("30 sec").tag(30)
                                Text("60 sec").tag(60)
                                Text("Off").tag(0)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                        }
                        .padding(14)
                    }
                    .background(Theme.darkSurface)
                    .cornerRadius(10)
                }

                // MARK: Save / Reset
                HStack(spacing: 12) {
                    Button("Reset to Defaults") {
                        settingsService.resetToDefaults()
                        loadFromSettings()
                        detectedProviders = readAuthProviders()
                    }
                    .foregroundColor(Theme.textMuted)

                    Spacer()

                    if savedConfirmation {
                        Text("Saved")
                            .font(.callout)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }

                    Button("Save") { saveSettings() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(24)
        }
        .background(Theme.darkBackground)
        .onAppear {
            loadFromSettings()
            detectedProviders = readAuthProviders()
            seedEnabledProvidersIfNeeded()
        }
    }

    // MARK: - Provider row

    private func providerRow(_ pid: String) -> some View {
        let enabled = isEnabled(pid)
        return HStack(spacing: 12) {
            Image(systemName: providerIcon(pid))
                .foregroundColor(enabled ? Theme.jarvisBlue : Theme.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(providerDisplayName(pid))
                    .foregroundColor(enabled ? .white : Theme.textMuted)
                Text(pid)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled(pid) },
                set: { _ in toggleProvider(pid) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture { toggleProvider(pid) }
    }

    // MARK: - Section builder

    private func settingsSection<Content: View>(
        _ title: String, icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.white)
            content()
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func settingsField(_ placeholder: String, text: Binding<String>, field: SettingsField, isSecure: Bool = false) -> some View {
        let isFocused = focusedField == field
        let isHovered = hoveredField == field

        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textFieldStyle(.plain)
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(fieldChrome(isFocused: isFocused, isHovered: isHovered))
        .focused($focusedField, equals: field)
        .onHover { hovering in
            updateHoveredField(field, hovering: hovering)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }

    private func fieldChrome(isFocused: Bool, isHovered: Bool) -> some View {
        let borderColor: Color
        if isFocused {
            borderColor = Theme.jarvisBlue
        } else if isHovered {
            borderColor = Theme.jarvisBlue.opacity(0.65)
        } else {
            borderColor = Theme.darkBorder.opacity(0.9)
        }

        let surface = Theme.darkAccent.opacity(isFocused ? 0.9 : 0.75)
        let glow = isFocused ? Theme.jarvisBlue.opacity(0.25) : Color.clear

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: glow, radius: isFocused ? 8 : 0)
    }

    private func updateHoveredField(_ field: SettingsField, hovering: Bool) {
        if hovering {
            hoveredField = field
        } else if hoveredField == field {
            hoveredField = nil
        }
    }

    // MARK: - Provider helpers

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

    private func seedEnabledProvidersIfNeeded() {
        guard settingsService.settings.enabledProviders == nil else { return }
        settingsService.update { s in s.enabledProviders = detectedProviders }
    }

    private func readAuthProviders() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.openclaw/agents/main/agent/auth.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return json.keys.sorted()
    }

    // MARK: - Gateway helpers

    private func loadFromSettings() {
        let s = settingsService.settings
        host = s.gatewayHost
        port = "\(s.gatewayPort)"
        token = s.authToken
        enableNotifications = s.enableNotifications
        refreshInterval = s.refreshInterval
        showOfflineAgents = s.showOfflineAgents
    }

    private func saveSettings() {
        let portInt = Int(port) ?? settingsService.settings.gatewayPort
        let previousURL = settingsService.settings.gatewayURL
        let previousToken = settingsService.settings.authToken

        settingsService.update { s in
            s.gatewayHost = host
            s.gatewayPort = portInt
            s.authToken = token
            s.enableNotifications = enableNotifications
            s.refreshInterval = refreshInterval
            s.showOfflineAgents = showOfflineAgents
        }

        if settingsService.settings.gatewayURL != previousURL || token != previousToken {
            gatewayService.disconnect()
            gatewayService.connect(host: host, port: portInt, token: token)
        }

        Motion.perform(reduceMotion) { savedConfirmation = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            Motion.perform(reduceMotion) { savedConfirmation = false }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let portInt = Int(port) ?? 18789
                let ws = URLSession.shared.webSocketTask(with: URL(string: "ws://\(host):\(portInt)")!)
                ws.resume()
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    ws.sendPing { error in
                        if let e = error { cont.resume(throwing: e) } else { cont.resume() }
                    }
                }
                ws.cancel(with: .goingAway, reason: nil)
                testResult = "Success — connected"
            } catch {
                testResult = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
