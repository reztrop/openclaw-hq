import SwiftUI

struct HQModalBackdrop: View {
    var body: some View {
        ZStack {
            CyberpunkBackdrop()
            Color.black.opacity(0.55)
        }
        .ignoresSafeArea()
    }
}

struct HQModalChrome<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    @ViewBuilder private let content: Content

    init(cornerRadius: CGFloat = 18, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        ZStack {
            HQModalBackdrop()

            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.darkSurface.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Theme.neonCyan.opacity(0.35), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Theme.neonCyan.opacity(0.16), radius: reduceMotion ? 0 : 28, x: 0, y: 16)
                .shadow(color: Theme.neonMagenta.opacity(0.12), radius: reduceMotion ? 0 : 48, x: 0, y: 24)
                .padding(padding)
        }
    }
}
