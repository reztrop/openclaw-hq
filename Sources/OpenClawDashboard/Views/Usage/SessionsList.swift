import SwiftUI

struct SessionsList: View {
    let sessions: [Session]

    var body: some View {
        VStack(spacing: 0) {
            // Header row with .terminalLabel()
            HStack {
                Text("AGENT")
                    .terminalLabel()
                    .frame(width: 100, alignment: .leading)
                Text("MODEL")
                    .terminalLabel()
                    .frame(width: 200, alignment: .leading)
                Text("TOKENS")
                    .terminalLabel()
                    .frame(width: 100, alignment: .trailing)
                Text("DATE")
                    .terminalLabel()
                    .frame(width: 120, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Theme.neonCyan.opacity(0.2))
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(50).enumerated()), id: \.offset) { index, session in
                        sessionRow(session, isEven: index % 2 == 0)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func sessionRow(_ session: Session, isEven: Bool) -> some View {
        let name = session.agentId == "main" ? "Jarvis" : (session.agentId?.capitalized ?? "—")
        return HStack {
            // Agent "@name" in brand color
            HStack(spacing: 6) {
                AgentAvatarSmall(agentName: name, size: 18)
                Text("@\(name.lowercased())")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Theme.agentColor(for: name))
            }
            .frame(width: 100, alignment: .leading)

            // Model
            Text(session.model ?? "—")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            // Tokens
            Text(session.totalTokens.compactTokens)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 100, alignment: .trailing)

            // Date in textMetadata
            Text(session.updatedAt?.relativeString ?? "—")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMetadata)
                .frame(width: 120, alignment: .trailing)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isEven ? Theme.darkSurface : Theme.neonCyan.opacity(0.02))
    }
}
