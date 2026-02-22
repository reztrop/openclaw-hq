import Foundation
import UniformTypeIdentifiers
import Combine

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let createdAt: Date

    var isUser: Bool { role.lowercased() == "user" }
}

struct ChatAttachment: Identifiable, Hashable {
    let id = UUID().uuidString
    let fileName: String
    let localPath: String
    let sizeBytes: Int64
}

struct ChatConversation: Identifiable, Hashable {
    let id: String
    var title: String
    var agentId: String
    var updatedAt: Date
    var isPinned: Bool = false

    var isDraft: Bool { id.hasPrefix("draft:") }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: String?
    @Published var messages: [ChatMessage] = []
    @Published var draftMessage: String = ""
    @Published var selectedAgentId: String = "jarvis"
    @Published var thinkingEnabled: Bool = true
    @Published var selectedModelId: String? = nil   // nil = use the agent's default model

    /// The agent that will receive the next message — derived from the active conversation
    /// or falls back to selectedAgentId.
    var currentAgentId: String {
        if let key = selectedConversationId,
           !key.hasPrefix("draft:"),
           let convo = conversations.first(where: { $0.id == key }) {
            return convo.agentId
        }
        return selectedAgentId
    }
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isSending = false

    /// Full accumulated streaming text — used as fallback for the final committed message.
    /// Not rendered directly in the UI during streaming; use streamingStatusLine instead.
    @Published var streamingText: String? = nil

    /// The last meaningful line from the stream — shown in the compact status bubble.
    /// Updated as tokens arrive; stays short so the bubble stays small.
    @Published var streamingStatusLine: String = ""

    /// Whether the user has expanded the full streaming log inline.
    @Published var streamingLogExpanded: Bool = false

    /// The stable ID used for the streaming bubble so ScrollView can anchor to it.
    let streamingBubbleId = "streaming-bubble"

    private let gatewayService: GatewayService
    private let settingsService: SettingsService
    private let maxInlineAttachmentChars = 12_000
    private let genericConversationTitles: Set<String> = ["Chat", "New Chat"]
    private var cancellables = Set<AnyCancellable>()
    /// Session key of the in-flight message, used to filter streaming events to this conversation.
    private var activeRunSessionKey: String? = nil
    /// The Task wrapping the current sendAgentMessage call — cancelled by stopCurrentRun().
    private var sendTask: Task<Void, Never>? = nil
    var onProjectPlanningStarted: ((String, String) -> Void)?
    var onProjectScopeReady: ((String, String) -> Void)?
    var onProjectChatUserMessage: ((String, String) -> Void)?
    var onProjectChatAssistantMessage: ((String, String) -> Void)?

    private var uploadsDir: String {
        NSString(string: "~/.openclaw/workspace/uploads/chat").expandingTildeInPath
    }

    init(gatewayService: GatewayService, settingsService: SettingsService) {
        self.gatewayService = gatewayService
        self.settingsService = settingsService
        ensureUploadDirectory()
        subscribeToAgentEvents()
    }

    // MARK: - Streaming

