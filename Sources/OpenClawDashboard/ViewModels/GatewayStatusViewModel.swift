import Foundation
import Combine

@MainActor
class GatewayStatusViewModel: ObservableObject {
    @Published var health: GatewayHealth?

    private let gatewayService: GatewayService
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    init(gatewayService: GatewayService) {
        self.gatewayService = gatewayService

        // Subscribe to health events
        gatewayService.healthEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.health = GatewayHealth.from(dict: data)
            }
            .store(in: &cancellables)

        // Subscribe to tick events — update active runs
        gatewayService.tickEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard var current = self?.health else { return }
                if let runs = data["activeRuns"] as? Int {
                    current.activeRuns = runs
                }
                if let runsList = data["runs"] as? [[String: Any]] {
                    current.activeRuns = runsList.count
                }
                current.lastHeartbeat = Date()
                self?.health = current
            }
            .store(in: &cancellables)

        startPolling()
    }

    func refreshHealth() async {
        do {
            if let dict = try await gatewayService.fetchHealth() {
                health = GatewayHealth.from(dict: dict)
            }

            // Also fetch status for active runs and presence info
            if let statusDict = try await gatewayService.fetchStatus() {
                if var h = health {
                    if let runs = statusDict["runs"] as? [[String: Any]] {
                        h.activeRuns = runs.count
                    }
                    if let presence = statusDict["presence"] as? [[String: Any]] {
                        h.connectedDevices = presence.count
                    }
                    if let model = statusDict["model"] as? String {
                        h.model = model
                    }
                    health = h
                }
            }
        } catch {
            print("[GatewayStatus] Health fetch failed: \(error)")
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.gatewayService.isConnected == true {
                    await self?.refreshHealth()
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }
}
