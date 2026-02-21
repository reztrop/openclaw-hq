import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject var activityLogVM: ActivityLogViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Log")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if !activityLogVM.events.isEmpty {
                    Button("Clear") {
                        activityLogVM.clearEvents()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.textMuted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Filter bar
            filterBar
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textMuted)
                TextField("Search events...", text: $activityLogVM.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                if !activityLogVM.searchText.isEmpty {
                    Button {
                        activityLogVM.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Theme.darkSurface)
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider().background(Theme.darkBorder)

            // Event list
            if activityLogVM.filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activityLogVM.filteredEvents) { event in
                            eventRow(event)
                            Divider().background(Theme.darkBorder)
                        }
                    }
                }
            }
        }
        .background(Theme.darkBackground)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", type: nil)
                ForEach(ActivityEventType.allCases, id: \.self) { type in
                    filterPill(label: type.rawValue, type: type)
                }
            }
        }
    }

    private func filterPill(label: String, type: ActivityEventType?) -> some View {
        let isSelected = activityLogVM.filter == type
        return Button {
            activityLogVM.filter = type
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? (type?.color ?? Theme.jarvisBlue) : Theme.darkSurface)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Event Row

    private func eventRow(_ event: ActivityEvent) -> some View {
        HStack(spacing: 12) {
            // Timestamp
            Text(event.timestamp.relativeString)
                .font(.caption2)
                .foregroundColor(Theme.textMuted)
                .frame(width: 60, alignment: .leading)

            // Agent avatar
            AgentAvatarSmall(agentName: event.agentName, size: 24)

            // Event type badge
            Image(systemName: event.eventType.icon)
                .font(.caption)
                .foregroundColor(event.eventType.color)
                .frame(width: 20)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let details = event.details {
                    Text(details)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "text.bubble",
            title: "No events yet",
            subtitle: "Activity from agents and the gateway will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
