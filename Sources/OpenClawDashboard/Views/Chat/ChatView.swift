import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var agentsVM: AgentsViewModel
    @StateObject var chatVM: ChatViewModel

    @State private var showImporter = false
    @State private var isTargetedForDrop = false

    init(chatViewModel: ChatViewModel) {
        _chatVM = StateObject(wrappedValue: chatViewModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                Divider().background(Theme.darkBorder)
                messagesArea
                Divider().background(Theme.darkBorder)
                composer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Theme.darkBorder)

            sidebar
                .frame(width: 320)
                .background(Theme.darkSurface.opacity(0.7))
        }
        .background(Theme.darkBackground)
        .task {
            await refreshData()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                chatVM.attachFiles(urls: urls)
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            chatVM.attachFiles(urls: items)
            isTargetedForDrop = false
            return true
        } isTargeted: { hovering in
            isTargetedForDrop = hovering
        }
        .overlay(alignment: .center) {
            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.jarvisBlue, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(16)
                    .overlay {
                        Text("Drop files to attach")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Theme.darkSurface.opacity(0.9))
                            .cornerRadius(10)
                    }
                    .transition(.opacity)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Chat")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Picker("Agent", selection: $chatVM.selectedAgentId) {
                ForEach(agentsVM.agents, id: \.id) { agent in
                    Text("\(agent.emoji) \(agent.name)").tag(agent.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)

            Toggle("Thinking", isOn: $chatVM.thinkingEnabled)
                .toggleStyle(.switch)
                .foregroundColor(Theme.textSecondary)

            Spacer()
        }
        .padding(14)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatVM.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if chatVM.isSending {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8).tint(Theme.jarvisBlue)
                            Text("Jarvis is thinking...")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: chatVM.messages.count) { _, _ in
                if let last = chatVM.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isUser { Spacer() }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.isUser ? "You" : "Assistant")
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
                Text(message.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(message.isUser ? Theme.jarvisBlue.opacity(0.35) : Theme.darkSurface)
                    .cornerRadius(12)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 700, alignment: .leading)
            if !message.isUser { Spacer() }
        }
        .padding(.horizontal, 16)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !chatVM.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatVM.pendingAttachments) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                Text(file.fileName)
                                    .lineLimit(1)
                                Button {
                                    chatVM.removeAttachment(file)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.darkSurface)
                            .cornerRadius(8)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.bordered)

                TextField("Message Jarvis...", text: $chatVM.draftMessage, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Theme.darkSurface)
                    .cornerRadius(8)
                    .onSubmit {
                        Task { await chatVM.sendCurrentMessage() }
                    }

                Button {
                    Task { await chatVM.sendCurrentMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(chatVM.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatVM.isSending)
            }
        }
        .padding(12)
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    chatVM.startNewChat(defaultAgentId: preferredJarvisId())
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(chatVM.conversations) { convo in
                        Button {
                            Task {
                                chatVM.selectedAgentId = convo.agentId
                                await chatVM.loadConversation(sessionKey: convo.id)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(convo.title.isEmpty ? "Chat" : convo.title)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                Text(convo.updatedAt.formatted(.dateTime.month().day().hour().minute()))
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(chatVM.selectedConversationId == convo.id ? Theme.darkAccent : Theme.darkSurface.opacity(0.7))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    private func refreshData() async {
        await agentsVM.refreshAgents()
        let ids = agentsVM.agents.map { $0.id }
        let jarvis = preferredJarvisId()
        if chatVM.selectedAgentId.isEmpty || !ids.contains(chatVM.selectedAgentId) {
            chatVM.selectedAgentId = jarvis
        }
        await chatVM.refresh(agentIds: ids)
    }

    private func preferredJarvisId() -> String {
        if let jarvis = agentsVM.agents.first(where: { $0.name.lowercased() == "jarvis" || $0.id.lowercased() == "jarvis" }) {
            return jarvis.id
        }
        return agentsVM.defaultAgentId ?? agentsVM.agents.first?.id ?? "jarvis"
    }
}
