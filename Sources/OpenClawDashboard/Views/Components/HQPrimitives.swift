import SwiftUI

enum HQTone {
    case neutral
    case accent
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral: return Theme.textMuted
        case .accent: return Theme.jarvisBlue
        case .success: return Theme.statusOnline
        case .warning: return Theme.statusBusy
        case .danger: return Theme.statusOffline
        }
    }
}

struct HQPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let surface: Color
    private let border: Color
    private let lineWidth: CGFloat
    @ViewBuilder private let content: Content

    init(
        cornerRadius: CGFloat = 12,
        surface: Color = Theme.darkSurface.opacity(0.7),
        border: Color = Theme.darkBorder.opacity(0.7),
        lineWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.surface = surface
        self.border = border
        self.lineWidth = lineWidth
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(border, lineWidth: lineWidth)
                    )
            )
    }
}

struct HQCard<Content: View>: View {
    private let padding: CGFloat
    @ViewBuilder private let content: Content

    init(padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        HQPanel {
            content
                .padding(padding)
        }
    }
}

struct HQBadge: View {
    let text: String
    var tone: HQTone = .neutral
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.14))
        .clipShape(Capsule())
    }
}

struct HQStatusPill: View {
    let text: String
    let color: Color

    init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    init(agentStatus: AgentStatus) {
        text = agentStatus.label
        color = agentStatus.color
    }

    init(taskStatus: TaskStatus) {
        text = taskStatus.columnTitle
        color = taskStatus.color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
}

struct HQButton<Label: View>: View {
    private let action: () -> Void
    private let variant: HQButtonStyle.Variant
    @ViewBuilder private let label: Label

    init(variant: HQButtonStyle.Variant = .secondary, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.variant = variant
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(HQButtonStyle(variant: variant))
    }
}

struct HQButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Variant {
        case primary
        case secondary
        case danger
    }

    var variant: Variant = .secondary

    func makeBody(configuration: Configuration) -> some View {
        let colors = palette
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundColor(colors.foreground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.background.opacity(configuration.isPressed ? 0.75 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(colors.border, lineWidth: 1)
                    )
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var palette: (foreground: Color, background: Color, border: Color) {
        switch variant {
        case .primary:
            return (.black.opacity(0.9), Theme.jarvisBlue, Theme.jarvisBlue.opacity(0.9))
        case .secondary:
            return (.white, Theme.darkSurface, Theme.darkBorder)
        case .danger:
            return (.white, Theme.statusOffline.opacity(0.2), Theme.statusOffline.opacity(0.85))
        }
    }
}
