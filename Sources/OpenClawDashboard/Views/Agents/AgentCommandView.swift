import SwiftUI

struct AgentCommandView: View {
    let agent: Agent
    @StateObject private var commandVM: CommandViewModel
    @State private var inputText = ""

    init(agent: Agent, gatewayService: GatewayService) {
        self.agent = agent
        _commandVM = StateObject(wrappedValue: CommandViewModel(gatewayService: gatewayService))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message history
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(commandVM.commandHistory) { command in
                            commandBubble(command)
                        }

                        if commandVM.isWaiting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(agent.brandColor)
                                Text("Waiting for response...")
                                    .font(.caption)
                                    .foregroundColor(Theme.textMuted)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .id("waiting")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: commandVM.commandHistory.count) { _, _ in
                    withAnimation {
                        scrollProxy.scrollTo("waiting", anchor: .bottom)
                    }
                }
            }

            Divider().background(Theme.darkBorder)

            // Input bar
            HStack(spacing: 8) {
                TextField("Send a command to \(agent.name)...", text: $inputText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Theme.darkSurface)
                    .cornerRadius(8)
                    .onSubmit {
                        sendCommand()
                    }

                Button {
                    sendCommand()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty || commandVM.isWaiting ? Theme.textMuted : agent.brandColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || commandVM.isWaiting)
            }
            .padding(12)
        }
    }

    private func commandBubble(_ command: AgentCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // User message
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(command.message)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(agent.brandColor.opacity(0.3))
                        .cornerRadius(12)
                    Text(command.timestamp.relativeString)
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 16)

            // Response
            if let response = command.response {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(agent.emoji)
                                .font(.caption)
                            Text(agent.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(agent.brandColor)
                        }
                        Text(response)
                            .font(.callout)
                            .foregroundColor(command.status == .failed ? Theme.statusOffline : .white)
                            .padding(10)
                            .background(Theme.darkSurface)
                            .cornerRadius(12)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sendCommand() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        inputText = ""
        Task {
            await commandVM.sendCommand(to: agent.name.lowercased(), message: message)
        }
    }
}
