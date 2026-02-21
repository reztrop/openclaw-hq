import SwiftUI

struct SkillsView: View {
    @EnvironmentObject var skillsViewModel: SkillsViewModel
    @State private var searchText = ""

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skills")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Text("Enabled skills available to your agents.")
                .foregroundColor(Theme.textMuted)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skillsCard: some View {
        HQPanel(cornerRadius: 12, surface: Theme.darkSurface, border: Theme.darkBorder) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.textMuted)
                        TextField("Search skills", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.darkAccent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.darkBorder, lineWidth: 1)
                    )
                    .cornerRadius(8)

                    HQButton(variant: .primary) {
                        Task { await skillsViewModel.refreshSkills() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                HStack {
                    Text("\(filteredSkills.count) shown")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    if skillsViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = skillsViewModel.errorMessage {
                    Text(error)
                        .foregroundColor(Theme.statusOffline)
                        .font(.caption)
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
                Text(skill.emoji)
                    .font(.title2)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(skill.name)
                            .font(.headline)
                            .foregroundColor(.white)
                        HQBadge(text: "enabled", tone: .success)
                        HQBadge(text: skill.source, tone: .neutral)
                        Spacer()
                    }

                    Text(skill.description)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !skill.agentsWithAccess.isEmpty {
                        HStack(spacing: 6) {
                            Text("Agents:")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                            ForEach(skill.agentsWithAccess, id: \.self) { agent in
                                HQBadge(text: agent.capitalized, color: Theme.agentColor(for: agent))
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}
