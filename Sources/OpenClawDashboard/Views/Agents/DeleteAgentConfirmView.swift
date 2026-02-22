import SwiftUI
import LocalAuthentication

struct DeleteAgentConfirmView: View {
    let agent: Agent
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel

    @State private var step: DeleteStep = .warning
    @State private var isAuthenticating = false
    @State private var authError: String?

    // Pulsing neon-red ring animation state
    @State private var ringPulse = false

    enum DeleteStep {
        case warning
        case authenticating
        case failed
    }

    var body: some View {
        HQModalChrome {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Button("CANCEL") { dismiss() }
                        .buttonStyle(.plain)
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(16)
                .background(Theme.darkSurface)

                Rectangle()
                    .fill(Theme.statusOffline.opacity(0.4))
                    .frame(height: 1)
                    .shadow(color: Theme.statusOffline.opacity(0.3), radius: 4, x: 0, y: 0)

                // Content
                VStack(spacing: 24) {
                    Spacer()

                    // Pulsing neon-red ring icon
                    ZStack {
                        // Outer pulsing ring
                        Circle()
                            .stroke(
                                Theme.statusOffline.opacity(ringPulse ? 0.15 : 0.05),
                                lineWidth: ringPulse ? 18 : 10
                            )
                            .frame(width: ringPulse ? 110 : 90, height: ringPulse ? 110 : 90)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: ringPulse
                            )

                        // Mid ring
                        Circle()
                            .stroke(
                                Theme.statusOffline.opacity(ringPulse ? 0.55 : 0.25),
                                lineWidth: 2
                            )
                            .frame(width: 80, height: 80)
                            .shadow(
                                color: Theme.statusOffline.opacity(ringPulse ? 0.8 : 0.3),
                                radius: ringPulse ? 12 : 4, x: 0, y: 0
                            )
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: ringPulse
                            )

                        // Fill circle
                        Circle()
                            .fill(Theme.statusOffline.opacity(0.15))
                            .frame(width: 72, height: 72)

                        Image(systemName: "trash.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.statusOffline)
                            .shadow(color: Theme.statusOffline.opacity(0.8), radius: 6, x: 0, y: 0)
                    }
                    .onAppear {
                        ringPulse = true
                    }

                    VStack(spacing: 8) {
                        // CONFIRM_DELETE: label with agent name in red monospaced
                        VStack(spacing: 4) {
                            Text("CONFIRM_DELETE:")
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.textMuted)

                            Text(agent.name.uppercased())
                                .font(.system(.title2, design: .monospaced, weight: .bold))
                                .foregroundColor(Theme.statusOffline)
                                .shadow(color: Theme.statusOffline.opacity(0.5), radius: 6, x: 0, y: 0)
                        }

                        Text("This is permanent and cannot be undone. All agent files, sessions, and configuration will be permanently removed from your system.")
                            .font(Theme.terminalFont)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: 360)
                    }

                    // Auth error
                    if let err = authError {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.statusOffline)
                            Text(err)
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.statusOffline)
                        }
                        .padding(10)
                        .background(Theme.statusOffline.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.statusOffline.opacity(0.3), lineWidth: 1)
                        )
                        .frame(maxWidth: 360)
                        .multilineTextAlignment(.center)
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: 10) {
                        Button(action: { Task { await authenticate() } }) {
                            if isAuthenticating {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Theme.textPrimary)
                                        .controlSize(.small)
                                    Text("VERIFYING...")
                                        .font(Theme.terminalFont)
                                }
                                .frame(maxWidth: 280)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("DELETE_AGENT")
                                        .font(Theme.terminalFont)
                                }
                                .frame(maxWidth: 280)
                            }
                        }
                        .buttonStyle(HQButtonStyle(variant: .danger))
                        .disabled(isAuthenticating || agent.isDefaultAgent)
                        .controlSize(.large)

                        if agent.isDefaultAgent {
                            Text("The main agent cannot be deleted.")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                        } else {
                            Text("You'll be asked to confirm your identity with Touch ID or password.")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                                .multilineTextAlignment(.center)
                        }

                        Button("CANCEL") { dismiss() }
                            .buttonStyle(.plain)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 40)
            }
            .frame(width: 460, height: 420)
        }
        .preferredColorScheme(.dark)
    }

    private func authenticate() async {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = error?.localizedDescription ?? "Authentication not available on this device."
            return
        }

        let reason = "Confirm your identity to delete the agent '\(agent.name)'."

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                onConfirm()
                dismiss()
            } else {
                authError = "Authentication failed. Agent was not deleted."
            }
        } catch {
            let laError = error as? LAError
            switch laError?.code {
            case .userCancel, .appCancel:
                // User cancelled — silently ignore
                break
            case .biometryNotEnrolled:
                authError = "No biometrics enrolled. Please set up Touch ID or a login password."
            default:
                authError = error.localizedDescription
            }
        }
    }
}
