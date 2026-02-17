import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
            if let actionLabel = actionLabel, let action = action {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .tint(Theme.jarvisBlue)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
