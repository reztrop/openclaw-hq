import SwiftUI

struct ConnectionBanner: View {
    @EnvironmentObject var gatewayService: GatewayService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Delays showing the connecting spinner so transient states don't flash the UI
    @State private var showConnecting = false
    @State private var connectingTask: Task<Void, Never>? = nil

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
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(Theme.jarvisBlue)
            Text("Connecting to gateway…")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.darkAccent)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private func disconnectedBanner(message: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundColor(Theme.statusOffline)
            Text(message ?? "Disconnected from gateway")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button("Reconnect") {
                gatewayService.connect()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.jarvisBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.darkAccent)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }
}
