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
                enforceSidebarRules()
            }
            .onChange(of: geo.size.width) { _, newWidth in
                if newWidth < 980 {
                    isSidebarCollapsed = true
                }
                enforceSidebarRules()
            }
            .onChange(of: isSidebarCollapsed) { _, _ in
                enforceSidebarRules()
            }
            .onChange(of: appViewModel.isMainSidebarCollapsed) { _, _ in
                enforceSidebarRules()
            }
            .onChange(of: appViewModel.isCompactWindow) { _, _ in
                enforceSidebarRules()
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
            Picker("Model", selection: Binding(
                get: { chatVM.selectedModelId },
                set: { newId in
                    guard newId != chatVM.selectedModelId else { return }
                    chatVM.selectedModelId = newId
                    // Persist the model choice on the agent so the gateway uses it.
                    // Model selection must go through agents.update — not the agent RPC.
                    if let modelId = newId, !modelId.isEmpty {
                        let agentId = chatVM.currentAgentId
                        Task { try? await agentsVM.updateAgent(agentId: agentId, model: modelId) }
                    }
                }
            )) {
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

                    // Live streaming bubble — shows text as tokens arrive.
                    // Visible whenever isSending is true, even before text accumulates.
                    if chatVM.isSending {
                        streamingBubble
                            .id(chatVM.streamingBubbleId)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: chatVM.messages.count) { _, _ in
                if let last = chatVM.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: chatVM.streamingText) { _, _ in
                // Keep streaming bubble pinned to bottom as text grows
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo(chatVM.streamingBubbleId, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Compact status row — always visible while running
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chatVM.streamingLogExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        // Pulsing dot
                        ThinkingDotsView()
                            .frame(width: 28, height: 14)

                        if chatVM.streamingStatusLine.isEmpty {
                            Text("\(selectedAgentName()) is working…")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                        } else {
                            Text(chatVM.streamingStatusLine)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 560, alignment: .leading)
                        }

                        Spacer()

                        // Expand/collapse chevron — only show if there's log content
                        if let log = chatVM.streamingText, !log.isEmpty {
                            Image(systemName: chatVM.streamingLogExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.darkSurface)
                    .cornerRadius(10, corners: chatVM.streamingLogExpanded ? [.topLeft, .topRight] : [.topLeft, .topRight, .bottomLeft, .bottomRight])
                }
                .buttonStyle(.plain)

                // Expanded log — full raw stream, fixed height with scroll
                if chatVM.streamingLogExpanded, let log = chatVM.streamingText, !log.isEmpty {
                    ScrollView(.vertical) {
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.textMuted.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                    .background(Theme.darkSurface.opacity(0.6))
                    .cornerRadius(0)
                    .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.darkBorder.opacity(0.3), lineWidth: 1)
            )

            Spacer()
        }
        .padding(.horizontal, 16)
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

                if chatVM.isSending {
                    // Stop button — cancels the in-flight run
                    Button {
                        chatVM.stopCurrentRun()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Send button
                    Button {
                        Task { await chatVM.sendCurrentMessage() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        chatVM.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && chatVM.pendingAttachments.isEmpty
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }

                    Button {
                        startProjectPlanningMode()
                    } label: {
                        Label("Start Project Planning", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.darkSurface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if !chatVM.selectedConversationIsLockedToAgent {
                    modelPicker
                }
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Text(currentModelLabel())
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.darkSurface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 6) {
                    Toggle("", isOn: $chatVM.thinkingEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("Thinking")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize()
                }

                Spacer()
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
                        HStack(spacing: 6) {
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

                            Menu {
                                Button(role: .destructive) {
                                    archiveConversationFromRow(convo.id)
                                } label: {
                                    Label("Archive Chat", systemImage: "archivebox")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(Theme.textMuted)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
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

    private func currentModelLabel() -> String {
        if let selectedModelId = chatVM.selectedModelId,
           let selected = agentsVM.availableModels.first(where: { $0.id == selectedModelId }) {
            return selected.name
        }
        if let agent = agentsVM.agents.first(where: { $0.id == chatVM.currentAgentId }) {
            if let modelName = agent.modelName, !modelName.isEmpty { return modelName }
            if let model = agent.model, !model.isEmpty { return model }
        }
        return "Agent Default"
    }

    private func startProjectPlanningMode() {
        let jarvis = preferredJarvisId()
        chatVM.startNewChat(defaultAgentId: jarvis)
        chatVM.selectedAgentId = jarvis
        let seed = "[project] We are starting a new project. Ask clarifying questions until scope is complete. When the scope is fully defined, respond with [project-ready] and a concise scoped summary.\n\nProject brief: "
        if chatVM.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatVM.draftMessage = seed
        } else if !chatVM.draftMessage.lowercased().contains("[project]") {
            chatVM.draftMessage = "\(seed)\(chatVM.draftMessage)"
        }
    }

    private func archiveConversationFromRow(_ conversationId: String) {
        // Ensure action targets the row the user invoked, then archive that exact session.
        chatVM.selectedConversationId = conversationId
        chatVM.archiveConversation(conversationId)
    }

    private func enforceSidebarRules() {
        guard appViewModel.isCompactWindow else { return }

        if !isSidebarCollapsed {
            if !appViewModel.isMainSidebarCollapsed {
                appViewModel.isMainSidebarCollapsed = true
            }
        } else if appViewModel.isMainSidebarCollapsed {
            appViewModel.isMainSidebarCollapsed = false
        }
    }
}

// MARK: - Per-Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: [RectCorner]) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

enum RectCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    static var all: [RectCorner] { allCases }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: [RectCorner]

    init(radius: CGFloat, corners: [RectCorner]) {
        self.radius = radius
        self.corners = corners
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Thinking Dots

/// Three animated dots shown in the streaming bubble before the first token arrives.
struct ThinkingDotsView: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(phase == i ? 0.9 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
