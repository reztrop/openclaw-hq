import SwiftUI

struct SessionsList: View {
    let sessions: [Session]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agent")
                    .frame(width: 100, alignment: .leading)
                Text("Model")
                    .frame(width: 200, alignment: .leading)
                Text("Tokens")
                    .frame(width: 100, alignment: .trailing)
                Text("Date")
                    .frame(width: 120, alignment: .trailing)
                Spacer()
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Theme.darkBorder)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessions.prefix(50)) { session in
                        sessionRow(session)
                        Divider().background(Theme.darkBorder.opacity(0.3))
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack {
            // Agent
            HStack(spacing: 6) {
                let name = session.agentId == "main" ? "Jarvis" : (session.agentId?.capitalized ?? "—")
                AgentAvatarSmall(agentName: name, size: 20)
                Text(name)
                    .font(.caption)
                    .foregroundColor(Theme.agentColor(for: name))
            }
            .frame(width: 100, alignment: .leading)

            // Model
            Text(session.model ?? "—")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            // Tokens
            Text(session.totalTokens.compactTokens)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(width: 100, alignment: .trailing)

            // Date
            Text(session.updatedAt?.relativeString ?? "—")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .frame(width: 120, alignment: .trailing)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.darkSurface)
    }
}
