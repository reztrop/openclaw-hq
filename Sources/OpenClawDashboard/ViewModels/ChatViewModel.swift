import Foundation
import UniformTypeIdentifiers

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

    var isDraft: Bool { id.hasPrefix("draft:") }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: String?
    @Published var messages: [ChatMessage] = []
    @Published var draftMessage: String = ""
    @Published var selectedAgentId: String = "jarvis"
    @Published var thinkingEnabled: Bool = false
    @Published var selectedModelId: String? = nil   // nil = use the agent's default model
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isSending = false

    private let gatewayService: GatewayService
    private let maxInlineAttachmentChars = 12_000

    private var uploadsDir: String {
        NSString(string: "~/.openclaw/workspace/uploads/chat").expandingTildeInPath
    }

    init(gatewayService: GatewayService) {
        self.gatewayService = gatewayService
        ensureUploadDirectory()
    }

    func refresh(agentIds: [String]) async {
        do {
            let raw = try await gatewayService.fetchSessionsList()
            let mapped = raw.compactMap { dict -> ChatConversation? in
                guard let session = Session.from(dict: dict) else { return nil }
                let agentId = session.agentId ?? "jarvis"
                guard agentIds.isEmpty || agentIds.contains(agentId) else { return nil }
                return ChatConversation(
                    id: session.key,
                    title: session.label ?? "Chat",
                    agentId: agentId,
                    updatedAt: session.updatedAt ?? Date()
                )
            }
            conversations = mapped.sorted { $0.updatedAt > $1.updatedAt }

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

        do {
            let outboundSessionKey: String? = {
                guard let key = selectedConversationId, !key.hasPrefix("draft:") else { return nil }
                return key
            }()

            let response = try await gatewayService.sendAgentMessage(
                agentId: outboundAgentId,
                message: finalMessage,
                sessionKey: outboundSessionKey,
                thinkingEnabled: thinkingEnabled,
                modelId: selectedModelId
            )

            if let key = response.sessionKey {
                if let old = selectedConversationId, old.hasPrefix("draft:"), let idx = conversations.firstIndex(where: { $0.id == old }) {
                    conversations[idx] = ChatConversation(id: key, title: conversations[idx].title, agentId: outboundAgentId, updatedAt: Date())
                }
                selectedConversationId = key
            }

            let assistantText = response.text.isEmpty ? "(No response — the agent may still be processing. Try refreshing the conversation.)" : response.text
            messages.append(ChatMessage(id: UUID().uuidString, role: "assistant", text: assistantText, createdAt: Date()))

            if let key = selectedConversationId {
                let title = messages.first(where: { $0.isUser })?.text.prefix(64) ?? "Chat"
                let existing = conversations.firstIndex { $0.id == key }
                if let idx = existing {
                    conversations[idx].updatedAt = Date()
                    conversations[idx].agentId = outboundAgentId
                    if conversations[idx].title == "Chat" || conversations[idx].title == "New Chat" {
                        conversations[idx].title = String(title)
                    }
                } else {
                    conversations.insert(ChatConversation(id: key, title: String(title), agentId: outboundAgentId, updatedAt: Date()), at: 0)
                }
                conversations.sort { $0.updatedAt > $1.updatedAt }
            }
        } catch {
            messages.append(ChatMessage(id: UUID().uuidString, role: "assistant", text: "Error: \(error.localizedDescription)", createdAt: Date()))
        }

        pendingAttachments = []
        isSending = false
    }

    var selectedConversationIsLockedToAgent: Bool {
        guard let key = selectedConversationId else { return false }
        return !key.hasPrefix("draft:")
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
}
