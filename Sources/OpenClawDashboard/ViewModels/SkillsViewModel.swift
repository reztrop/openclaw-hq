import Foundation
import Dispatch

@MainActor
final class SkillsViewModel: ObservableObject {
    enum SyntheticState: String {
        case none
        case loading
        case empty
        case error

        static func fromLaunchArguments() -> SyntheticState {
            let prefix = "--nexus-synthetic-state="
            guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
                return .none
            }
            let value = String(arg.dropFirst(prefix.count)).lowercased()
            return SyntheticState(rawValue: value) ?? .none
        }
    }

    @Published private(set) var skills: [SkillInfo] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchFD: CInt = -1
    private let openclawExecutablePath: String?
    private let syntheticState: SyntheticState

    init() {
        openclawExecutablePath = Self.resolveOpenClawExecutablePath()
        syntheticState = SyntheticState.fromLaunchArguments()

        guard syntheticState == .none else {
            applySyntheticState(syntheticState)
            return
        }

        startPolling()
        startSkillsDirectoryWatch()
        refreshTask = Task { [weak self] in
            await self?.refreshSkills()
        }
    }

    deinit {
        pollingTask?.cancel()
        refreshTask?.cancel()
        watchSource?.cancel()
        if watchFD >= 0 {
            close(watchFD)
            watchFD = -1
        }
    }

    func refreshSkills() async {
        if syntheticState != .none {
            applySyntheticState(syntheticState)
            return
        }

        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let rawSkills = try await fetchSkillsFromCLI()
            let enabledSkills = rawSkills.filter {
                $0.eligible && !$0.disabled && !$0.blockedByAllowlist
            }

            let sortedEnabled = enabledSkills.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            let agents = try await fetchAgentsFromCLI()
            let accessBySkill = await loadAgentSkillAccess(
                agents: agents.map(\.id),
                enabledSkillNames: Set(sortedEnabled.map(\.name))
            )

            let allAgentIds = agents.map(\.id)
            skills = sortedEnabled.map { raw in
                let access = accessBySkill[raw.name] ?? allAgentIds
                return SkillInfo(
                    name: raw.name,
                    description: raw.description,
                    emoji: raw.emoji ?? "🧩",
                    source: raw.source,
                    homepage: raw.homepage,
                    agentsWithAccess: access.sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                )
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load skills: \(error.localizedDescription)"
        }
    }

    private func applySyntheticState(_ state: SyntheticState) {
        switch state {
        case .none:
            break
        case .loading:
            skills = []
            errorMessage = nil
            isLoading = true
            lastUpdated = nil
        case .empty:
            skills = []
            errorMessage = nil
            isLoading = false
            lastUpdated = Date()
        case .error:
            skills = []
            errorMessage = "Synthetic Nexus error: failed to resolve skills registry (fixture)."
            isLoading = false
            lastUpdated = Date()
        }
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.refreshSkills()
            }
        }
    }

    private func startSkillsDirectoryWatch() {
        let path = Constants.managedSkillsDirectory
        guard FileManager.default.fileExists(atPath: path) else { return }

        watchFD = open(path, O_EVTONLY)
        guard watchFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchFD,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.refreshSkills()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.watchFD >= 0 {
                close(self.watchFD)
                self.watchFD = -1
            }
        }
        watchSource = source
        source.resume()
    }

    private func fetchSkillsFromCLI() async throws -> [RawSkill] {
        let json = try await runOpenClawAndDecodeJSON(arguments: ["skills", "list", "--json"])
        return try decodeArray([RawSkill].self, from: json, key: "skills")
    }

    private func fetchAgentsFromCLI() async throws -> [RawAgent] {
        let json = try await runOpenClawAndDecodeJSON(arguments: ["agents", "list", "--json"])
        return try decodeArray([RawAgent].self, from: json, key: nil)
    }

    private func loadAgentSkillAccess(
        agents: [String],
        enabledSkillNames: Set<String>
    ) async -> [String: [String]] {
        var result: [String: [String]] = [:]
        for agentId in agents {
            let path = "\(Constants.agentStateDirectory)/\(agentId)/sessions/sessions.json"
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            let names = extractSkillNames(from: json).filter { enabledSkillNames.contains($0) }
            for name in names {
                result[name, default: []].append(agentId)
            }
        }
        return result
    }

    private func extractSkillNames(from json: Any) -> Set<String> {
        var found: Set<String> = []

        if let dict = json as? [String: Any] {
            if let snapshot = dict["skillsSnapshot"] as? [String: Any],
               let skills = snapshot["skills"] as? [[String: Any]] {
                for skill in skills {
                    if let name = skill["name"] as? String, !name.isEmpty {
                        found.insert(name)
                    }
                }
            }
            for value in dict.values {
                let nested = extractSkillNames(from: value)
                found.formUnion(nested)
            }
        } else if let arr = json as? [Any] {
            for item in arr {
                let nested = extractSkillNames(from: item)
                found.formUnion(nested)
            }
        }

        return found
    }

    private func runOpenClawAndDecodeJSON(arguments: [String]) async throws -> Any {
        guard let executable = openclawExecutablePath else {
            throw NSError(
                domain: "OpenClawHQ.Skills",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenClaw CLI not found. Install it or ensure it exists at /opt/homebrew/bin/openclaw or /usr/local/bin/openclaw."]
            )
        }

        let data = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = Self.openClawProcessEnvironment()

            // macOS app bundles have a stripped PATH that excludes Homebrew.
            // openclaw.mjs uses `#!/usr/bin/env node`, so we must ensure node
            // is findable by injecting the full shell PATH.
            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            let currentPath = env["PATH"] ?? ""
            let pathComponents = currentPath.split(separator: ":").map(String.init)
            let merged = extraPaths.filter { !pathComponents.contains($0) } + pathComponents
            env["PATH"] = merged.joined(separator: ":")
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let stderrString = String(data: errorOutput, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown CLI error"
                throw NSError(
                    domain: "OpenClawHQ.Skills",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: stderrString]
                )
            }
            return output
        }.value

        guard !data.isEmpty else {
            throw NSError(
                domain: "OpenClawHQ.Skills",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenClaw returned no JSON output."]
            )
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    private func decodeArray<T: Decodable>(_ type: T.Type, from json: Any, key: String?) throws -> T {
        let target: Any
        if let key, let dict = json as? [String: Any], let value = dict[key] {
            target = value
        } else {
            target = json
        }
        let data = try JSONSerialization.data(withJSONObject: target)
        return try JSONDecoder().decode(type, from: data)
    }

    nonisolated private static func resolveOpenClawExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/usr/bin/openclaw"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    nonisolated private static func openClawProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let required = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = env["PATH"] ?? ""
        let currentParts = current.split(separator: ":").map(String.init)
        var merged = required
        for part in currentParts where !merged.contains(part) {
            merged.append(part)
        }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }
}

private struct RawSkill: Decodable {
    let name: String
    let description: String
    let emoji: String?
    let eligible: Bool
    let disabled: Bool
    let blockedByAllowlist: Bool
    let source: String
    let homepage: String?
}

private struct RawAgent: Decodable {
    let id: String
}
