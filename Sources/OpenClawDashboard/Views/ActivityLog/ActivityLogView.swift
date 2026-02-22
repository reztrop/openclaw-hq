import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject var activityLogVM: ActivityLogViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var isLiveBlink = false

    private let blinkTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("[")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan.opacity(0.6))
                    Text("ACTIVITY_FEED")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan)
                    Text("]")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundColor(Theme.neonCyan.opacity(0.6))
                }

                // Blinking [LIVE] badge when events are being added
                if !activityLogVM.events.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.statusOnline)
                            .frame(width: 6, height: 6)
                            .opacity(isLiveBlink ? 1 : 0.2)
                        Text("[LIVE]")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.statusOnline)
                    }
                    .onReceive(blinkTimer) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLiveBlink.toggle()
                        }
                    }
                }

                Spacer()

                if !activityLogVM.events.isEmpty {
                    Button {
                        activityLogVM.clearEvents()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("CLEAR_LOG")
                        }
                    }
                    .buttonStyle(HQButtonStyle(variant: .danger))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Filter bar — "[TYPE]" square-bracket monospaced
            filterBar
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // Terminal-style search: "FILTER:" prefix
            HStack(spacing: 8) {
                Text("FILTER:")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
                    .tracking(1)
                    .fixedSize()
                TextField("", text: $activityLogVM.searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.terminalFont)
                    .foregroundColor(Theme.textPrimary)
                    .focused($isSearchFocused)
                    .tint(Theme.neonCyan)
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
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSearchFocused ? Theme.neonCyan.opacity(0.6) : Theme.darkBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Theme.neonCyan.opacity(0.15))
                .frame(height: 1)

            // Event list
            if activityLogVM.filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(activityLogVM.filteredEvents.enumerated()), id: \.offset) { index, event in
                            eventRow(event, isEven: index % 2 == 0)
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
                filterPill(label: "ALL", type: nil)
                ForEach(ActivityEventType.allCases, id: \.self) { type in
                    filterPill(label: type.rawValue.uppercased(), type: type)
                }
            }
        }
    }

    private func filterPill(label: String, type: ActivityEventType?) -> some View {
        let isSelected = activityLogVM.filter == type
        let pillColor = type?.color ?? Theme.neonCyan
        return Button {
            activityLogVM.filter = type
        } label: {
            Text("[\(label)]")
                .font(Theme.terminalFontSM)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Theme.darkBackground : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? pillColor : Theme.darkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? pillColor : Theme.darkBorder.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Event Row

    private func eventRow(_ event: ActivityEvent, isEven: Bool) -> some View {
        HStack(spacing: 12) {
            // Timestamp
            Text(event.timestamp.relativeString)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMetadata)
                .frame(width: 60, alignment: .leading)

            // Agent avatar
            AgentAvatarSmall(agentName: event.agentName, size: 22)

            // Event type icon
            Image(systemName: event.eventType.icon)
                .font(.caption)
                .foregroundColor(event.eventType.color)
                .frame(width: 18)

            // "@agent ▸ event_type" format
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("@\(event.agentName.lowercased())")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundColor(Theme.agentColor(for: event.agentName))
                    Text("▸")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                    Text(event.eventType.rawValue.lowercased())
                        .font(Theme.terminalFontSM)
                        .foregroundColor(event.eventType.color)
                }
                Text(event.message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                if let details = event.details {
                    Text(details)
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        // Alternating 2% row tint instead of dividers
        .background(isEven ? Color.clear : Theme.neonCyan.opacity(0.02))
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
