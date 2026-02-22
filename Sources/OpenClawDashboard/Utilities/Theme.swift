import SwiftUI

enum Theme {
    // MARK: - Backgrounds (Lofi Cyberpunk)
    static let darkBackground = Color(hex: "#090D15")
    static let darkSurface = Color(hex: "#111827")
    static let darkAccent = Color(hex: "#141F34")
    static let darkBorder = Color(hex: "#2A3A56")

    static let terminalGreen = Color(hex: "#95FFB8")
    static let neonCyan = Color(hex: "#4CF2FF")
    static let neonMagenta = Color(hex: "#FF5FD2")
    static let neonLime = Color(hex: "#C5FF6B")
    static let glitchAmber = Color(hex: "#FFE566")
    static let gridLineColor = Color(hex: "#2A3A56").opacity(0.3)

    // MARK: - Typography
    static let terminalFont = Font.system(.caption, design: .monospaced, weight: .regular)
    static let terminalFontSM = Font.system(.caption2, design: .monospaced, weight: .regular)
    static let headerFont = Font.system(.headline, design: .monospaced, weight: .bold)
    static let subheaderFont = Font.system(.subheadline, design: .monospaced, weight: .semibold)

    // MARK: - Scanline
    static let scanlineOpacity: Double = 0.07

    static let backdropGradient = LinearGradient(
        colors: [Color(hex: "#070A12"), Color(hex: "#111827"), Color(hex: "#0B1020")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Neon Glow Shadows
    static func neonGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        Rectangle()
            .fill(Color.clear)
            .shadow(color: color.opacity(0.7), radius: radius / 2, x: 0, y: 0)
            .shadow(color: color.opacity(0.35), radius: radius, x: 0, y: 0)
    }

    // MARK: - Agent Brand Colors
    static let jarvisBlue = Color(hex: "#4CF2FF")
    static let matrixOrange = Color(hex: "#FF9A4A")
    static let prismCyan = Color(hex: "#39E7FF")
    static let scopePurple = Color(hex: "#BD7CFF")
    static let atlasAmber = Color(hex: "#FFD36A")

    // MARK: - Status Colors
    static let statusOnline = Color(hex: "#4DF5A2")
    static let statusBusy = Color(hex: "#FFB454")
    static let statusIdle = Color(hex: "#7C8AA5")
    static let statusOffline = Color(hex: "#FF5A6A")

    // MARK: - Text
    static let textPrimary = Color(hex: "#DCE8FF")
    static let textSecondary = Color(hex: "#B5C6E6")
    static let textMuted = Color(hex: "#91A7CC")
    static let textMetadata = Color(hex: "#7CEBFF")

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
