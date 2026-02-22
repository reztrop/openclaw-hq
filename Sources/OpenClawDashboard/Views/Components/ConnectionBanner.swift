import SwiftUI

struct ConnectionBanner: View {
    @EnvironmentObject var gatewayService: GatewayService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showConnecting = false
    @State private var connectingTask: Task<Void, Never>? = nil
    @State private var scanOffset: CGFloat = -300

    var body: some View {
        Group {
            switch gatewayService.connectionState {
            case .connected:
                EmptyView()

            case .connecting:
                if showConnecting {
                    connectingBanner
                } else {
                    EmptyView()
                }

            case .disconnected(let message):
                disconnectedBanner(message: message)
            }
        }
        .onChange(of: gatewayService.connectionState) { _, newState in
            switch newState {
            case .connecting:
                connectingTask?.cancel()
                connectingTask = Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    if !Task.isCancelled {
                        if reduceMotion {
                            showConnecting = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) { showConnecting = true }
                        }
                    }
                }
            case .connected, .disconnected:
                connectingTask?.cancel()
                connectingTask = nil
                if reduceMotion {
                    showConnecting = false
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { showConnecting = false }
                }
            }
        }
        .onAppear {
            if case .connecting = gatewayService.connectionState {
                connectingTask = Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    if !Task.isCancelled {
                        if reduceMotion {
                            showConnecting = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) { showConnecting = true }
                        }
                    }
                }
            }
        }
    }

    private var connectingBanner: some View {
        ZStack(alignment: .leading) {
            // Terminal alert bar background
            Theme.darkAccent

            // Scanning-line animation: bright rect sliding left-to-right
            if !reduceMotion {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Theme.neonCyan.opacity(0.18), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 120)
                        .offset(x: scanOffset)
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.8)
                                .repeatForever(autoreverses: false)
                            ) {
                                scanOffset = geo.size.width + 120
                            }
                        }
                }
            }

            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.neonCyan)

                Text("GATEWAY_CONNECTING...")
                    .font(Theme.terminalFont)
                    .foregroundColor(Theme.glitchAmber)
                    .tracking(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 36)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.glitchAmber.opacity(0.3))
                .frame(height: 1)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private func disconnectedBanner(message: String?) -> some View {
        HStack(spacing: 10) {
            Text("⚠")
                .font(Theme.terminalFont)
                .foregroundColor(Theme.glitchAmber)

            Text("GATEWAY_OFFLINE — ATTEMPTING RECONNECT...")
                .font(Theme.terminalFont)
                .foregroundColor(Theme.glitchAmber)
                .tracking(1)

            if let message = message, !message.isEmpty {
                Text("[\(message)]")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button {
                gatewayService.connect()
            } label: {
                Text("RECONNECT")
                    .font(Theme.terminalFontSM)
            }
            .buttonStyle(HQButtonStyle(variant: .secondary))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.glitchAmber.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.glitchAmber.opacity(0.35))
                .frame(height: 1)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }
}
