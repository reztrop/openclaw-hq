import SwiftUI

struct SkillsView: View {
    @EnvironmentObject var skillsViewModel: SkillsViewModel
    @State private var searchText = ""
    @State private var showSyntheticModal = false
    @FocusState private var isSearchFocused: Bool

    private var shouldShowSyntheticModal: Bool {
        ProcessInfo.processInfo.arguments.contains("--nexus-synthetic-modal")
    }

    private var filteredSkills: [SkillInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skillsViewModel.skills }
        return skillsViewModel.skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query) ||
            skill.description.localizedCaseInsensitiveContains(query) ||
            skill.agentsWithAccess.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ConnectionBanner()
                header
                skillsCard
            }
            .padding(24)
        }
        .background(Theme.darkBackground)
        .task {
            await skillsViewModel.refreshSkills()
        }
        .onAppear {
            if shouldShowSyntheticModal {
                showSyntheticModal = true
            }
        }
        .sheet(isPresented: $showSyntheticModal) {
            syntheticModal
        }
    }

    private var syntheticModal: some View {
        HQModalChrome {
            VStack(alignment: .leading, spacing: 12) {
                Text("// NEXUS_SYNTHETIC_MODAL")
                    .terminalLabel()

                Text("Fixture-only modal state for screenshot capture. Launch with --nexus-synthetic-modal.")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textSecondary)

                HStack {
                    Spacer()
                    HQButton(variant: .glow) {
                        showSyntheticModal = false
                    } label: {
                        Label("DISMISS", systemImage: "xmark.circle")
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
        .presentationDetents([.medium])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // "[ SKILL_MATRIX ]" + count
            HStack(spacing: 4) {
                Text("[")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
                Text("SKILL_MATRIX")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.neonCyan)
                    .glitchText()
                Text("]")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
                Text("·\(skillsViewModel.skills.count)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
            }
            Text("Enabled skills available to your agents.")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skillsCard: some View {
        HQPanel(cornerRadius: 12, surface: Theme.darkSurface, border: Theme.darkBorder) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    // Terminal-style search: dark background, "SEARCH:" prefix, neon cursor
                    HStack(spacing: 8) {
                        Text("SEARCH:")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                            .tracking(1)
                        TextField("", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textPrimary)
                            .focused($isSearchFocused)
                            .tint(Theme.neonCyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.darkBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSearchFocused ? Theme.neonCyan.opacity(0.7) : Theme.darkBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HQButton(variant: .secondary) {
                        Task { await skillsViewModel.refreshSkills() }
                    } label: {
                        Label("REFRESH", systemImage: "arrow.clockwise")
                    }
                }

                HStack {
                    Text("\(filteredSkills.count)_SKILLS_SHOWN")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    if skillsViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.neonCyan)
                    }
                }

                if let error = skillsViewModel.errorMessage {
                    HStack(spacing: 6) {
                        Text("ERR:")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.statusOffline)
                        Text(error)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.statusOffline)
                    }
                }

                if filteredSkills.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "No enabled skills found",
                        subtitle: "Enable a skill to see it listed here.",
                        maxWidth: .infinity,
                        iconSize: 24,
                        contentPadding: 16,
                        showPanel: true
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSkills) { skill in
                            skillRow(skill)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func skillRow(_ skill: SkillInfo) -> some View {
        HQPanel(cornerRadius: 10, surface: Theme.darkAccent.opacity(0.45), border: Theme.darkBorder.opacity(0.8)) {
            HStack(alignment: .top, spacing: 12) {
                // Emoji in neon-bordered square
                NeonBorderPanel(color: Theme.neonCyan, cornerRadius: 6, surface: Theme.neonCyan.opacity(0.06), lineWidth: 1) {
                    Text(skill.emoji)
                        .font(.title2)
                        .frame(width: 38, height: 38)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Monospaced skill name
                        Text(skill.name)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        // "[ACTIVE]" badge in terminalGreen monospaced
                        Text("[ACTIVE]")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.statusOnline)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.statusOnline.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.statusOnline.opacity(0.4), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        HQBadge(text: skill.source, tone: .neutral)
                        Spacer()
                    }

                    Text(skill.description)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !skill.agentsWithAccess.isEmpty {
                        HStack(spacing: 6) {
                            Text("AGENTS:")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                            ForEach(skill.agentsWithAccess, id: \.self) { agent in
                                // "@agent" badge in brand color
                                Text("@\(agent.lowercased())")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(Theme.agentColor(for: agent))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.agentColor(for: agent).opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}
