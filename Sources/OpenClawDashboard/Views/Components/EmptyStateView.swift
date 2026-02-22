import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    var secondaryActionLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var alignment: HorizontalAlignment = .center
    var textAlignment: TextAlignment = .center
    var maxWidth: CGFloat? = 520
    var iconSize: CGFloat = 44
    var iconColor: Color = Theme.neonCyan.opacity(0.85)
    var contentPadding: CGFloat = 24
    var showPanel: Bool = true

    var body: some View {
        let content = VStack(alignment: alignment, spacing: 12) {
            // ASCII bracket frame around icon: "[ 🔍 ]"
            HStack(spacing: 4) {
                Text("[")
                    .font(.system(size: iconSize * 0.7, design: .monospaced).weight(.thin))
                    .foregroundColor(Theme.neonCyan.opacity(0.4))
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(iconColor)
                Text("]")
                    .font(.system(size: iconSize * 0.7, design: .monospaced).weight(.thin))
                    .foregroundColor(Theme.neonCyan.opacity(0.4))
            }

            // "// NO_DATA" prefix + title
            VStack(alignment: alignment, spacing: 4) {
                Text("// NO_DATA")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
                    .multilineTextAlignment(textAlignment)
                Text(title)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(textAlignment)
            }

            // Subtitle in muted monospaced
            if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                    .multilineTextAlignment(textAlignment)
            }

            // Action buttons
            if actionLabel != nil || secondaryActionLabel != nil {
                HStack(spacing: 12) {
                    if let secondaryActionLabel, let secondaryAction {
                        Button(secondaryActionLabel, action: secondaryAction)
                            .buttonStyle(HQButtonStyle(variant: .secondary))
                    }

                    if let actionLabel, let action {
                        Button(actionLabel, action: action)
                            .buttonStyle(HQButtonStyle(variant: .glow))
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth)
        .padding(contentPadding)

        if showPanel {
            HQPanel(cornerRadius: 16, surface: Theme.darkSurface.opacity(0.65), border: Theme.darkBorder.opacity(0.5), lineWidth: 1) {
                content
            }
        } else {
            content
        }
    }
}
