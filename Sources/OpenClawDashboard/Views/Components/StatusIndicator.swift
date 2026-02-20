import SwiftUI

struct StatusIndicator: View {
    let status: AgentStatus
    var size: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Pulse ring
            if status.shouldPulse && !reduceMotion {
                Circle()
                    .fill(status.color.opacity(0.3))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            // Status dot
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)

            // Inner highlight
            Circle()
                .fill(status.color.opacity(0.5))
                .frame(width: size * 0.5, height: size * 0.5)
                .offset(x: -size * 0.1, y: -size * 0.1)
        }
        .onAppear {
            if status.shouldPulse {
                isPulsing = true
            }
        }
        .onChange(of: status) { _, newStatus in
            isPulsing = newStatus.shouldPulse
        }
    }
}
