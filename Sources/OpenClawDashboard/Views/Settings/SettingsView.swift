import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var gatewayService: GatewayService

    @State private var host: String = ""
    @State private var port: String = ""
    @State private var token: String = ""
    @State private var enableNotifications: Bool = true
    @State private var refreshInterval: Int = 30
    @State private var showOfflineAgents: Bool = true
    @State private var testResult: String?
    @State private var isTesting: Bool = false
    @State private var savedConfirmation: Bool = false

    var body: some View {
        Form {
            Section("Gateway Connection") {
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                SecureField("Auth Token", text: $token)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Enable Notifications", isOn: $enableNotifications)
            }

            Section("Display") {
                Picker("Auto-Refresh Interval", selection: $refreshInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("Off").tag(0)
                }
                Toggle("Show Offline Agents", isOn: $showOfflineAgents)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 380)
        .onAppear {
            loadFromSettings()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset to Defaults") {
                    settingsService.resetToDefaults()
                    loadFromSettings()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                HStack(spacing: 8) {
                    if savedConfirmation {
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                    Button("Save") {
                        saveSettings()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

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

        // Reconnect if gateway config changed
        if settingsService.settings.gatewayURL != previousURL || token != previousToken {
            gatewayService.disconnect()
            gatewayService.connect(
                host: host,
                port: portInt,
                token: token
            )
        }

        // Show confirmation feedback
        withAnimation {
            savedConfirmation = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                savedConfirmation = false
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let portInt = Int(port) ?? 18789
                let testURL = "ws://\(host):\(portInt)"
                var request = URLRequest(url: URL(string: testURL)!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let session = URLSession(configuration: .default)
                let ws = session.webSocketTask(with: request)
                ws.resume()

                // Try to send a ping
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    ws.sendPing { error in
                        if let error = error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume()
                        }
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
