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
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(Theme.terminalGreen)
        textView.backgroundColor = .clear
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.insertionPointColor = NSColor(Theme.neonCyan)

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
                lbl.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject var chatVM: ChatViewModel

    @State private var showImporter = false
    @State private var isTargetedForDrop = false
    @State private var isSidebarCollapsed = false
    @State private var showAddTagSheet = false
    @State private var newTagInput: String = ""
    @State private var availableTags: [String] = ["[project]", "[changes-requested]", "[final-approve]"]
    @State private var selectedTags: Set<String> = []
    @State private var showRenameSheet = false
    @State private var renameTargetId: String = ""
    @State private var renameInput: String = ""
    @State private var showClearAllConfirm = false
    @State private var showDeleteConfirm = false
    @State private var deleteTargetId: String = ""

    init(chatViewModel: ChatViewModel) {
        _chatVM = StateObject(wrappedValue: chatViewModel)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    Rectangle()
                        .fill(Theme.neonCyan.opacity(0.25))
                        .frame(height: 1)
                    messagesArea
                    // Composer top border
                    Rectangle()
                        .fill(Theme.neonCyan.opacity(0.5))
                        .frame(height: 2)
                    composer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isSidebarCollapsed {
                    Rectangle()
                        .fill(Theme.darkBorder.opacity(0.5))
                        .frame(width: 1)

                    sidebar
                        .frame(width: 320)
                        .background(
                            ZStack {
                                Theme.darkSurface.opacity(0.7)
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.12)
                            }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
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
        .preferredColorScheme(.dark)
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
                    .stroke(Theme.neonCyan, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(16)
                    .overlay {
                        Text("DROP_FILES_TO_ATTACH")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.neonCyan)
                            .padding(12)
                            .background(Theme.darkSurface.opacity(0.9))
                            .cornerRadius(10)
                    }
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Top Bar (terminal titlebar)

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("┌─[")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Theme.neonCyan.opacity(0.6))
                    Text("TERMINAL_CHAT")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan)
                        .glitchText()
                    Text("]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Theme.neonCyan.opacity(0.6))
                }

                Text(headerStatusLine())
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Agent picker or lock badge
            if chatVM.selectedConversationIsLockedToAgent {
                // Show clear badge instead of disabled picker
                let lockedAgent = agentsVM.agents.first { $0.id == chatVM.selectedAgentId }
                HStack(spacing: 6) {
                    Text("AGENT:")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                    Text("\(lockedAgent?.emoji ?? "🤖") \((lockedAgent?.name ?? "UNKNOWN").uppercased())")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.neonMagenta)
                    Text("[SESSION LOCKED]")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.neonMagenta.opacity(0.6))
                }
                .fixedSize()
            } else {
                HStack(spacing: 6) {
                    Text("SELECT_AGENT:")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .tracking(1)
                        .fixedSize()
                    Picker("Agent", selection: $chatVM.selectedAgentId) {
                        ForEach(agentsVM.agents, id: \.id) { agent in
                            Text("\(agent.emoji)  \(agent.name)").tag(agent.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }

            Spacer()

            Button {
                if reduceMotion {
                    isSidebarCollapsed.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarCollapsed.toggle()
                    }
                }
            } label: {
                Label(isSidebarCollapsed ? "Show Conversations" : "Hide Conversations",
                      systemImage: isSidebarCollapsed ? "rectangle.leadinghalf.filled" : "rectangle.righthalf.filled")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(HQButtonStyle(variant: .secondary))
            .help(isSidebarCollapsed ? "Show Conversations" : "Hide Conversations")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.darkSurface.opacity(0.9))
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

                    if chatVM.messages.isEmpty && !chatVM.isSending {
                        emptyState
                    }

                    if chatVM.isSending {
                        streamingBubble
                            .id(chatVM.streamingBubbleId)
                    }
                }
                .padding(.vertical, 12)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: chatVM.selectedConversationId) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: chatVM.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: chatVM.streamingText) { _, _ in
                if reduceMotion {
                    proxy.scrollTo(chatVM.streamingBubbleId, anchor: .bottom)
                } else {
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo(chatVM.streamingBubbleId, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No messages yet",
                subtitle: "Start a new message or attach files to kick things off.",
                alignment: .leading,
                textAlignment: .leading,
                maxWidth: 520,
                iconSize: 28,
                contentPadding: 16,
                showPanel: true
            )
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = chatVM.messages.last else { return }
        DispatchQueue.main.async {
            if animated && !reduceMotion {
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            } else {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var streamingBubble: some View {
        HStack(spacing: 10) {
            ThinkingDotsView()

            let statusText = chatVM.streamingStatusLine.isEmpty
                ? "\(selectedAgentName()) is working..."
                : chatVM.streamingStatusLine
            Text(statusText)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.neonCyan)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button {
                chatVM.stopCurrentRun()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("STOP")
                        .font(Theme.terminalFontSM)
                }
            }
            .buttonStyle(HQButtonStyle(variant: .danger))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.darkSurface.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.neonCyan.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        let isError = !message.isUser && message.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("error:")
        let agentName = selectedAgentName()
        let agentColor = Theme.agentColor(for: agentName)
        let borderColor = message.isUser
            ? Theme.neonCyan.opacity(0.5)
            : (isError ? Theme.statusOffline.opacity(0.8) : agentColor.opacity(0.35))
        let surfaceColor = message.isUser
            ? Theme.neonCyan.opacity(0.07)
            : (isError ? Theme.statusOffline.opacity(0.1) : Theme.darkSurface.opacity(0.92))
        let textColor = message.isUser
            ? Theme.textPrimary
            : (isError ? Theme.statusOffline : Theme.terminalGreen)

        return HStack(alignment: .top, spacing: 0) {
            if message.isUser { Spacer(minLength: 80) }

            if message.isUser {
                // User bubble with left cyan border stripe
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Theme.neonCyan)
                        .frame(width: 3)
                        .cornerRadius(3, corners: [.topLeft, .bottomLeft])

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(">")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundColor(Theme.neonCyan)
                            HQBadge(text: "USER", tone: .accent)
                        }

                        HQPanel(cornerRadius: 0, surface: surfaceColor, border: borderColor, lineWidth: 1) {
                            Text(message.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(textColor)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 8)
                }
                .background(surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                // Agent bubble
                VStack(alignment: .leading, spacing: 6) {
                    // Agent header line
                    HStack(spacing: 8) {
                        Text("[\(agentName.uppercased())]:")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(agentColor)
                        Text(selectedAgentRole())
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                    }

                    ScanlinePanel(opacity: 0.03) {
                        NeonBorderPanel(color: borderColor, cornerRadius: 12, surface: surfaceColor, lineWidth: 1) {
                            Text(message.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(textColor)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !message.isUser { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !chatVM.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatVM.pendingAttachments) { file in
                            // File pill styled as [filename]
                            HStack(spacing: 6) {
                                Text("[\(file.fileName)]")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.neonCyan)
                                    .lineLimit(1)
                                Button {
                                    chatVM.removeAttachment(file)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Theme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.darkSurface.opacity(0.85))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.neonCyan.opacity(0.35), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // ">" prefix in neonCyan before the text input
                Text(">")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan)
                    .padding(.bottom, 10)

                HQPanel(cornerRadius: 8, surface: Theme.darkSurface.opacity(0.9), border: Theme.neonCyan.opacity(0.3), lineWidth: 1) {
                    ComposerTextView(
                        text: $chatVM.draftMessage,
                        placeholder: "message \(selectedAgentName().lowercased())…  (shift+enter for newline)",
                        onSend: { Task { await sendCurrentMessageWithSelectedTags() } },
                        isSending: chatVM.isSending
                    )
                    .frame(minHeight: 36, maxHeight: 120)
                    .padding(6)
                }

                Button {
                    Task { await sendCurrentMessageWithSelectedTags() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(HQButtonStyle(variant: .glow))
                .disabled(
                    chatVM.isSending
                    || (chatVM.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && chatVM.pendingAttachments.isEmpty)
                )
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundColor(Theme.neonCyan)
                        Text("ATTACH")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.darkSurface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if !chatVM.selectedConversationIsLockedToAgent {
                    modelPicker
                }

                Menu {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            Label(tag, systemImage: selectedTags.contains(tag) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    Divider()
                    Button {
                        showAddTagSheet = true
                    } label: {
                        Label("Add Tag...", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Text(selectedTags.isEmpty ? "TAGS" : "TAGS(\(selectedTags.count))")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.darkSurface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Text(currentModelLabel())
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.darkSurface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 6) {
                    Toggle("", isOn: $chatVM.thinkingEnabled)
                        .toggleStyle(.switch)
                        .tint(Theme.neonCyan)
                        .labelsHidden()
                    Text("THINK")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize()
                }

                Spacer()
            }
        }
        .padding(12)
        .background(Theme.darkBackground)
        .sheet(isPresented: $showAddTagSheet) {
            HQModalChrome(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("// ADD_TAG")
                        .terminalLabel()
                    TextField("example: blocked", text: $newTagInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("CANCEL") {
                            newTagInput = ""
                            showAddTagSheet = false
                        }
                        .buttonStyle(HQButtonStyle(variant: .secondary))
                        Button("ADD") {
                            addTagFromInput()
                        }
                        .buttonStyle(HQButtonStyle(variant: .glow))
                        .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(width: 360)
            }
        }
    }

    // MARK: - Sidebar (// SESSIONS)

    private var sidebar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("// SESSIONS")
                    .terminalLabel()
                Spacer()

                // Clear All button
                if !chatVM.conversations.filter({ !$0.isDraft }).isEmpty {
                    Button {
                        showClearAllConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear All Conversations")
                    .confirmationDialog("Clear all conversations?", isPresented: $showClearAllConfirm, titleVisibility: .visible) {
                        Button("Clear All", role: .destructive) {
                            chatVM.clearAllConversations()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes all conversations from the list. Session history on the gateway is not deleted.")
                    }
                }

                Button {
                    chatVM.startNewChat(defaultAgentId: preferredJarvisId())
                } label: {
                    Label("NEW", systemImage: "plus")
                }
                .buttonStyle(HQButtonStyle(variant: .glow))
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(chatVM.conversations) { convo in
                        let isActive = chatVM.selectedConversationId == convo.id
                        HStack(spacing: 6) {
                            Button {
                                Task {
                                    chatVM.selectedAgentId = convo.agentId
                                    await chatVM.loadConversation(sessionKey: convo.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    // Active indicator
                                    if isActive {
                                        Text("▶")
                                            .font(Theme.terminalFontSM)
                                            .foregroundColor(Theme.neonCyan)
                                    } else {
                                        Text(" ")
                                            .font(Theme.terminalFontSM)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        let rowAgent = agentsVM.agents.first { $0.id == convo.agentId }
                                        HStack(spacing: 4) {
                                            Text("\(rowAgent?.emoji ?? "🤖") \((rowAgent?.name ?? "UNKNOWN").uppercased())")
                                                .font(Theme.terminalFontSM)
                                                .foregroundColor(isActive ? Theme.neonMagenta : Theme.textMuted)
                                            if convo.isPinned {
                                                Image(systemName: "pin.fill")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundColor(Theme.neonMagenta.opacity(0.7))
                                            }
                                        }
                                        Text(convo.title.isEmpty ? "SESSION" : convo.title.uppercased())
                                            .font(.system(.caption, design: .monospaced).weight(isActive ? .semibold : .regular))
                                            .foregroundColor(isActive ? Theme.neonCyan : Theme.textSecondary)
                                            .lineLimit(1)
                                        Text(convo.updatedAt.formatted(.dateTime.month().day().hour().minute()))
                                            .font(Theme.terminalFontSM)
                                            .foregroundColor(Theme.textMuted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(10)
                                .background(isActive ? Theme.neonCyan.opacity(0.08) : Theme.darkSurface.opacity(0.7))
                                .overlay(alignment: .leading) {
                                    if isActive {
                                        Rectangle()
                                            .fill(Theme.neonCyan)
                                            .frame(width: 2)
                                            .padding(.vertical, 4)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isActive ? Theme.neonCyan.opacity(0.5) : Theme.darkBorder.opacity(0.4), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            // Context menu
                            Menu {
                                // Pin / Unpin
                                Button {
                                    chatVM.pinConversation(convo.id, pinned: !convo.isPinned)
                                } label: {
                                    Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
                                }

                                // Rename (only for non-drafts)
                                if !convo.isDraft {
                                    Button {
                                        renameTargetId = convo.id
                                        renameInput = convo.title
                                        showRenameSheet = true
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                }

                                Divider()

                                // Archive
                                if !convo.isDraft {
                                    Button {
                                        chatVM.archiveConversation(convo.id)
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                }

                                // Delete
                                Button(role: .destructive) {
                                    deleteTargetId = convo.id
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
        // Rename sheet
        .sheet(isPresented: $showRenameSheet) {
            HQModalChrome(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("// RENAME SESSION")
                        .terminalLabel()
                    TextField("New name", text: $renameInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            commitRename()
                        }
                    HStack {
                        Spacer()
                        Button("CANCEL") {
                            showRenameSheet = false
                        }
                        .buttonStyle(HQButtonStyle(variant: .secondary))
                        Button("RENAME") {
                            commitRename()
                        }
                        .buttonStyle(HQButtonStyle(variant: .glow))
                        .disabled(renameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(width: 360)
            }
        }
        // Delete confirmation
        .confirmationDialog("Delete this conversation?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                chatVM.deleteConversation(deleteTargetId)
                deleteTargetId = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it from the list. Gateway session history is not deleted.")
        }
    }

    private func commitRename() {
        chatVM.renameConversation(renameTargetId, title: renameInput)
        showRenameSheet = false
        renameTargetId = ""
        renameInput = ""
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

    private func selectedAgentRole() -> String {
        Theme.agentRole(for: selectedAgentName())
    }

    private func headerStatusLine() -> String {
        let mode = chatVM.selectedConversationIsLockedToAgent ? "session:locked" : "session:draft"
        let agent = "agent:\(selectedAgentName().lowercased())"
        let role = "role:\(selectedAgentRole().lowercased().replacingOccurrences(of: " ", with: "-"))"
        return "\(mode) · \(agent) · \(role)"
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
        return "AGENT_DEFAULT"
    }

    private func archiveConversationFromRow(_ conversationId: String) {
        chatVM.selectedConversationId = conversationId
        chatVM.archiveConversation(conversationId)
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func addTagFromInput() {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = normalizeTag(trimmed)
        if !availableTags.contains(normalized) {
            availableTags.append(normalized)
        }
        selectedTags.insert(normalized)
        newTagInput = ""
        showAddTagSheet = false
    }

    private func normalizeTag(_ raw: String) -> String {
        let core = raw
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "[\(core)]"
    }

    private func sendCurrentMessageWithSelectedTags() async {
        if !selectedTags.isEmpty {
            let ordered = availableTags.filter { selectedTags.contains($0) }
            let prefix = ordered.joined(separator: " ")
            let draft = chatVM.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.isEmpty {
                chatVM.draftMessage = prefix
            } else {
                var missing: [String] = []
                let lower = draft.lowercased()
                for tag in ordered where !lower.contains(tag.lowercased()) {
                    missing.append(tag)
                }
                if !missing.isEmpty {
                    chatVM.draftMessage = "\(missing.joined(separator: " ")) \(draft)"
                }
            }
        }
        await chatVM.sendCurrentMessage()
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

// MARK: - Thinking Dots (cyberpunk blinking cursor + PROCESSING text)

/// Animated blinking block cursor with "PROCESSING..." label.
/// Preserves the original dot timer logic.
struct ThinkingDotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    @State private var cursorVisible = true

    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    private let cursorTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            // Blinking block cursor
            Text(cursorVisible || reduceMotion ? "█" : " ")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(Theme.neonCyan)
                .frame(width: 10)

            Text("PROCESSING")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)

            // Original dots logic alongside (hidden but preserving state)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity((reduceMotion ? 1 : phase) == i ? 0.6 : 0.15))
                        .frame(width: 4, height: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phase)
                }
            }
        }
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            phase = (phase + 1) % 3
        }
        .onReceive(cursorTimer) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                cursorVisible.toggle()
            }
        }
    }
}
