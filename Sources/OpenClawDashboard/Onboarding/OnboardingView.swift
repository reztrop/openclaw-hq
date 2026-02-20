import SwiftUI

struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background
            Theme.darkBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                if vm.step != .welcome && vm.step != .done {
                    progressDots
                        .padding(.top, 32)
                }

                // Step content
                Group {
                    switch vm.step {
                    case .welcome:
                        WelcomeStep(vm: vm)
                    case .connection:
                        ConnectionStep(vm: vm)
                    case .agentDiscovery:
                        AgentDiscoveryStep(vm: vm)
                    case .avatarSetup:
                        AvatarSetupStep(vm: vm)
                    case .done:
                        DoneStep(vm: vm) {
                            Task {
                                await vm.completeOnboarding(settingsService: appViewModel.settingsService)
                                appViewModel.onboardingCompleted()
                            }
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(vm.step)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .preferredColorScheme(.dark)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            // Steps 1–3 shown as dots (welcome and done excluded)
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(vm.step.rawValue >= i ? Theme.jarvisBlue : Theme.darkBorder)
                    .frame(width: 8, height: 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.step)
            }
        }
    }
}

// MARK: - Welcome Step
struct WelcomeStep: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.jarvisBlue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                Text("OpenClaw HQ")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Agent Dashboard")
                    .font(.title3)
                    .foregroundColor(Theme.textSecondary)
            }

            VStack(spacing: 12) {
                Text("This app connects to your OpenClaw gateway to help you monitor and manage your AI agents.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary)

                Text("⚠️  This app does not install OpenClaw. You'll need OpenClaw installed and running before continuing.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Link("Don't have OpenClaw? Visit openclaw.com", destination: URL(string: "https://openclaw.com")!)
                    .font(.caption)
                    .foregroundColor(Theme.jarvisBlue)
            }
            .frame(maxWidth: 480)

            Spacer()

            Button(action: { vm.goNext() }) {
                Label("Get Started", systemImage: "arrow.right")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.jarvisBlue)
            .padding(.bottom, 48)
        }
        .padding(40)
    }
}

