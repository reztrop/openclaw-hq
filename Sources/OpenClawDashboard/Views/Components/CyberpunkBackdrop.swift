import SwiftUI

struct CyberpunkBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloom = false

    var body: some View {
        ZStack {
            // Base gradient
            Theme.backdropGradient
                .ignoresSafeArea()

            // Neon colour overlay
            LinearGradient(
                colors: [Theme.neonCyan.opacity(0.08), .clear, Theme.neonMagenta.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            // Animated bloom in top-left corner
            RadialGradient(
                colors: [Theme.neonCyan.opacity(bloom && !reduceMotion ? 0.07 : 0.03), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 8.0).repeatForever(autoreverses: true),
                value: bloom
            )

            // Terminal grid overlay
            TerminalGridOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Scanline overlay (denser)
            ScanlineOverlay()
                .opacity(Theme.scanlineOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            bloom = true
        }
    }
}

// MARK: - ScanlineOverlay (shared, used by ScanlinePanel too)
struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let lines = Int(geo.size.height / 3)
            VStack(spacing: 2) {
                ForEach(0..<max(lines, 1), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Terminal grid overlay
private struct TerminalGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 60
            var x: CGFloat = 0
            while x <= size.width {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(Theme.darkBorder.opacity(0.09)),
                    lineWidth: 0.5
                )
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(Theme.darkBorder.opacity(0.09)),
                    lineWidth: 0.5
                )
                y += spacing
            }
        }
        .opacity(0.6)
    }
}
