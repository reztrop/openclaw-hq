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
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: String?
    @Published var messages: [ChatMessage] = []
    @Published var draftMessage: String = ""
    @Published var selectedAgentId: String = "jarvis"
    @Published var thinkingEnabled: Bool = false
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isSending = false

    private let gatewayService: GatewayService

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

            if selectedConversationId == nil {
                selectedConversationId = conversations.first?.id
            }

            if let key = selectedConversationId {
                await loadConversation(sessionKey: key)
            }
        } catch {
            print("[ChatVM] refresh failed: \(error)")
        }
    }

    func startNewChat(defaultAgentId: String) {
        selectedConversationId = nil
        selectedAgentId = defaultAgentId
        messages = []
        draftMessage = ""
        pendingAttachments = []
    }

    func loadConversation(sessionKey: String) async {
        selectedConversationId = sessionKey
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
        guard !trimmed.isEmpty, !isSending else { return }

        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", text: trimmed, createdAt: Date())
        messages.append(userMsg)
        draftMessage = ""
        isSending = true

        var finalMessage = trimmed
        if !pendingAttachments.isEmpty {
            let filesList = pendingAttachments.map { "- \($0.fileName): \($0.localPath)" }.joined(separator: "\n")
            finalMessage += "\n\nAttached files (available on disk):\n\(filesList)\nUse these files as reference for this conversation."
        }

        do {
            let response = try await gatewayService.sendAgentMessage(
                agentId: selectedAgentId,
                message: finalMessage,
                sessionKey: selectedConversationId,
                thinkingEnabled: thinkingEnabled
            )

            if let key = response.sessionKey {
                selectedConversationId = key
            }

            let assistantText = response.text.isEmpty ? "(No response body)" : response.text
            messages.append(ChatMessage(id: UUID().uuidString, role: "assistant", text: assistantText, createdAt: Date()))

            if let key = selectedConversationId {
                let title = messages.first(where: { $0.isUser })?.text.prefix(64) ?? "Chat"
                let existing = conversations.firstIndex { $0.id == key }
                if let idx = existing {
                    conversations[idx].updatedAt = Date()
                    conversations[idx].agentId = selectedAgentId
                    if conversations[idx].title == "Chat" {
                        conversations[idx].title = String(title)
                    }
                } else {
                    conversations.insert(ChatConversation(id: key, title: String(title), agentId: selectedAgentId, updatedAt: Date()), at: 0)
                }
            }
        } catch {
            messages.append(ChatMessage(id: UUID().uuidString, role: "assistant", text: "Error: \(error.localizedDescription)", createdAt: Date()))
        }

        pendingAttachments = []
        isSending = false
    }

    private func ensureUploadDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: uploadsDir, withIntermediateDirectories: true)
        } catch {
            print("[ChatVM] failed to create uploads dir: \(error)")
        }
    }
}
