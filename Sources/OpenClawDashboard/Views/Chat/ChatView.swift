import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Smart Composer Text View
// NSViewRepresentable so we can intercept Enter vs Shift+Enter at the AppKit level.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSend: () -> Void
    var isSending: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 6)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.isSending = isSending

        // Only update if the text actually changed (avoid cursor-jump loop)
        if textView.string != text {
            textView.string = text
        }

        // Placeholder visibility
        context.coordinator.updatePlaceholder(textView, placeholder: placeholder)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        var isSending: Bool = false
        weak var textView: NSTextView?
        private var placeholderLabel: NSTextField?

        init(_ parent: ComposerTextView) { self.parent = parent }

        // Enter → send; Shift+Enter → newline
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftDown = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                if shiftDown {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    if !isSending && !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parent.onSend()
                    }
                    return true
                }
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updatePlaceholder(textView, placeholder: parent.placeholder)
        }

        func updatePlaceholder(_ textView: NSTextView, placeholder: String) {
            if placeholderLabel == nil {
                let lbl = NSTextField(labelWithString: "")
                lbl.textColor = NSColor.tertiaryLabelColor
                lbl.font = .systemFont(ofSize: 13)
                lbl.isEditable = false
                lbl.isSelectable = false
                lbl.isBordered = false
                lbl.backgroundColor = .clear
                textView.addSubview(lbl)
                placeholderLabel = lbl
            }
            placeholderLabel?.stringValue = textView.string.isEmpty ? placeholder : ""
            placeholderLabel?.frame = NSRect(x: 6, y: 4, width: textView.bounds.width - 12, height: 20)
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var agentsVM: AgentsViewModel
    @StateObject var chatVM: ChatViewModel

    @State private var showImporter = false
    @State private var isTargetedForDrop = false
    @State private var isSidebarCollapsed = false

    init(chatViewModel: ChatViewModel) {
        _chatVM = StateObject(wrappedValue: chatViewModel)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    Divider().background(Theme.darkBorder)
                    messagesArea
                    Divider().background(Theme.darkBorder)
                    composer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isSidebarCollapsed {
                    Divider().background(Theme.darkBorder)

                    sidebar
                        .frame(width: 320)
                        .background(Theme.darkSurface.opacity(0.7))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onAppear {
                if geo.size.width < 1180 {
                    isSidebarCollapsed = true
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                if newWidth < 980 {
                    isSidebarCollapsed = true
                }
            }
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

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Chat")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .fixedSize()

            // Agent picker
            Picker("Agent", selection: $chatVM.selectedAgentId) {
                ForEach(agentsVM.agents, id: \.id) { agent in
                    Text("\(agent.emoji)  \(agent.name)").tag(agent.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .disabled(chatVM.selectedConversationIsLockedToAgent)

            // Model picker — only shown when conversation is not locked
            if !chatVM.selectedConversationIsLockedToAgent {
                modelPicker
            }

            // Thinking toggle — fixed size label so it never wraps or rotates
            HStack(spacing: 6) {
                Toggle("", isOn: $chatVM.thinkingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("Thinking")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize()
            }

            if chatVM.selectedConversationIsLockedToAgent {
                Text("Agent fixed — start a new chat to switch")
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
                    .fixedSize()
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarCollapsed.toggle()
                }
            } label: {
                Label(isSidebarCollapsed ? "Show Conversations" : "Hide Conversations",
                      systemImage: isSidebarCollapsed ? "rectangle.leadinghalf.filled" : "rectangle.righthalf.filled")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(isSidebarCollapsed ? "Show Conversations" : "Hide Conversations")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .task { await agentsVM.loadModels() }
    }

    @ViewBuilder
    private var modelPicker: some View {
        let models = filteredModels
        if !models.isEmpty {
            Picker("Model", selection: $chatVM.selectedModelId) {
                Text("Agent Default").tag(Optional<String>.none)
                Divider()
                ForEach(models) { model in
                    Text(model.name).tag(Optional(model.id))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
        }
    }

    /// Models available for manual override.
    /// models.list already reflects only connected providers; spark is stripped at load.
    private var filteredModels: [ModelInfo] {
        agentsVM.availableModels
    }

    // MARK: - Messages Area

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
                            Text("\(selectedAgentName()) is thinking...")
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
                Text(message.isUser ? "You" : selectedAgentName())
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

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !chatVM.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatVM.pendingAttachments) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                Text(file.fileName).lineLimit(1)
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

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.bordered)

                // Scrollable multi-line composer with Enter-to-send / Shift+Enter for newline
                ComposerTextView(
                    text: $chatVM.draftMessage,
                    placeholder: "Message \(selectedAgentName())…  (Shift+Enter for new line)",
                    onSend: { Task { await chatVM.sendCurrentMessage() } },
                    isSending: chatVM.isSending
                )
                .frame(minHeight: 36, maxHeight: 120)
                .padding(6)
                .background(Theme.darkSurface)
                .cornerRadius(8)

                Button {
                    Task { await chatVM.sendCurrentMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    (chatVM.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatVM.pendingAttachments.isEmpty)
                    || chatVM.isSending
                )
            }
        }
        .padding(12)
    }

    // MARK: - Sidebar

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

    // MARK: - Helpers

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

    private func selectedAgentName() -> String {
        agentsVM.agents.first(where: { $0.id == chatVM.selectedAgentId })?.name ?? "Agent"
    }
}
