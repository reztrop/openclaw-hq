import Foundation

struct GatewayHealth {
    var isHealthy: Bool
    var uptime: TimeInterval?
    var lastHeartbeat: Date
    var activeRuns: Int
    var connectedDevices: Int
    var model: String?
    var version: String?

    static func from(dict: [String: Any]) -> GatewayHealth {
        let uptime: TimeInterval?
        if let u = dict["uptime"] as? Double {
            uptime = u
        } else if let u = dict["uptime"] as? Int {
            uptime = Double(u)
        } else {
            uptime = nil
        }

        let runs: Int
        if let r = dict["activeRuns"] as? Int {
            runs = r
        } else if let runsList = dict["runs"] as? [[String: Any]] {
            runs = runsList.count
        } else {
            runs = 0
        }

        let devices: Int
        if let d = dict["connectedDevices"] as? Int {
            devices = d
        } else if let p = dict["presence"] as? [[String: Any]] {
            devices = p.count
        } else {
            devices = 0
        }

        return GatewayHealth(
            isHealthy: dict["healthy"] as? Bool ?? true,
            uptime: uptime,
            lastHeartbeat: Date(),
            activeRuns: runs,
            connectedDevices: devices,
            model: dict["model"] as? String,
            version: dict["version"] as? String
        )
    }

    var uptimeString: String {
        guard let uptime = uptime else { return "—" }
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
