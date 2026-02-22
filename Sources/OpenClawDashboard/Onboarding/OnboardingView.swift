import SwiftUI

struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Boot sequence state
    @State private var showingBoot = true
    @State private var bootLines: [String] = []
    @State private var bootComplete = false

    private let allBootLines = [
        "INITIALIZING OPENCLAW HQ...",
        "LOADING AGENT PROFILES...",
        "ESTABLISHING NEURAL LINK...",
        "CALIBRATING NEXUS MATRIX...",
        "BOOT SEQUENCE COMPLETE."
    ]

    var body: some View {
        ZStack {
            Theme.darkBackground.ignoresSafeArea()

            if showingBoot {
                bootSequenceView
                    .transition(reduceMotion ? .opacity : .opacity)
            } else {
                mainOnboarding
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity,
                        removal: .opacity
                    ))
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .preferredColorScheme(.dark)
        .onAppear {
            startBootSequence()
        }
    }

    // MARK: - Boot Sequence View

    private var bootSequenceView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bootLines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 8) {
                        Text(">")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .foregroundColor(Theme.neonCyan.opacity(0.7))
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(line == "BOOT SEQUENCE COMPLETE." ? Theme.statusOnline : Theme.terminalGreen)
                    }
                    .transition(.opacity)
                }

                if bootLines.count == allBootLines.count {
                    HStack(spacing: 8) {
                        Text(">")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .foregroundColor(Theme.neonCyan.opacity(0.7))
                        BlinkingCursor()
                    }
                }
            }
            .padding(40)

            Spacer()

            HStack {
                Spacer()
                Button("SKIP") {
                    finishBoot()
                }
                .buttonStyle(HQButtonStyle(variant: .secondary))
                .padding(24)
            }
        }
    }

    // MARK: - Main Onboarding

    private var mainOnboarding: some View {
        VStack(spacing: 0) {
            if vm.step != .welcome && vm.step != .done {
                progressIndicator
                    .padding(.top, 32)
            }

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

    // MARK: - Progress Indicator "[■■□□□] STEP N OF N"

    private var progressIndicator: some View {
        let totalSteps = 3
        let currentStep = max(1, min(vm.step.rawValue, totalSteps))

        return HStack(spacing: 6) {
            Text("[")
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(Theme.neonCyan.opacity(0.5))
            ForEach(1...totalSteps, id: \.self) { i in
                Text(i <= currentStep ? "■" : "□")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(i <= currentStep ? Theme.neonCyan : Theme.darkBorder)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentStep)
            }
            Text("] STEP \(currentStep) OF \(totalSteps)")
                .font(Theme.terminalFont)
                .foregroundColor(Theme.textMuted)
        }
    }

    // MARK: - Boot Sequence Logic

    private func startBootSequence() {
        guard !reduceMotion else {
            // Instant complete if reduce motion is on
            finishBoot()
            return
        }

        for (index, line) in allBootLines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.4) {
                withAnimation(.easeIn(duration: 0.2)) {
                    bootLines.append(line)
                }
            }
        }

        // After 2.5s total, transition to welcome
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            finishBoot()
        }
    }

    private func finishBoot() {
        guard showingBoot else { return }
        if reduceMotion {
            showingBoot = false
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                showingBoot = false
            }
        }
    }
}

// MARK: - Blinking Cursor

