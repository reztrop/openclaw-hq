import SwiftUI

enum Theme {
    // MARK: - Backgrounds
    static let darkBackground = Color(hex: "#0F0F1A")
    static let darkSurface = Color(hex: "#1A1A2E")
    static let darkAccent = Color(hex: "#16213E")
    static let darkBorder = Color(hex: "#2A2A4A")

    // MARK: - Agent Brand Colors
    static let jarvisBlue = Color(hex: "#3B82F6")
    static let matrixOrange = Color(hex: "#F97316")
    static let prismCyan = Color(hex: "#06B6D4")
    static let scopePurple = Color(hex: "#A855F7")
    static let atlasAmber = Color(hex: "#F59E0B")

    // MARK: - Status Colors
    static let statusOnline = Color(hex: "#22C55E")
    static let statusBusy = Color(hex: "#F97316")
    static let statusIdle = Color(hex: "#6B7280")
    static let statusOffline = Color(hex: "#EF4444")

    // MARK: - Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#9CA3AF")
    static let textMuted = Color(hex: "#6B7280")

    // MARK: - Kanban Column Colors
    static let columnScheduled = Color(hex: "#6366F1")
    static let columnQueued = Color(hex: "#F59E0B")
    static let columnInProgress = Color(hex: "#3B82F6")
    static let columnDone = Color(hex: "#22C55E")

    // MARK: - Priority Colors
    static let priorityLow = Color(hex: "#6B7280")
    static let priorityMedium = Color(hex: "#3B82F6")
    static let priorityHigh = Color(hex: "#F97316")
    static let priorityUrgent = Color(hex: "#EF4444")

    // MARK: - Agent Color Lookup
    static func agentColor(for name: String) -> Color {
        switch name.lowercased() {
        case "jarvis": return jarvisBlue
        case "matrix": return matrixOrange
        case "prism": return prismCyan
        case "scope": return scopePurple
        case "atlas": return atlasAmber
        default: return textSecondary
        }
    }

    // MARK: - Agent Emoji Lookup
    static func agentEmoji(for name: String) -> String {
        switch name.lowercased() {
        case "jarvis": return "🧠"
        case "matrix": return "🧩"
        case "prism": return "🔍"
        case "scope": return "📐"
        case "atlas": return "🗺️"
        default: return "🤖"
        }
    }

    // MARK: - Agent Role Lookup
    static func agentRole(for name: String) -> String {
        switch name.lowercased() {
        case "jarvis": return "The Conductor"
        case "matrix": return "The Tinkerer"
        case "prism": return "The Skeptic"
        case "scope": return "The Architect"
        case "atlas": return "The Scholar"
        default: return "Agent"
        }
    }
}
