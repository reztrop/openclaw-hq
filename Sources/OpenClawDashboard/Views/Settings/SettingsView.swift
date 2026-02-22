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

    private let inModal: Bool

    init(inModal: Bool = false) {
        self.inModal = inModal
    }

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
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // "[ SYS_CONFIG ]" header
                HStack(spacing: 4) {
                    Text("[")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan.opacity(0.6))
                    Text("SYS_CONFIG")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan)
                        .glitchText()
                    Text("]")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan.opacity(0.6))
                }

                // MARK: // API_CONNECTIONS
                settingsSection("API_CONNECTIONS", icon: "key.fill") {
                    if detectedProviders.isEmpty {
                        EmptyStateView(
                            icon: "key",
                            title: "No providers found",
                            subtitle: "Check ~/.openclaw/agents/main/agent/auth.json",
                            alignment: .leading,
                            textAlignment: .leading,
                            maxWidth: .infinity,
                            iconSize: 18,
                            contentPadding: 8,
                            showPanel: false
                        )
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(detectedProviders, id: \.self) { pid in
                                providerRow(pid)
                                if pid != detectedProviders.last {
                                    Rectangle()
                                        .fill(Theme.darkBorder.opacity(0.4))
                                        .frame(height: 1)
                                        .padding(.leading, 40)
                                }
                            }
                        }
                        .background(Theme.darkSurface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Only models from enabled providers will appear in the Chat model picker.")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                }

                // MARK: // GATEWAY
                settingsSection("GATEWAY", icon: "antenna.radiowaves.left.and.right") {
                    VStack(spacing: 12) {
                        labeledField("HOST") {
                            settingsField("127.0.0.1", text: $host, field: .host)
                        }
                        labeledField("PORT") {
                            settingsField("18789", text: $port, field: .port)
                        }
                        labeledField("AUTH_TOKEN") {
                            settingsField("token", text: $token, field: .token, isSecure: true)
                        }
                        HStack(spacing: 10) {
                            Button {
                                testConnection()
                            } label: {
                                HStack(spacing: 6) {
                                    if isTesting {
                                        ProgressView().scaleEffect(0.7)
                                        Text("PINGING...")
                                    } else {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                        Text("TEST_CONNECTION")
                                    }
                                }
                                .font(Theme.terminalFont)
                            }
                            .buttonStyle(HQButtonStyle(variant: .secondary))
                            .disabled(isTesting)

                            if let result = testResult {
                                // Terminal output style: "$ ping gateway... OK" or "ERR: ..."
                                let isSuccess = result.contains("Success")
                                HStack(spacing: 6) {
                                    Text("$")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(isSuccess ? Theme.statusOnline : Theme.statusOffline)
                                    Text(isSuccess ? "ping gateway... OK" : "ERR: \(result)")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(isSuccess ? Theme.statusOnline : Theme.statusOffline)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Theme.darkSurface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // MARK: // DISPLAY
                settingsSection("DISPLAY", icon: "paintbrush") {
                    VStack(spacing: 0) {
                        Toggle("ENABLE_NOTIFICATIONS", isOn: $enableNotifications)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textSecondary)
                            .tint(Theme.neonCyan)
                            .padding(14)
                        Rectangle()
                            .fill(Theme.darkBorder.opacity(0.4))
                            .frame(height: 1)
                        Toggle("SHOW_OFFLINE_AGENTS", isOn: $showOfflineAgents)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textSecondary)
                            .tint(Theme.neonCyan)
                            .padding(14)
                        Rectangle()
                            .fill(Theme.darkBorder.opacity(0.4))
                            .frame(height: 1)
                        HStack {
                            Text("AUTO_REFRESH_INTERVAL")
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.textSecondary)
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
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // MARK: Save / Reset
                HStack(spacing: 12) {
                    Button("RESET_DEFAULTS") {
                        settingsService.resetToDefaults()
                        loadFromSettings()
                        detectedProviders = readAuthProviders()
                    }
                    .buttonStyle(HQButtonStyle(variant: .danger))

                    Spacer()

                    if savedConfirmation {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("SAVED")
                        }
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.statusOnline)
                        .transition(.opacity)
                    }

                    Button("WRITE_CONFIG") { saveSettings() }
                        .buttonStyle(HQButtonStyle(variant: .glow))
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(24)
        }
        .onAppear {
            loadFromSettings()
            detectedProviders = readAuthProviders()
            seedEnabledProvidersIfNeeded()
        }

        if inModal {
            HQModalChrome(padding: 24) {
                content
                    .frame(maxWidth: 960, maxHeight: 720)
            }
        } else {
            content
                .background(Theme.darkBackground)
        }
    }

    // MARK: - Provider row

    private func providerRow(_ pid: String) -> some View {
        let enabled = isEnabled(pid)
        return HStack(spacing: 12) {
            Image(systemName: providerIcon(pid))
                .foregroundColor(enabled ? Theme.neonCyan : Theme.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(providerDisplayName(pid))
                    .font(Theme.terminalFont)
                    .foregroundColor(enabled ? Theme.textPrimary : Theme.textMuted)
                Text(pid)
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled(pid) },
                set: { _ in toggleProvider(pid) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.neonCyan)
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(Theme.neonCyan.opacity(0.7))
                Text("// \(title)")
                    .terminalLabel()
            }
            content()
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1)
                .frame(width: 100, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func settingsField(_ placeholder: String, text: Binding<String>, field: SettingsField, isSecure: Bool = false) -> some View {
        let isFocused = focusedField == field
        let isHovrd = hoveredField == field

        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(Theme.terminalFont)
        .foregroundColor(Theme.textPrimary)
        .cyberpunkInput(isFocused: isFocused)
        .focused($focusedField, equals: field)
        .onHover { hovering in
            updateHoveredField(field, hovering: hovering)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovrd)
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