private struct BlinkingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(visible || reduceMotion ? "█" : " ")
            .font(.system(.body, design: .monospaced))
            .foregroundColor(Theme.neonCyan)
            .onReceive(timer) { _ in
                guard !reduceMotion else { return }
                visible.toggle()
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
                        colors: [Theme.neonCyan, Theme.scopePurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Theme.neonCyan.opacity(0.4), radius: 20)

            VStack(spacing: 12) {
                Text("OPENCLAW_HQ")
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan)
                    .glitchText()

                Text("AGENT_DASHBOARD")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }

            VStack(spacing: 12) {
                Text("This app connects to your OpenClaw gateway to help you monitor and manage your AI agents.")
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary)

                NeonBorderPanel(color: Theme.glitchAmber, cornerRadius: 8, surface: Theme.glitchAmber.opacity(0.06), lineWidth: 1) {
                    HStack(spacing: 8) {
                        Text("⚠")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.glitchAmber)
                        Text("This app does not install OpenClaw. You'll need OpenClaw installed and running before continuing.")
                            .font(Theme.terminalFontSM)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.glitchAmber.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Link("Don't have OpenClaw? Visit openclaw.com", destination: URL(string: "https://openclaw.com")!)
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.neonCyan)
            }
            .frame(maxWidth: 480)

            Spacer()

            Button(action: { vm.goNext() }) {
                HStack(spacing: 8) {
                    Text("INITIALIZE")
                    Image(systemName: "arrow.right")
                }
                .font(.system(.headline, design: .monospaced))
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
            }
            .buttonStyle(HQButtonStyle(variant: .glow))
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
    @FocusState private var focusedField: OnboardingField?

    enum OnboardingField: Hashable {
        case host, port, token
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("// CONNECT_TO_GATEWAY")
                        .terminalLabel()
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("Tell us where your OpenClaw gateway is running")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 24)

                // Mode picker
                Picker("Mode", selection: $vm.connectionMode) {
                    Text("LOCAL (THIS MAC)").tag(ConnectionMode.local)
                    Text("REMOTE / MANUAL").tag(ConnectionMode.remote)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                if vm.connectionMode == .local {
                    localModeSection
                } else {
                    remoteModeSection
                }

                testConnectionSection

                Spacer(minLength: 16)

                HStack {
                    Button("BACK") { vm.goBack() }
                        .buttonStyle(HQButtonStyle(variant: .secondary))

                    Spacer()

                    Button("CONTINUE →") {
                        Task { await vm.discoverAgents() }
                        vm.goNext()
                    }
                    .buttonStyle(HQButtonStyle(variant: .glow))
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
                NeonBorderPanel(color: Theme.statusOnline, cornerRadius: 8, surface: Theme.statusOnline.opacity(0.06), lineWidth: 1) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.statusOnline)
                        Text("TOKEN_FOUND_IN_CONFIG")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.statusOnline)
                    }
                    .padding(12)
                }
            } else {
                NeonBorderPanel(color: Theme.glitchAmber, cornerRadius: 8, surface: Theme.glitchAmber.opacity(0.06), lineWidth: 1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NO TOKEN FOUND IN ~/.openclaw/openclaw.json")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.glitchAmber)

                        if let err = vm.generateTokenError {
                            Text("ERR: \(err)")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.statusOffline)
                        }

                        Button(action: { Task { await vm.generateToken() } }) {
                            if vm.generatingToken {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Label("GENERATE_TOKEN_AUTO", systemImage: "wand.and.rays")
                            }
                        }
                        .buttonStyle(HQButtonStyle(variant: .secondary))
                        .disabled(vm.generatingToken)

                        Text("$ openclaw doctor --generate-gateway-token --non-interactive --yes")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(12)
                }
            }

            if !vm.token.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOKEN")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .tracking(1.2)
                    SecureField("Gateway token", text: $vm.token)
                        .textFieldStyle(.plain)
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textPrimary)
                        .cyberpunkInput(isFocused: focusedField == .token)
                        .focused($focusedField, equals: .token)
                }
            }

            DisclosureGroup("ADVANCED", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    onboardingLabeledField("HOST", binding: $vm.host, placeholder: "127.0.0.1", field: .host, focused: $focusedField)
                    onboardingLabeledField("PORT", binding: $vm.port, placeholder: "18789", field: .port, focused: $focusedField)
                }
                .padding(.top, 8)
            }
            .font(Theme.terminalFont)
            .foregroundColor(Theme.textMuted)
        }
    }

    private var remoteModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            onboardingLabeledField("HOST", binding: $vm.host, placeholder: "192.168.1.x or example.com", field: .host, focused: $focusedField)
            onboardingLabeledField("PORT", binding: $vm.port, placeholder: "18789", field: .port, focused: $focusedField)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TOKEN")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .tracking(1.2)
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
                    .textFieldStyle(.plain)
                    .font(Theme.terminalFont)
                    .foregroundColor(Theme.textPrimary)
                    .cyberpunkInput(isFocused: focusedField == .token)
                    .focused($focusedField, equals: .token)
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
                        ProgressView().scaleEffect(0.7).tint(Theme.neonCyan)
                        Text("TESTING...")
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("TEST_CONNECTION")
                    }
                }
                .font(Theme.terminalFont)
                .frame(maxWidth: 240)
            }
            .buttonStyle(HQButtonStyle(variant: .secondary))
            .disabled(vm.token.isEmpty || vm.testStatus.isTesting)

            // Terminal output style for results
            switch vm.testStatus {
            case .idle:
                EmptyView()
            case .testing:
                EmptyView()
            case .success:
                HStack(spacing: 6) {
                    Text("$")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.statusOnline)
                    Text("ping gateway... OK — connected successfully")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.statusOnline)
                }
            case .failed(let msg):
                HStack(spacing: 6) {
                    Text("$")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.statusOffline)
                    Text("ERR: \(msg)")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.statusOffline)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tokenHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("// HOW_TO_GET_TOKEN")
                .terminalLabel()
            Text("Ask your OpenClaw agent: 'Generate a gateway operator token for me.'")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textSecondary)
            Divider().background(Theme.darkBorder)
            Text("Or run this on the machine with OpenClaw:")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textSecondary)
            Text("$ openclaw doctor --generate-gateway-token\n  --non-interactive --yes")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.neonCyan)
            Text("Then find the token in:\n~/.openclaw/openclaw.json → gateway.auth.token")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.darkSurface)
    }

    private func onboardingLabeledField(_ label: String, binding: Binding<String>, placeholder: String, field: OnboardingField, focused: FocusState<OnboardingField?>.Binding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(Theme.terminalFont)
                .foregroundColor(Theme.textPrimary)
                .cyberpunkInput(isFocused: focused.wrappedValue == field)
                .focused(focused, equals: field)
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
                    Text("// YOUR_AGENTS")
                        .terminalLabel()
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("Select an agent, edit details, then save")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 24)

                if vm.isLoadingAgents {
                    ProgressView("DISCOVERING_AGENTS...")
                        .tint(Theme.neonCyan)
                        .foregroundColor(Theme.textSecondary)
                        .font(Theme.terminalFont)
                } else if let err = vm.agentDiscoveryError {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text("ERR:")
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.statusOffline)
                            Text(err)
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.statusOffline)
                        }
                        Button("RETRY") { Task { await vm.discoverAgents() } }
                            .buttonStyle(HQButtonStyle(variant: .secondary))
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(vm.discoveredAgents) { agent in
                            agentRow(agent)
                        }
                    }
                    .frame(maxWidth: 460)

                    if vm.selectedEditableAgentId != nil {
                        Rectangle()
                            .fill(Theme.neonCyan.opacity(0.2))
                            .frame(height: 1)
                            .frame(maxWidth: 460)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("// EDIT_SELECTED_AGENT")
                                .terminalLabel()

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NAME")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                        .tracking(1.2)
                                    TextField("AGENT_NAME", text: $vm.editableAgentName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(Theme.terminalFont)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("EMOJI")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                        .tracking(1.2)
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
                                        .background(vm.editableAgentEmoji == e ? Theme.neonCyan.opacity(0.2) : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(vm.editableAgentEmoji == e ? Theme.neonCyan.opacity(0.6) : Color.clear, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .buttonStyle(.plain)
                                }
                            }

                            Toggle(isOn: $vm.editableAgentCanCommunicateWithAgents) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ALLOW_AGENT_COLLABORATION")
                                        .font(Theme.terminalFont)
                                        .foregroundColor(Theme.textPrimary)
                                    Text("When enabled, this agent may coordinate with other agents via Jarvis.")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(Theme.neonCyan)

                            HStack {
                                Button("SAVE_AGENT_CHANGES") {
                                    vm.saveSelectedAgentEdits()
                                }
                                .buttonStyle(HQButtonStyle(variant: .glow))

                                if let notice = vm.agentSaveNotice {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text(notice.uppercased())
                                    }
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.statusOnline)
                                }
                            }
                        }
                        .frame(maxWidth: 460)
                        .padding(16)
                        .background(Theme.darkSurface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.neonCyan.opacity(0.2), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                HStack {
                    Button("BACK") { vm.goBack() }
                        .buttonStyle(HQButtonStyle(variant: .secondary))
                    Spacer()
                    Button("SKIP") { vm.goNext() }
                        .buttonStyle(HQButtonStyle(variant: .secondary))
                    Button("CONTINUE →") { vm.goNext() }
                        .buttonStyle(HQButtonStyle(variant: .glow))
                }
                .frame(maxWidth: 460)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 48)
        }
        .task { await vm.discoverAgents() }
    }

    private func agentRow(_ agent: Agent) -> some View {
        let isSelected = vm.selectedEditableAgentId == agent.id
        return Button {
            vm.selectAgentForEditing(agentId: agent.id)
        } label: {
            HStack(spacing: 12) {
                Text(vm.effectiveEmoji(for: agent)).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vm.effectiveName(for: agent).uppercased())
                            .font(Theme.terminalFont)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? Theme.neonCyan : Theme.textPrimary)
                        if agent.isDefaultAgent {
                            Text("[MAIN]")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.neonCyan)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.neonCyan.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.neonCyan.opacity(0.4), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(agent.id)
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                Image(systemName: isSelected ? "pencil.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(isSelected ? Theme.neonCyan : Theme.statusOnline)
            }
            .padding(12)
            .background(isSelected ? Theme.neonCyan.opacity(0.07) : Theme.darkSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.neonCyan.opacity(0.6) : Theme.darkBorder.opacity(0.5), lineWidth: 1)
            )
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
                Text("// AVATAR_SETUP")
                    .terminalLabel()
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Add avatar images for \(vm.agentName.isEmpty ? "your main agent" : vm.agentName) (optional)")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            HStack(spacing: 32) {
                avatarPicker(
                    label: "ACTIVE_STATE",
                    path: vm.activeImagePath,
                    onPick: { vm.activeImagePath = $0 },
                    color: Theme.statusOnline
                )

                avatarPicker(
                    label: "IDLE_STATE",
                    path: vm.idleImagePath,
                    onPick: { vm.idleImagePath = $0 },
                    color: Theme.statusOffline
                )
            }
            .frame(maxWidth: 440)

            Text("// No avatars? The app will show a colored gradient with the agent's initial.")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Spacer()

            HStack {
                Button("BACK") { vm.goBack() }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                Spacer()
                Button("SKIP") { vm.goNext() }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                Button("CONTINUE →") { vm.goNext() }
                    .buttonStyle(HQButtonStyle(variant: .glow))
            }
            .frame(maxWidth: 440)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 48)
    }

    private func avatarPicker(label: String, path: String?, onPick: @escaping (String) -> Void, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)

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
                        NeonBorderPanel(color: color, cornerRadius: 60, surface: color.opacity(0.07), lineWidth: 1.5) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .foregroundColor(color)
                                Text("SELECT")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(color.opacity(0.7))
                            }
                            .frame(width: 120, height: 120)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if path != nil {
                Button("REMOVE") {
                    if label.contains("ACTIVE") { vm.activeImagePath = nil }
                    else { vm.idleImagePath = nil }
                }
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.statusOffline)
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

            // "[ SYSTEM READY ]" neon-bordered framed text
            NeonBorderPanel(color: Theme.statusOnline, cornerRadius: 10, surface: Theme.statusOnline.opacity(0.06), lineWidth: 1.5) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.statusOnline)
                    Text("[ SYSTEM READY ]")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.statusOnline)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(Theme.statusOnline)
                .symbolEffect(.bounce, value: !reduceMotion)
                .shadow(color: Theme.statusOnline.opacity(0.4), radius: 20)

            VStack(spacing: 12) {
                Text("YOU'RE ALL SET!")
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan)
                    .glitchText()

                // Terminal output style for completion status
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("$")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                        Label("Gateway connected", systemImage: "antenna.radiowaves.left.and.right")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                    HStack(spacing: 8) {
                        Text("$")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                        Label("\(vm.discoveredAgents.count) agent\(vm.discoveredAgents.count == 1 ? "" : "s") discovered", systemImage: "cpu")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                    if !vm.agentName.isEmpty {
                        HStack(spacing: 8) {
                            Text("$")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                            Label("\(vm.agentEmoji) \(vm.agentName) ready", systemImage: "checkmark")
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.statusOnline)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onComplete) {
                HStack(spacing: 8) {
                    Text("OPEN_DASHBOARD")
                    Image(systemName: "arrow.right")
                }
                .font(.system(.headline, design: .monospaced))
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
            }
            .buttonStyle(HQButtonStyle(variant: .glow))
            .padding(.bottom, 48)
        }
        .padding(40)
    }
}
