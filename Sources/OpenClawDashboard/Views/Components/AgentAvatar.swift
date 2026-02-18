import SwiftUI

struct AgentAvatar: View {
    let agentName: String
    let isActive: Bool
    var size: CGFloat = 200

    @State private var showingActive = false

    var body: some View {
        ZStack {
            // Idle image / gradient (base)
            avatarLayer(active: false)
                .opacity(showingActive ? 0 : 1)

            // Active image / gradient (overlay)
            avatarLayer(active: true)
                .opacity(showingActive ? 1 : 0)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.15)
                .stroke(
                    Theme.agentColor(for: agentName).opacity(isActive ? 0.8 : 0.3),
                    lineWidth: isActive ? 3 : 1
                )
        )
        .shadow(
            color: isActive ? Theme.agentColor(for: agentName).opacity(0.4) : .clear,
            radius: isActive ? 12 : 0
        )
        .onChange(of: isActive) { _, newValue in
            withAnimation(.easeInOut(duration: 0.6)) {
                showingActive = newValue
            }
        }
        .onAppear {
            showingActive = isActive
        }
    }

    @ViewBuilder
    private func avatarLayer(active: Bool) -> some View {
        let state: AvatarState = active ? .active : .idle
        if let nsImage = AvatarService.shared.loadAvatar(for: agentName, state: state) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fill)
                .drawingGroup(opaque: false, colorMode: .linear)
        } else {
            // Gradient fallback when no image file is present
            GradientAvatarView(agentName: agentName, isActive: active, size: size)
        }
    }
}

// MARK: - Small Avatar (for task cards, lists)
struct AgentAvatarSmall: View {
    let agentName: String
    var size: CGFloat = 32

    var body: some View {
        if let nsImage = AvatarService.shared.loadAvatar(for: agentName, state: .active) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .drawingGroup(opaque: false, colorMode: .linear)
                .overlay(
                    Circle()
                        .stroke(Theme.agentColor(for: agentName).opacity(0.5), lineWidth: 1)
                )
        } else {
            GradientAvatarSmall(agentName: agentName, isActive: true, size: size)
        }
    }
}
