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

    enum DeleteStep {
        case warning
        case authenticating
        case failed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textMuted)
            }
            .padding(16)
            .background(Theme.darkSurface)

            Divider().opacity(0.3)

            // Content
            VStack(spacing: 24) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                }

                VStack(spacing: 8) {
                    Text("Delete \(agent.name)?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("This is permanent and cannot be undone. All agent files, sessions, and configuration will be permanently removed from your system.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: 360)
                }

                // Auth error
                if let err = authError {
                    Label(err, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 10) {
                    Button(action: { Task { await authenticate() } }) {
                        if isAuthenticating {
                            HStack { ProgressView(); Text("Verifying…") }
                                .frame(maxWidth: 280)
                        } else {
                            Label("Delete Agent", systemImage: "trash")
                                .frame(maxWidth: 280)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isAuthenticating || agent.isDefaultAgent)
                    .controlSize(.large)

                    if agent.isDefaultAgent {
                        Text("The main agent cannot be deleted.")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    } else {
                        Text("You'll be asked to confirm your identity with Touch ID or password.")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                    }

                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 40)
        }
        .background(Theme.darkBackground)
        .frame(width: 460, height: 380)
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
