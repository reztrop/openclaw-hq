import Foundation

@MainActor
class CommandViewModel: ObservableObject {
    @Published var commandHistory: [AgentCommand] = []
    @Published var isWaiting = false

    private let gatewayService: GatewayService

    init(gatewayService: GatewayService) {
        self.gatewayService = gatewayService
    }

    func sendCommand(to agentId: String, message: String) async {
        var command = AgentCommand(agentId: agentId, message: message)
        command.status = .sent
        commandHistory.append(command)
        let index = commandHistory.count - 1
        isWaiting = true

        do {
            let result = try await gatewayService.sendAgentCommand(agentId, message: message)
            commandHistory[index].status = .completed

            // Extract response text from result
            if let response = result?["response"] as? String {
                commandHistory[index].response = response
            } else if let text = result?["text"] as? String {
                commandHistory[index].response = text
            } else if let output = result?["output"] as? String {
                commandHistory[index].response = output
            } else if let result = result {
                commandHistory[index].response = String(describing: result)
            } else {
                commandHistory[index].response = "Command sent (no response)"
            }
        } catch {
            commandHistory[index].status = .failed
            commandHistory[index].response = "Error: \(error.localizedDescription)"
        }

        isWaiting = false
    }

    func clearHistory() {
        commandHistory.removeAll()
    }
}
