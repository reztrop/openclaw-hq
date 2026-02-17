import Foundation
import UserNotifications
import Combine

@MainActor
class NotificationService {
    private let settingsService: SettingsService
    private let gatewayService: GatewayService
    private var cancellables = Set<AnyCancellable>()
    private var wasConnected = true

    init(settingsService: SettingsService, gatewayService: GatewayService) {
        self.settingsService = settingsService
        self.gatewayService = gatewayService
        subscribeToEvents()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[Notifications] Permission error: \(error)")
            }
        }
    }

    private func subscribeToEvents() {
        // Agent errors
        gatewayService.agentEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self = self, self.settingsService.settings.enableNotifications else { return }
                let status = data["status"] as? String ?? ""
                if status == "error" {
                    let agentId = data["agentId"] as? String ?? "main"
                    let agentName = agentId == "main" ? "Jarvis" : agentId.capitalized
                    let activity = data["activity"] as? String ?? "Unknown error"
                    self.send(
                        title: "\(agentName) Error",
                        body: activity
                    )
                }
            }
            .store(in: &cancellables)

        // Connection lost/restored
        gatewayService.$connectionState
            .receive(on: DispatchQueue.main)
            .map { $0.isConnected }
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self = self, self.settingsService.settings.enableNotifications else { return }
                if !connected && self.wasConnected {
                    self.send(
                        title: "Gateway Disconnected",
                        body: "Lost connection to OpenClaw gateway"
                    )
                } else if connected && !self.wasConnected {
                    self.send(
                        title: "Gateway Connected",
                        body: "Reconnected to OpenClaw gateway"
                    )
                }
                self.wasConnected = connected
            }
            .store(in: &cancellables)
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notifications] Failed to send: \(error)")
            }
        }
    }
}
