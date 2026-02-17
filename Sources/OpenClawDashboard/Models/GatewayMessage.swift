import Foundation

// MARK: - JSON-RPC Request
struct GatewayRequest: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]?

    init(id: Int, method: String, params: [String: Any]? = nil) {
        self.id = id
        self.method = method
        self.params = params?.mapValues { AnyCodable($0) }
    }
}

// MARK: - JSON-RPC Response
struct GatewayResponse: Decodable {
    let jsonrpc: String?
    let id: Int?
    let result: AnyCodable?
    let error: GatewayError?
}

struct GatewayError: Decodable, Error, LocalizedError {
    let code: Int?
    let message: String

    var errorDescription: String? { message }
}

// MARK: - Broadcast Event
struct GatewayBroadcast: Decodable {
    let type: String?
    let method: String?
    let params: AnyCodable?
    let data: AnyCodable?

    var eventType: String? { type ?? method }
    var eventData: AnyCodable? { data ?? params }
}

// MARK: - AnyCodable Wrapper
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    // MARK: - Value Accessors
    var dictionary: [String: Any]? { value as? [String: Any] }
    var array: [Any]? { value as? [Any] }
    var string: String? { value as? String }
    var int: Int? { value as? Int }
    var double: Double? { value as? Double }
    var bool: Bool? { value as? Bool }

    subscript(key: String) -> Any? {
        (value as? [String: Any])?[key]
    }

    subscript(index: Int) -> Any? {
        guard let arr = value as? [Any], index < arr.count else { return nil }
        return arr[index]
    }
}
