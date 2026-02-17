import Foundation

struct Session: Identifiable, Codable {
    var id: String { key }
    let key: String
    let agentId: String?
    let label: String?
    let model: String?
    let modelProvider: String?
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let updatedAt: Date?

    init(
        key: String,
        agentId: String? = nil,
        label: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalTokens: Int = 0,
        updatedAt: Date? = nil
    ) {
        self.key = key
        self.agentId = agentId
        self.label = label
        self.model = model
        self.modelProvider = modelProvider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.updatedAt = updatedAt
    }

    static func from(dict: [String: Any]) -> Session? {
        guard let key = dict["key"] as? String ?? dict["sessionId"] as? String else {
            return nil
        }
        let totalTokens = dict["totalTokens"] as? Int ?? 0
        let inputTokens = dict["inputTokens"] as? Int ?? 0
        let outputTokens = dict["outputTokens"] as? Int ?? 0

        var updatedAt: Date? = nil
        if let ts = dict["updatedAt"] as? Double {
            updatedAt = Date(timeIntervalSince1970: ts / 1000)
        } else if let ts = dict["updatedAt"] as? Int {
            updatedAt = Date(timeIntervalSince1970: Double(ts) / 1000)
        }

        return Session(
            key: key,
            agentId: dict["agentId"] as? String,
            label: dict["label"] as? String,
            model: dict["model"] as? String,
            modelProvider: dict["modelProvider"] as? String,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            updatedAt: updatedAt
        )
    }
}
