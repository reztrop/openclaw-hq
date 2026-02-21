import SwiftUI

struct HQStateView: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var tone: HQTone = .accent
    var iconSize: CGFloat = 34
    var maxWidth: CGFloat? = 520
    var contentPadding: CGFloat = 28
    var showPanel: Bool = true
    var showsProgress: Bool = false
    var progressTint: Color = Theme.neonCyan
    var subtitleFont: Font = .system(.caption, design: .monospaced)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = VStack(spacing: 12) {
            if showsProgress {
                if reduceMotion {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: iconSize * 0.8, weight: .semibold))
                        .foregroundColor(progressTint)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(progressTint)
                }
            }

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(tone.color)
            }

            Text(title)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)

            if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundColor(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: maxWidth)
        .padding(contentPadding)

        if showPanel {
            HQPanel(cornerRadius: 16, surface: Theme.darkSurface.opacity(0.7), border: tone.color.opacity(0.45), lineWidth: 1) {
                content
            }
        } else {
            content
        }
    }
}

struct HQInlineStatusView: View {
    enum Kind {
        case loading
        case error
        case info

        var color: Color {
            switch self {
            case .loading: return Theme.textMuted
            case .error: return Theme.statusOffline
            case .info: return Theme.textSecondary
            }
        }
    }

    var kind: Kind = .info
    var text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if kind == .loading {
                if reduceMotion {
                    Image(systemName: "circle.dotted")
                        .font(.caption)
                        .foregroundColor(Theme.neonCyan)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.neonCyan)
                }
            } else if kind == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(kind.color)
            } else {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(kind.color)
            }

            Text(text)
                .font(.caption)
                .foregroundColor(kind.color)
        }
    }
}