    private func subscribeToAgentEvents() {
        gatewayService.agentEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleStreamingEvent(data) }
            .store(in: &cancellables)
    }

    private func handleStreamingEvent(_ data: [String: Any]) {
        guard isSending else { return }

        // Only process events for the current conversation's session key.
        // New chats use "agent:{agentId}:main" before a key is assigned.
        let eventSessionKey = data["sessionKey"] as? String ?? ""
        if let active = activeRunSessionKey {
            guard eventSessionKey == active else { return }
        } else {
            // No session key yet (new chat) — accept any event matching the outbound agent
            let agentId = data["agentId"] as? String
                ?? agentIdFromSessionKey(eventSessionKey)
            guard agentId == currentAgentId else { return }
        }

        let stream = data["stream"] as? String ?? ""
        let eventData = data["data"] as? [String: Any]

        switch stream {
        case "assistant":
            // Accumulate full text as fallback for the committed message
            if let chunk = eventData?["text"] as? String, !chunk.isEmpty {
                streamingText = (streamingText ?? "") + chunk
                // Update the status line with the last non-whitespace line of the stream
                let full = streamingText ?? ""
                let lastLine = full
                    .components(separatedBy: "\n")
                    .reversed()
                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                    ?? ""
                streamingStatusLine = lastLine
            }
        case "lifecycle":
            let phase = eventData?["phase"] as? String
            if phase == "end" || phase == "error" {
                // agent.wait / sendCurrentMessage will commit the final message.
                // Just clear the streaming buffer here — sendCurrentMessage handles appending.
                streamingText = nil
                activeRunSessionKey = nil
            }
        default:
            break
        }
    }

    /// Extracts agentId from session key format "agent:{agentId}:{rest}"
    private func agentIdFromSessionKey(_ sessionKey: String) -> String {
        let lower = sessionKey.lowercased()
        guard lower.hasPrefix("agent:") else { return "main" }
        let after = lower.dropFirst("agent:".count)
        return after.components(separatedBy: ":").first.map { String($0) } ?? "main"
    }

    func refresh(agentIds: [String]) async {
        do {
            let localMap = Dictionary(uniqueKeysWithValues: settingsService.settings.localChats.map { ($0.id, $0) })
            let raw = try await gatewayService.fetchSessionsList()
            let mapped = raw.compactMap { dict -> ChatConversation? in
                guard let session = Session.from(dict: dict) else { return nil }
                let agentId = session.agentId ?? "jarvis"
                guard agentIds.isEmpty || agentIds.contains(agentId) else { return nil }
                if localMap[session.key]?.isArchived == true { return nil }
                let fallbackTitle = session.label ?? "Chat"
                let localTitle = localMap[session.key]?.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (localTitle?.isEmpty == false) ? (localTitle ?? fallbackTitle) : fallbackTitle
                let pinned = localMap[session.key]?.isPinned ?? false
                return ChatConversation(
                    id: session.key,
                    title: title,
                    agentId: agentId,
                    updatedAt: session.updatedAt ?? Date(),
                    isPinned: pinned
                )
            }
            // Pinned conversations float to the top, then sorted by most recent
            conversations = mapped.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.updatedAt > $1.updatedAt
            }

            if let selected = selectedConversationId,
               !selected.hasPrefix("draft:"),
               !conversations.contains(where: { $0.id == selected }) {
                selectedConversationId = conversations.first?.id
            } else if selectedConversationId == nil {
                selectedConversationId = conversations.first?.id
            }

            if let key = selectedConversationId {
                await loadConversation(sessionKey: key)
            } else if let fallback = agentIds.first {
                selectedAgentId = fallback
                selectedModelId = nil
            }
        } catch {
            print("[ChatVM] refresh failed: \(error)")
        }
    }

    func startNewChat(defaultAgentId: String) {
        conversations.removeAll { $0.isDraft }

        let draftId = "draft:\(UUID().uuidString)"
        selectedConversationId = draftId
        selectedAgentId = defaultAgentId
        selectedModelId = nil
        messages = []
        draftMessage = ""
        pendingAttachments = []
        streamingText = nil
        isSending = false
        activeRunSessionKey = nil

        conversations.insert(
            ChatConversation(id: draftId, title: "New Chat", agentId: defaultAgentId, updatedAt: Date()),
            at: 0
        )
    }

    func loadConversation(sessionKey: String) async {
        selectedConversationId = sessionKey

        if sessionKey.hasPrefix("draft:") {
            if let convo = conversations.first(where: { $0.id == sessionKey }) {
                selectedAgentId = convo.agentId
            }
            messages = []
            return
        }

        if let convo = conversations.first(where: { $0.id == sessionKey }) {
            selectedAgentId = convo.agentId
        }
        // Model overrides are per-send UI choices and should not carry across conversations.
        selectedModelId = nil

        do {
            let history = try await gatewayService.fetchSessionHistory(sessionKey: sessionKey, limit: 200)
            messages = history
            ensureGeneratedTitle(for: sessionKey, messages: history)
        } catch {
            print("[ChatVM] history load failed: \(error)")
            messages = []
        }
    }

    func attachFiles(urls: [URL]) {
        var copied: [ChatAttachment] = []

        for sourceURL in urls {
            guard sourceURL.isFileURL else { continue }
            let destination = URL(fileURLWithPath: uploadsDir).appendingPathComponent(sourceURL.lastPathComponent)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    let ext = sourceURL.pathExtension
                    let stem = sourceURL.deletingPathExtension().lastPathComponent
                    let stamped = "\(stem)-\(Int(Date().timeIntervalSince1970)).\(ext)"
                    let uniqueDest = URL(fileURLWithPath: uploadsDir).appendingPathComponent(stamped)
                    try FileManager.default.copyItem(at: sourceURL, to: uniqueDest)
                    let size = (try? uniqueDest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    copied.append(ChatAttachment(fileName: uniqueDest.lastPathComponent, localPath: uniqueDest.path, sizeBytes: size))
                } else {
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    copied.append(ChatAttachment(fileName: destination.lastPathComponent, localPath: destination.path, sizeBytes: size))
                }
            } catch {
                print("[ChatVM] attachment copy failed for \(sourceURL.path): \(error)")
            }
        }

        pendingAttachments.append(contentsOf: copied)
    }

    func removeAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func sendCurrentMessage() async {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending else { return }
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }

        let userVisibleText = trimmed.isEmpty ? "[Attached files]" : trimmed
        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", text: userVisibleText, createdAt: Date())
        messages.append(userMsg)
        draftMessage = ""
        isSending = true

        var finalMessage = trimmed
        if !pendingAttachments.isEmpty {
            let attachmentContext = buildAttachmentContext(pendingAttachments)
            if finalMessage.isEmpty {
                finalMessage = "Please review the attached files and respond with findings.\n\n\(attachmentContext)"
            } else {
                finalMessage += "\n\n\(attachmentContext)"
            }
        }

        let outboundAgentId: String = {
            if let key = selectedConversationId,
               !key.hasPrefix("draft:"),
               let convo = conversations.first(where: { $0.id == key }) {
                return convo.agentId
            }
            return selectedAgentId
        }()
        if outboundAgentId.lowercased() == "jarvis",
           let key = selectedConversationId,
           !key.hasPrefix("draft:") {
            onProjectChatUserMessage?(key, userVisibleText)
        }
        let isProjectPlanningKickoff = outboundAgentId.lowercased() == "jarvis"
            && trimmed.lowercased().contains("[project]")

        // Set the session key so streaming events are filtered to this conversation.
        // For new chats it will be nil until the gateway returns the actual key.
        activeRunSessionKey = {
            guard let key = selectedConversationId, !key.hasPrefix("draft:") else { return nil }
            return key
        }()
        // Seed the streaming bubble immediately so the UI shows activity right away.
        streamingText = ""
        streamingStatusLine = ""
        streamingLogExpanded = false

        // Run the gateway call in a tracked Task so stopCurrentRun() can cancel it.
        let task = Task {
            await performSend(
                agentId: outboundAgentId,
                message: finalMessage,
                userVisibleText: userVisibleText,
                isProjectPlanningKickoff: isProjectPlanningKickoff
            )
        }
        sendTask = task
        await task.value
        sendTask = nil
    }

    /// Cancels the in-flight agent run immediately.
    /// The streaming bubble commits whatever text was already received, then closes.
    func stopCurrentRun() {
        sendTask?.cancel()
        sendTask = nil
    }

    private func performSend(agentId: String, message: String, userVisibleText: String, isProjectPlanningKickoff: Bool) async {
        let outboundSessionKey = activeRunSessionKey

        do {
            let response = try await gatewayService.sendAgentMessage(
                agentId: agentId,
                message: message,
                sessionKey: outboundSessionKey,
                thinkingEnabled: thinkingEnabled
            )

            if let key = response.sessionKey {
                // Update session key so streaming events after this point are filtered correctly.
                activeRunSessionKey = key
                if let old = selectedConversationId, old.hasPrefix("draft:"), let idx = conversations.firstIndex(where: { $0.id == old }) {
                    conversations[idx] = ChatConversation(id: key, title: conversations[idx].title, agentId: agentId, updatedAt: Date())
                }
                selectedConversationId = key
            }

            // Prefer the streamed text we accumulated; fall back to the polled history text
            // from agent.wait in case events were missed or out of order.
            let accumulated = streamingText ?? ""
            let finalText = accumulated.isEmpty ? response.text : accumulated
            let assistantText = finalText.isEmpty
                ? "(No response — the agent may still be processing. Try refreshing the conversation.)"
                : finalText

            commitResponse(text: assistantText, agentId: agentId, userVisibleText: userVisibleText)
            if let key = selectedConversationId {
                if isProjectPlanningKickoff {
                    onProjectPlanningStarted?(key, userVisibleText)
                }
                if agentId.lowercased() == "jarvis" {
                    onProjectChatAssistantMessage?(key, assistantText)
                }
                if assistantText.lowercased().contains("[project-ready]") {
                    onProjectScopeReady?(key, assistantText)
                }
            }

        } catch where Task.isCancelled || (error as? CancellationError) != nil {
            // User tapped stop — commit whatever streamed so far (may be empty)
            let partial = streamingText ?? ""
            let committedText = partial.isEmpty ? "(Stopped.)" : partial + "\n\n*(Stopped)*"
            commitResponse(text: committedText, agentId: agentId, userVisibleText: userVisibleText)

        } catch {
            streamingText = nil
            activeRunSessionKey = nil
            messages.append(ChatMessage(id: UUID().uuidString, role: "assistant", text: userFacingSendError(error), createdAt: Date()))
        }

        pendingAttachments = []
        isSending = false
    }

    private func commitResponse(text: String, agentId: String, userVisibleText: String) {
        streamingText = nil
        streamingStatusLine = ""
        streamingLogExpanded = false
        activeRunSessionKey = nil

        messages.append(ChatMessage(id: UUID().uuidString, role: "assistant", text: text, createdAt: Date()))

        if let key = selectedConversationId {
            let title = generateConversationTitle(from: userVisibleText, fallback: messages.first(where: { $0.isUser })?.text ?? "Chat")
            let existing = conversations.firstIndex { $0.id == key }
            if let idx = existing {
                conversations[idx].updatedAt = Date()
                conversations[idx].agentId = agentId
                if isGenericTitle(conversations[idx].title) {
                    conversations[idx].title = title
                }
            } else {
                conversations.insert(ChatConversation(id: key, title: title, agentId: agentId, updatedAt: Date()), at: 0)
            }
            saveChatConfig(sessionKey: key) { config in
                config.customTitle = title
                config.isArchived = false
            }
            conversations.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    private func userFacingSendError(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("unknown model") || lower.contains("model specified without provider") {
            return "Error: This agent's model is misconfigured. Set the model to a provider-qualified value such as openai-codex/gpt-5.3-codex in Agents settings."
        }
        return "Error: \(raw)"
    }

    var selectedConversationIsLockedToAgent: Bool {
        guard let key = selectedConversationId else { return false }
        return !key.hasPrefix("draft:")
    }

    func archiveConversation(_ sessionKey: String) {
        guard !sessionKey.hasPrefix("draft:") else {
            removeConversationFromList(sessionKey)
            return
        }
        saveChatConfig(sessionKey: sessionKey) { config in
            config.isArchived = true
        }
        removeConversationFromList(sessionKey)
    }

    func deleteConversation(_ sessionKey: String) {
        // Remove from local config entirely (not just archived)
        settingsService.update { settings in
            settings.localChats.removeAll { $0.id == sessionKey }
        }
        removeConversationFromList(sessionKey)
    }

    func clearAllConversations() {
        // Wipe all local chat configs and clear in-memory list
        settingsService.update { settings in
            settings.localChats = []
        }
        conversations.removeAll { !$0.isDraft }
        if let selected = selectedConversationId, !selected.hasPrefix("draft:") {
            selectedConversationId = conversations.first?.id
            messages = []
        }
    }

    func pinConversation(_ sessionKey: String, pinned: Bool) {
        if let idx = conversations.firstIndex(where: { $0.id == sessionKey }) {
            conversations[idx].isPinned = pinned
        }
        saveChatConfig(sessionKey: sessionKey) { config in
            config.isPinned = pinned
        }
        // Re-sort: pinned float to top
        conversations = conversations.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func renameConversation(_ sessionKey: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = conversations.firstIndex(where: { $0.id == sessionKey }) {
            conversations[idx].title = trimmed
        }
        saveChatConfig(sessionKey: sessionKey) { config in
            config.customTitle = trimmed
        }
    }

    // MARK: - Private helpers

    private func removeConversationFromList(_ sessionKey: String) {
        conversations.removeAll { $0.id == sessionKey }
        if selectedConversationId == sessionKey {
            selectedConversationId = conversations.first?.id
            if let first = selectedConversationId {
                Task { await loadConversation(sessionKey: first) }
            } else {
                messages = []
            }
        }
    }

    private func buildAttachmentContext(_ attachments: [ChatAttachment]) -> String {
        let filesList = attachments.map { "- \($0.fileName): \($0.localPath)" }.joined(separator: "\n")
        var blocks: [String] = [
            "Attached files (available on disk):",
            filesList,
            "Automatically inspect each file before responding. Use the attached files as first-class context for this reply."
        ]

        let analyses = attachments.compactMap { analyzeAttachment($0) }
        if !analyses.isEmpty {
            blocks.append("\nAttachment Analysis (auto-ingested preview):")
            blocks.append(analyses.joined(separator: "\n\n"))
        }

        return blocks.joined(separator: "\n")
    }

    private func analyzeAttachment(_ attachment: ChatAttachment) -> String? {
        let url = URL(fileURLWithPath: attachment.localPath)
        let ext = url.pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "yaml", "yml", "csv", "tsv", "xml",
            "swift", "js", "ts", "jsx", "tsx", "py", "go", "rs", "java", "c", "cpp", "h", "hpp", "sh", "zsh", "sql"
        ]

        if textExtensions.contains(ext),
           let data = FileManager.default.contents(atPath: attachment.localPath),
           let text = String(data: data, encoding: .utf8) {
            let excerpt = String(text.prefix(maxInlineAttachmentChars))
            return "File: \(attachment.fileName)\nType: text\nPreview:\n\(excerpt)"
        }

        if ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext) {
            return "File: \(attachment.fileName)\nType: image\nNote: Image attached at \(attachment.localPath). Inspect this image directly before answering."
        }

        if ext == "pdf" {
            return "File: \(attachment.fileName)\nType: pdf\nNote: PDF attached at \(attachment.localPath). Extract and inspect this document before answering."
        }

        return "File: \(attachment.fileName)\nType: binary/other\nNote: Attached at \(attachment.localPath). Inspect if needed."
    }

    private func ensureUploadDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: uploadsDir, withIntermediateDirectories: true)
        } catch {
            print("[ChatVM] failed to create uploads dir: \(error)")
        }
    }

    private func ensureGeneratedTitle(for sessionKey: String, messages: [ChatMessage]) {
        guard let idx = conversations.firstIndex(where: { $0.id == sessionKey }) else { return }
        guard isGenericTitle(conversations[idx].title) else { return }
        guard let firstUser = messages.first(where: { $0.isUser })?.text else { return }

        let title = generateConversationTitle(from: firstUser, fallback: firstUser)
        conversations[idx].title = title
        saveChatConfig(sessionKey: sessionKey) { config in
            config.customTitle = title
            config.isArchived = false
        }
    }

    private func generateConversationTitle(from candidate: String, fallback: String) -> String {
        let source = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = source
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = normalized.isEmpty || normalized == "[Attached files]" ? fallback : normalized
        if usable.isEmpty { return "Chat" }
        if usable.count <= 56 { return usable }
        let prefix = usable.prefix(56).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private func isGenericTitle(_ title: String) -> Bool {
        genericConversationTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveChatConfig(sessionKey: String, update: (inout LocalChatConversationConfig) -> Void) {
        settingsService.update { settings in
            var chats = settings.localChats
            var config = chats.first(where: { $0.id == sessionKey }) ?? LocalChatConversationConfig(id: sessionKey)
            update(&config)
            if let idx = chats.firstIndex(where: { $0.id == sessionKey }) {
                chats[idx] = config
            } else {
                chats.append(config)
            }
            settings.localChats = chats
        }
    }
}
