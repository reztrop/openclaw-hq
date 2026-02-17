import SwiftUI

// MARK: - GradientAvatarView
/// Shown when no avatar image file is available for an agent.
/// Active agents get a green gradient, idle/offline get a red gradient.
struct GradientAvatarView: View {
    let agentName: String
    let isActive: Bool
    var size: CGFloat = 120

    private var initial: String {
        String(agentName.prefix(1)).uppercased()
    }

    private var gradient: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [Color(red: 0.10, green: 0.47, blue: 0.29), Color(red: 0.18, green: 0.80, blue: 0.44)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 0.47, green: 0.10, blue: 0.10), Color(red: 0.80, green: 0.18, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(gradient)

            VStack(spacing: size * 0.04) {
                Text(initial)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(isActive ? "Active" : "Idle")
                    .font(.system(size: size * 0.16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Small Gradient Avatar
struct GradientAvatarSmall: View {
    let agentName: String
    let isActive: Bool
    var size: CGFloat = 32

    private var initial: String {
        String(agentName.prefix(1)).uppercased()
    }

    private var color: Color {
        isActive ? Color(red: 0.18, green: 0.80, blue: 0.44) : Color(red: 0.80, green: 0.18, blue: 0.18)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1))

            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        GradientAvatarView(agentName: "Prism", isActive: true, size: 120)
        GradientAvatarView(agentName: "Atlas", isActive: false, size: 120)
    }
    .padding()
    .background(Color.black)
}