// MARK: - Connection Step
struct ConnectionStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var showTokenHelp = false
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 8) {
                    Text("Connect to Gateway")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Tell us where your OpenClaw gateway is running")
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 24)

                // Mode picker
                Picker("Mode", selection: $vm.connectionMode) {
                    Text("Local (This Mac)").tag(ConnectionMode.local)
                    Text("Remote / Manual").tag(ConnectionMode.remote)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                // Local mode
                if vm.connectionMode == .local {
                    localModeSection
                } else {
                    remoteModeSection
                }

                // Test connection
                testConnectionSection

                Spacer(minLength: 16)

                // Navigation
                HStack {
                    Button("Back") { vm.goBack() }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.textMuted)

                    Spacer()

                    Button("Continue →") {
                        Task { await vm.discoverAgents() }
                        vm.goNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.jarvisBlue)
                    .disabled(!vm.testStatus.isSuccess)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 48)
            .frame(maxWidth: 560)
        }
    }

    private var localModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if vm.tokenFoundInConfig {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Token found in your OpenClaw config ✓")
                        .foregroundColor(.green)
                        .font(.callout)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No token found in ~/.openclaw/openclaw.json")
                        .foregroundColor(.orange)
                        .font(.callout)

                    if let err = vm.generateTokenError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button(action: { Task { await vm.generateToken() } }) {
                        if vm.generatingToken {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Label("Generate Token Automatically", systemImage: "wand.and.rays")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.generatingToken)

                    Text("This will run: openclaw doctor --generate-gateway-token --non-interactive --yes")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .monospaced()
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Token override field (always visible in local mode)
            if !vm.token.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Token").font(.caption).foregroundColor(Theme.textMuted)
                    SecureField("Gateway token", text: $vm.token)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Advanced disclosure
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("Host", text: $vm.host, placeholder: "127.0.0.1")
                    labeledField("Port", text: $vm.port, placeholder: "18789")
                }
                .padding(.top, 8)
            }
            .foregroundColor(Theme.textMuted)
        }
    }

    private var remoteModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledField("Host", text: $vm.host, placeholder: "192.168.1.x or example.com")
            labeledField("Port", text: $vm.port, placeholder: "18789")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Token").font(.caption).foregroundColor(Theme.textMuted)
                    Button(action: { showTokenHelp.toggle() }) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showTokenHelp) {
                        tokenHelpPopover
                    }
                }
                SecureField("Gateway operator token", text: $vm.token)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var testConnectionSection: some View {
        VStack(spacing: 10) {
            Button(action: {
                Task { await vm.testConnection() }
            }) {
                HStack(spacing: 8) {
                    if vm.testStatus.isTesting {
                        ProgressView().scaleEffect(0.7)
                        Text("Testing…")
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Test Connection")
                    }
                }
                .frame(maxWidth: 200)
            }
            .buttonStyle(.bordered)
            .disabled(vm.token.isEmpty || vm.testStatus.isTesting)

            switch vm.testStatus {
            case .idle:
                EmptyView()
            case .testing:
                EmptyView()
            case .success:
                Label("Connected successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.callout)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tokenHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to get a token")
                .font(.headline)
                .foregroundColor(.white)
            Text("Ask your OpenClaw agent: 'Generate a gateway operator token for me.'")
                .foregroundColor(Theme.textSecondary)
                .font(.callout)
            Divider()
            Text("Or run this on the machine with OpenClaw:")
                .foregroundColor(Theme.textSecondary)
                .font(.callout)
            Text("openclaw doctor --generate-gateway-token\n  --non-interactive --yes")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.jarvisBlue)
            Text("Then find the token in:\n~/.openclaw/openclaw.json → gateway.auth.token")
                .foregroundColor(Theme.textMuted)
                .font(.caption)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.darkSurface)
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(Theme.textMuted)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Agent Discovery Step
struct AgentDiscoveryStep: View {
    @ObservedObject var vm: OnboardingViewModel

    private let commonEmojis = ["🤖", "🧠", "🔍", "🧩", "📐", "🗺️", "⚡", "🎯", "🚀", "💡", "🔮", "🌟"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Your Agents")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Select an agent, edit details, then save")
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 24)

                if vm.isLoadingAgents {
                    ProgressView("Discovering agents…")
                        .tint(Theme.jarvisBlue)
                        .foregroundColor(Theme.textSecondary)
                } else if let err = vm.agentDiscoveryError {
                    VStack(spacing: 8) {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Button("Retry") { Task { await vm.discoverAgents() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(vm.discoveredAgents) { agent in
                            agentRow(agent)
                        }
                    }
                    .frame(maxWidth: 460)

                    if vm.selectedEditableAgentId != nil {
                        Divider().opacity(0.3)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Edit selected agent")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Name").font(.caption).foregroundColor(Theme.textMuted)
                                    TextField("Agent name", text: $vm.editableAgentName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Emoji").font(.caption).foregroundColor(Theme.textMuted)
                                    TextField("Emoji", text: $vm.editableAgentEmoji)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 64)
                                }
                            }

                            LazyVGrid(columns: Array(repeating: .init(.fixed(36)), count: 12), spacing: 4) {
                                ForEach(commonEmojis, id: \.self) { e in
                                    Button(e) { vm.editableAgentEmoji = e }
                                        .font(.title3)
                                        .frame(width: 32, height: 32)
                                        .background(vm.editableAgentEmoji == e ? Theme.jarvisBlue.opacity(0.3) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .buttonStyle(.plain)
                                }
                            }

                            Toggle(isOn: $vm.editableAgentCanCommunicateWithAgents) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow Agent-to-Agent Collaboration")
                                        .foregroundColor(.white)
                                    Text("When enabled, this agent may coordinate with other agents via Jarvis.")
                                        .font(.caption)
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                            .toggleStyle(.switch)

                            HStack {
                                Button("Save Agent Changes") {
                                    vm.saveSelectedAgentEdits()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.jarvisBlue)

                                if let notice = vm.agentSaveNotice {
                                    Label(notice, systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .frame(maxWidth: 460)
                        .padding(16)
                        .background(Theme.darkSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                HStack {
                    Button("Back") { vm.goBack() }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Button("Skip for now") { vm.goNext() }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.textMuted)
                    Button("Continue →") { vm.goNext() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.jarvisBlue)
                }
                .frame(maxWidth: 460)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 48)
        }
        .task { await vm.discoverAgents() }
    }

    private func agentRow(_ agent: Agent) -> some View {
        Button {
            vm.selectAgentForEditing(agentId: agent.id)
        } label: {
            HStack(spacing: 12) {
                Text(vm.effectiveEmoji(for: agent)).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vm.effectiveName(for: agent))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        if agent.isDefaultAgent {
                            Text("MAIN")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.jarvisBlue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.jarvisBlue.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Text(agent.id)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .monospaced()
                }
                Spacer()
                Image(systemName: vm.selectedEditableAgentId == agent.id ? "pencil.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(vm.selectedEditableAgentId == agent.id ? Theme.jarvisBlue : .green)
            }
            .padding(12)
            .background(vm.selectedEditableAgentId == agent.id ? Theme.darkAccent : Theme.darkSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avatar Setup Step
struct AvatarSetupStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var showActiveFilePicker = false
    @State private var showIdleFilePicker = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Agent Avatars")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Add avatar images for \(vm.agentName.isEmpty ? "your main agent" : vm.agentName) (optional)")
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            HStack(spacing: 32) {
                avatarPicker(
                    label: "Active (Working)",
                    path: vm.activeImagePath,
                    onPick: { vm.activeImagePath = $0 },
                    color: .green
                )

                avatarPicker(
                    label: "Idle / Offline",
                    path: vm.idleImagePath,
                    onPick: { vm.idleImagePath = $0 },
                    color: .red
                )
            }
            .frame(maxWidth: 440)

            Text("No avatars? No problem — the app will show a coloured gradient with the agent's initial.")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Spacer()

            HStack {
                Button("Back") { vm.goBack() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Button("Skip — I'll add these later") { vm.goNext() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textMuted)
                Button("Continue →") { vm.goNext() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.jarvisBlue)
            }
            .frame(maxWidth: 440)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 48)
    }

    private func avatarPicker(label: String, path: String?, onPick: @escaping (String) -> Void, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textMuted)

            Button(action: {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    onPick(url.path)
                }
            }) {
                ZStack {
                    if let p = path, let img = NSImage(contentsOfFile: p) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 120, height: 120)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                        .font(.title2)
                                        .foregroundColor(color)
                                    Text("Choose")
                                        .font(.caption)
                                        .foregroundColor(Theme.textMuted)
                                }
                            )
                    }
                }
            }
            .buttonStyle(.plain)

            if path != nil {
                Button("Remove") {
                    if label.contains("Active") { vm.activeImagePath = nil }
                    else { vm.idleImagePath = nil }
                }
                .font(.caption)
                .foregroundColor(.red)
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Done Step
struct DoneStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
                .symbolEffect(.bounce, value: !reduceMotion)

            VStack(spacing: 12) {
                Text("You're all set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                VStack(spacing: 6) {
                    Label("Connected to gateway", systemImage: "antenna.radiowaves.left.and.right")
                    Label("\(vm.discoveredAgents.count) agent\(vm.discoveredAgents.count == 1 ? "" : "s") found", systemImage: "cpu")
                    if !vm.agentName.isEmpty {
                        Label("\(vm.agentEmoji) \(vm.agentName) ready", systemImage: "checkmark")
                    }
                }
                .font(.callout)
                .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button(action: onComplete) {
                Label("Open Dashboard", systemImage: "arrow.right")
                    .font(.headline)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.jarvisBlue)
            .padding(.bottom, 48)
        }
        .padding(40)
    }
}
