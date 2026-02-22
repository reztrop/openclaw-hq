import SwiftUI
import Combine

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
    var color: Color? = nil

    var body: some View {
        let resolvedColor = color ?? tone.color
        return HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(resolvedColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(resolvedColor.opacity(0.14))
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
        case glow
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
                            .stroke(colors.border, lineWidth: variant == .glow ? 1.5 : 1)
                    )
            )
            .shadow(color: variant == .glow ? colors.border.opacity(configuration.isPressed ? 0.9 : 0.5) : .clear,
                    radius: configuration.isPressed ? 10 : 6, x: 0, y: 0)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
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
        case .glow:
            return (Theme.neonCyan, Theme.neonCyan.opacity(0.08), Theme.neonCyan.opacity(0.7))
        }
    }
}

// MARK: - NeonBorderPanel
/// HQPanel variant with a gently pulsing neon border. Falls back to static when reduceMotion is on.
struct NeonBorderPanel<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let color: Color
    private let cornerRadius: CGFloat
    private let surface: Color
    private let lineWidth: CGFloat
    @ViewBuilder private let content: Content

    init(
        color: Color = Theme.neonCyan,
        cornerRadius: CGFloat = 12,
        surface: Color = Theme.darkSurface.opacity(0.75),
        lineWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.surface = surface
        self.lineWidth = lineWidth
        self.content = content()
    }

    private var borderOpacity: Double { reduceMotion ? 0.45 : (pulse ? 0.75 : 0.35) }
    private var glowRadius: CGFloat { reduceMotion ? 0 : (pulse ? 10 : 4) }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(color.opacity(borderOpacity), lineWidth: lineWidth)
                    )
                    .shadow(color: color.opacity(pulse && !reduceMotion ? 0.3 : 0.1),
                            radius: glowRadius, x: 0, y: 0)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - TerminalLabel ViewModifier
struct TerminalLabelModifier: ViewModifier {
    var color: Color = Theme.textMetadata
    var size: Font = Theme.terminalFont

    func body(content: Content) -> some View {
        content
            .font(size)
            .foregroundColor(color)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

extension View {
    func terminalLabel(color: Color = Theme.textMetadata, size: Font = Theme.terminalFont) -> some View {
        modifier(TerminalLabelModifier(color: color, size: size))
    }
}

// MARK: - ScanlinePanel
/// Wraps content with a CRT scanline overlay at configurable opacity.
struct ScanlinePanel<Content: View>: View {
    private let opacity: Double
    @ViewBuilder private let content: Content

    init(opacity: Double = 0.05, @ViewBuilder content: () -> Content) {
        self.opacity = opacity
        self.content = content()
    }

    var body: some View {
        content
            .overlay(
                GeometryReader { geo in
                    let lines = Int(geo.size.height / 3)
                    VStack(spacing: 2) {
                        ForEach(0..<max(lines, 1), id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(opacity))
                                .frame(height: 1)
                        }
                    }
                }
                .allowsHitTesting(false)
            )
    }
}

// MARK: - CRTFlicker ViewModifier
struct CRTFlickerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flickerOpacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(flickerOpacity)
            .onAppear {
                guard !reduceMotion else { return }
                scheduleFlicker()
            }
    }

    private func scheduleFlicker() {
        let delay = Double.random(in: 3.0...8.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.05)) { flickerOpacity = Double.random(in: 0.94...0.98) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.05)) { flickerOpacity = 1.0 }
                scheduleFlicker()
            }
        }
    }
}

extension View {
    func crtFlicker() -> some View {
        modifier(CRTFlickerModifier())
    }
}

// MARK: - GlitchText ViewModifier
struct GlitchTextModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offsetX: CGFloat = 0
    @State private var showGhost = false
    var color: Color = Theme.neonMagenta

    func body(content: Content) -> some View {
        ZStack {
            if showGhost && !reduceMotion {
                content
                    .foregroundColor(color.opacity(0.5))
                    .offset(x: offsetX, y: 0)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            content
        }
        .onAppear {
            guard !reduceMotion else { return }
            scheduleGlitch()
        }
    }

    private func scheduleGlitch() {
        let delay = Double.random(in: 8.0...18.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !reduceMotion else { return }
            offsetX = CGFloat.random(in: -3 ... 3)
            withAnimation(.easeInOut(duration: 0.06)) { showGhost = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.06)) { showGhost = false }
                scheduleGlitch()
            }
        }
    }
}

extension View {
    func glitchText(color: Color = Theme.neonMagenta) -> some View {
        modifier(GlitchTextModifier(color: color))
    }
}

// MARK: - Cyberpunk text input style helper
extension View {
    /// Applies a terminal-style bottom-border-only input treatment with neon focus glow.
    func cyberpunkInput(isFocused: Bool, accentColor: Color = Theme.neonCyan) -> some View {
        self
            .font(Theme.terminalFont)
            .foregroundColor(Theme.textPrimary)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Theme.darkBackground)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(isFocused ? accentColor : Theme.darkBorder)
                        .frame(height: isFocused ? 2 : 1)
                }
            )
            .shadow(color: isFocused ? accentColor.opacity(0.3) : .clear, radius: 6, x: 0, y: 2)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
