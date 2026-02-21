import Foundation

// MARK: - Task Service
@MainActor
class TaskService: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var isExecutionPaused: Bool = false
    @Published var isLoading: Bool = true
    @Published var lastLoadError: String? = nil

    private let filePath: String
    private let stateFilePath: String
    private var lastTasksFileModificationDate: Date?
    private var lastStateFileModificationDate: Date?
    private var filePollTask: Task<Void, Never>?

    private struct TaskRuntimeState: Codable {
        var isExecutionPaused: Bool
    }

    struct TaskCompactionReport {
        struct MergeGroup {
            let keeperId: UUID
            let mergedIds: [UUID]
            let projectName: String?
            let assignedAgent: String?
            let normalizedKey: String
        }

        let scannedActiveCount: Int
        let mergedTaskCount: Int
        let groups: [MergeGroup]
    }

    init(filePath: String = Constants.tasksFilePath, stateFilePath: String = Constants.tasksStateFilePath) {
        self.filePath = filePath
        self.stateFilePath = stateFilePath
        loadTasks()
        loadRuntimeState()
        refreshKnownFileModificationDates()
        startFilePolling()
    }

    deinit {
        filePollTask?.cancel()
    }

    // MARK: - Persistence

    func loadTasks() {
        isLoading = true
        defer { isLoading = false }
        // IMPORTANT: Never overwrite a user's tasks with sample data.
        // If the file is missing, recover from latest valid backup when possible.
        guard FileManager.default.fileExists(atPath: filePath) else {
            if recoverTasksFromBackupIfPossible() {
                lastLoadError = nil
                return
            }
            tasks = []
            lastTasksFileModificationDate = fileModificationDate(at: filePath)
            lastLoadError = nil
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            tasks = try decoder.decode([TaskItem].self, from: data)
            if enforceSingleInProgressPerAgent() {
                saveTasks()
            }
            lastLoadError = nil
        } catch {
            // Preserve a forensic snapshot of unreadable content, but never
            // remove the primary file path (moving it can look like deletion).
            let suffix = ISO8601DateFormatter().string(from: Date())
            let corruptPath = filePath + ".corrupt-" + suffix + ".json"
            do {
                if !FileManager.default.fileExists(atPath: corruptPath) {
                    try FileManager.default.copyItem(atPath: filePath, toPath: corruptPath)
                    print("[TaskService] Snapshotted unreadable tasks file to: \(corruptPath)")
                }
            } catch {
                print("[TaskService] Failed to snapshot unreadable tasks file: \(error)")
            }

            if recoverTasksFromBackupIfPossible() {
                lastLoadError = nil
                return
            }

            print("[TaskService] Failed to load tasks (no valid backup found, starting empty): \(error)")
            tasks = []
            lastTasksFileModificationDate = fileModificationDate(at: filePath)
            lastLoadError = error.localizedDescription
        }
    }

    func saveTasks() {
        do {
            // Best-effort backup of the prior file (if it exists) to reduce recovery pain.
            if FileManager.default.fileExists(atPath: filePath) {
                let suffix = ISO8601DateFormatter().string(from: Date())
                let backupPath = filePath + ".bak-" + suffix
                // Copy (not move) so the app continues to function if backup fails.
                _ = try? FileManager.default.copyItem(atPath: filePath, toPath: backupPath)
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tasks)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            lastTasksFileModificationDate = fileModificationDate(at: filePath)
        } catch {
            print("[TaskService] Failed to save tasks: \(error)")
        }
    }

    private func loadRuntimeState() {
        guard FileManager.default.fileExists(atPath: stateFilePath) else {
            isExecutionPaused = false
            saveRuntimeState()
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let decoder = JSONDecoder()
            let state = try decoder.decode(TaskRuntimeState.self, from: data)
            isExecutionPaused = state.isExecutionPaused
        } catch {
            isExecutionPaused = false
        }
    }

    private func saveRuntimeState() {
        do {
            let state = TaskRuntimeState(isExecutionPaused: isExecutionPaused)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
            lastStateFileModificationDate = fileModificationDate(at: stateFilePath)
        } catch {
            print("[TaskService] Failed to save runtime state: \(error)")
        }
    }

    private func startFilePolling() {
        filePollTask?.cancel()
        filePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.reloadFromDiskIfNeeded()
            }
        }
    }

    private func reloadFromDiskIfNeeded() {
        let currentTasksMod = fileModificationDate(at: filePath)
        let currentStateMod = fileModificationDate(at: stateFilePath)

        if currentTasksMod != lastTasksFileModificationDate {
            loadTasks()
            lastTasksFileModificationDate = currentTasksMod
        }

        if currentStateMod != lastStateFileModificationDate {
            loadRuntimeState()
            lastStateFileModificationDate = currentStateMod
        }
    }

    private func refreshKnownFileModificationDates() {
        lastTasksFileModificationDate = fileModificationDate(at: filePath)
        lastStateFileModificationDate = fileModificationDate(at: stateFilePath)
    }

    private func fileModificationDate(at path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    /// Attempts to restore tasks from the newest valid backup/corrupt snapshot.
    @discardableResult
    private func recoverTasksFromBackupIfPossible() -> Bool {
        let workspaceDir = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: workspaceDir) else { return false }

        let candidates = entries
            .filter { $0.hasPrefix("tasks.json.bak-") || $0.hasPrefix("tasks.json.corrupt-") }
            .map { "\(workspaceDir)/\($0)" }
            .sorted { lhs, rhs in
                let lDate = fileModificationDate(at: lhs) ?? .distantPast
                let rDate = fileModificationDate(at: rhs) ?? .distantPast
                return lDate > rDate
            }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for candidate in candidates {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: candidate)),
                  let recovered = try? decoder.decode([TaskItem].self, from: data),
                  !recovered.isEmpty else {
                continue
            }
            tasks = recovered
            _ = enforceSingleInProgressPerAgent()
            saveTasks()
            print("[TaskService] Recovered tasks from backup: \(candidate)")
            return true
        }

        return false
    }

    func setExecutionPaused(_ paused: Bool) {
        isExecutionPaused = paused
        saveRuntimeState()
    }

    func toggleExecutionPaused() {
        setExecutionPaused(!isExecutionPaused)
    }

    // MARK: - CRUD

    func createTask(
        title: String,
        description: String? = nil,
        assignedAgent: String? = nil,
        status: TaskStatus = .scheduled,
        priority: TaskPriority = .medium,
        scheduledFor: Date? = nil,
        projectId: String? = nil,
        projectName: String? = nil,
        projectColorHex: String? = nil,
        isVerificationTask: Bool = false,
        verificationRound: Int? = nil,
        isVerified: Bool = false,
        isArchived: Bool = false
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            description: description,
            assignedAgent: assignedAgent,
            status: status,
            priority: priority,
            scheduledFor: scheduledFor,
            projectId: projectId,
            projectName: projectName,
            projectColorHex: projectColorHex,
            isVerificationTask: isVerificationTask,
            verificationRound: verificationRound,
            isVerified: isVerified,
            isArchived: isArchived
        )
        tasks.append(task)
        saveTasks()
        return task
    }

    func updateTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            var updated = task
            updated.updatedAt = Date()
            tasks[index] = updated
            _ = enforceSingleInProgressPerAgent(preferredTaskId: task.id)
            saveTasks()
        }
    }

    func mutateTask(_ taskId: UUID, mutate: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        mutate(&tasks[index])
        tasks[index].updatedAt = Date()
        _ = enforceSingleInProgressPerAgent(preferredTaskId: taskId)
        saveTasks()
    }

    func appendTaskEvidence(_ taskId: UUID, text: String, maxCharacters: Int = 2400) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        mutateTask(taskId) { task in
            let prior = task.lastEvidence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let merged = prior.isEmpty ? cleaned : "\(prior)\n\(cleaned)"
            let clipped = String(merged.suffix(maxCharacters))
            task.lastEvidence = clipped
            task.lastEvidenceAt = Date()
        }
    }

    func deleteTask(_ taskId: UUID) {
        tasks.removeAll { $0.id == taskId }
        saveTasks()
    }

    func moveTask(_ taskId: UUID, to status: TaskStatus) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = status
            tasks[index].updatedAt = Date()
            if status == .done {
                tasks[index].completedAt = Date()
                if tasks[index].isVerificationTask {
                    tasks[index].isVerified = true
                }
            } else {
                tasks[index].completedAt = nil
                if tasks[index].isVerificationTask {
                    tasks[index].isVerified = false
                }
            }
            let preferredTask = status == .inProgress ? taskId : nil
            _ = enforceSingleInProgressPerAgent(preferredTaskId: preferredTask)
            saveTasks()
        }
    }

    func archiveTasks(for projectId: String) {
        var mutated = false
        for idx in tasks.indices {
            if tasks[idx].projectId == projectId, !tasks[idx].isArchived {
                tasks[idx].isArchived = true
                tasks[idx].updatedAt = Date()
                mutated = true
            }
        }
        if mutated {
            saveTasks()
        }
    }

    /// Compacts high-volume queued/ready work by merging duplicate or near-duplicate tasks.
    /// This is intentionally conservative: only non-archived, non-verification tasks in
    /// Ready/Queue are eligible.
    func compactTaskBacklogIfNeeded(minimumActiveTasks: Int = 220, maxMerges: Int = 25) -> TaskCompactionReport? {
        let eligibleIndices = tasks.indices.filter { idx in
            let t = tasks[idx]
            guard !t.isArchived else { return false }
            guard !t.isVerificationTask else { return false }
            return t.status == .scheduled || t.status == .queued
        }
        guard eligibleIndices.count >= minimumActiveTasks else { return nil }

        var mergesRemaining = maxMerges
        var didMutate = false
        var groups: [TaskCompactionReport.MergeGroup] = []

        // Pass 1: strict duplicates by normalized task key (project + agent + canonical title).
        let groupedByKey = Dictionary(grouping: eligibleIndices) { index in
            normalizedCompactionKey(for: tasks[index])
        }

        for (key, indices) in groupedByKey where indices.count > 1 && mergesRemaining > 0 {
            let sorted = indices.sorted(by: preferredTaskIndexComparator)
            guard let keeper = sorted.first else { continue }
            var merged: [UUID] = []
            for idx in sorted.dropFirst() {
                guard mergesRemaining > 0 else { break }
                guard !tasks[idx].isArchived else { continue }
                tasks[idx].isArchived = true
                tasks[idx].updatedAt = Date()
                merged.append(tasks[idx].id)
                mergesRemaining -= 1
                didMutate = true
            }
            if !merged.isEmpty {
                appendMergeEvidence(to: keeper, mergedIds: merged)
                groups.append(
                    .init(
                        keeperId: tasks[keeper].id,
                        mergedIds: merged,
                        projectName: tasks[keeper].projectName,
                        assignedAgent: tasks[keeper].assignedAgent,
                        normalizedKey: key
                    )
                )
            }
        }

        // Pass 2: near-duplicates within same project/agent bucket.
        // Disabled by default to avoid aggressive archival; strict duplicate compaction
        // from pass 1 remains active and much safer.
        let enableNearDuplicateMerge = false
        if enableNearDuplicateMerge && mergesRemaining > 0 {
            let secondaryEligible = tasks.indices.filter { idx in
                let t = tasks[idx]
                guard !t.isArchived else { return false }
                guard !t.isVerificationTask else { return false }
                return t.status == .scheduled || t.status == .queued
            }

            let buckets = Dictionary(grouping: secondaryEligible) { idx in
                let t = tasks[idx]
                return "\(t.projectId ?? "global")|\(normalizedAgent(t.assignedAgent) ?? "unassigned")"
            }

            for (_, bucket) in buckets where bucket.count >= 3 && mergesRemaining > 0 {
                let sorted = bucket.sorted(by: preferredTaskIndexComparator)
                var consumed = Set<Int>()

                for baseIdx in sorted {
                    guard mergesRemaining > 0 else { break }
                    guard !consumed.contains(baseIdx), !tasks[baseIdx].isArchived else { continue }
                    let baseTokens = normalizedTitleTokens(tasks[baseIdx].title)
                    guard !baseTokens.isEmpty else { continue }

                    var merged: [UUID] = []
                    for candidateIdx in sorted {
                        guard mergesRemaining > 0 else { break }
                        guard candidateIdx != baseIdx else { continue }
                        guard !consumed.contains(candidateIdx), !tasks[candidateIdx].isArchived else { continue }
                        let candidateTokens = normalizedTitleTokens(tasks[candidateIdx].title)
                        guard !candidateTokens.isEmpty else { continue }
                        let similarity = jaccardSimilarity(baseTokens, candidateTokens)
                        guard similarity >= 0.82 else { continue }

                        tasks[candidateIdx].isArchived = true
                        tasks[candidateIdx].updatedAt = Date()
                        consumed.insert(candidateIdx)
                        merged.append(tasks[candidateIdx].id)
                        mergesRemaining -= 1
                        didMutate = true
                    }

                    if !merged.isEmpty {
                        consumed.insert(baseIdx)
                        appendMergeEvidence(to: baseIdx, mergedIds: merged)
                        groups.append(
                            .init(
                                keeperId: tasks[baseIdx].id,
                                mergedIds: merged,
                                projectName: tasks[baseIdx].projectName,
                                assignedAgent: tasks[baseIdx].assignedAgent,
                                normalizedKey: normalizedCompactionKey(for: tasks[baseIdx])
                            )
                        )
                    }
                }
            }
        }

        guard didMutate else { return nil }
        saveTasks()
        return TaskCompactionReport(
            scannedActiveCount: eligibleIndices.count,
            mergedTaskCount: groups.reduce(0) { $0 + $1.mergedIds.count },
            groups: groups
        )
    }

    func tasksForStatus(_ status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status && !$0.isArchived }
            .sorted {
                if status == .done {
                    let lhsVerified = $0.isVerificationTask && $0.isVerified
                    let rhsVerified = $1.isVerificationTask && $1.isVerified
                    if lhsVerified != rhsVerified { return lhsVerified && !rhsVerified }
                }
                let lhsPriority = Self.priorityRank($0.priority)
                let rhsPriority = Self.priorityRank($1.priority)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.createdAt > $1.createdAt
            }
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    private func preferredTaskIndexComparator(_ lhs: Int, _ rhs: Int) -> Bool {
        let left = tasks[lhs]
        let right = tasks[rhs]
        let lPriority = Self.priorityRank(left.priority)
        let rPriority = Self.priorityRank(right.priority)
        if lPriority != rPriority { return lPriority < rPriority }
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        return left.createdAt > right.createdAt
    }

    @discardableResult
    private func enforceSingleInProgressPerAgent(preferredTaskId: UUID? = nil) -> Bool {
        var didMutate = false
        let grouped = Dictionary(grouping: tasks.indices.filter { tasks[$0].status == .inProgress && !tasks[$0].isArchived }) { index in
            normalizedAgent(tasks[index].assignedAgent)
        }

        for (agent, indices) in grouped {
            guard agent != nil, indices.count > 1 else { continue }

            let keepIndex: Int
            if let preferredTaskId,
               let matched = indices.first(where: { tasks[$0].id == preferredTaskId }) {
                keepIndex = matched
            } else {
                keepIndex = indices.max(by: { lhs, rhs in
                    if tasks[lhs].updatedAt != tasks[rhs].updatedAt {
                        return tasks[lhs].updatedAt < tasks[rhs].updatedAt
                    }
                    let lPriority = Self.priorityRank(tasks[lhs].priority)
                    let rPriority = Self.priorityRank(tasks[rhs].priority)
                    if lPriority != rPriority {
                        return lPriority > rPriority
                    }
                    return tasks[lhs].createdAt < tasks[rhs].createdAt
                }) ?? indices[0]
            }

            for index in indices where index != keepIndex {
                tasks[index].status = .queued
                tasks[index].updatedAt = Date()
                tasks[index].completedAt = nil
                if tasks[index].isVerificationTask {
                    tasks[index].isVerified = false
                }
                didMutate = true
            }
        }

        return didMutate
    }

    private func normalizedAgent(_ value: String?) -> String? {
        guard let value else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? nil : token
    }

    private func normalizedCompactionKey(for task: TaskItem) -> String {
        let project = task.projectId ?? "global"
        let agent = normalizedAgent(task.assignedAgent) ?? "unassigned"
        let titleTokens = normalizedTitleTokens(task.title).sorted().joined(separator: " ")
        return "\(project)|\(agent)|\(titleTokens)"
    }

    private func normalizedTitleTokens(_ text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "a", "an", "to", "for", "and", "of", "in", "on", "with", "by",
            "task", "fix", "update", "create", "implement", "review", "check"
        ]
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = cleaned.split(separator: " ").map(String.init)
        return Set(tokens.filter { $0.count >= 3 && !stopWords.contains($0) })
    }

    private func jaccardSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private func appendMergeEvidence(to keeperIndex: Int, mergedIds: [UUID]) {
        guard tasks.indices.contains(keeperIndex) else { return }
        let note = "Compacted duplicate/related tasks: \(mergedIds.map { $0.uuidString }.joined(separator: ", "))"
        let prior = tasks[keeperIndex].lastEvidence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let merged = prior.isEmpty ? note : "\(prior)\n\(note)"
        tasks[keeperIndex].lastEvidence = String(merged.suffix(2400))
        tasks[keeperIndex].lastEvidenceAt = Date()
        tasks[keeperIndex].updatedAt = Date()
    }

    // MARK: - Sample Data

    static let sampleTasks: [TaskItem] = [
        TaskItem(title: "Initialize Scope agent", description: "Set up planning agent with acceptance criteria templates", assignedAgent: "Jarvis", status: .scheduled, priority: .high),
        TaskItem(title: "Initialize Atlas agent", description: "Configure research agent with knowledge base access", assignedAgent: "Jarvis", status: .scheduled, priority: .high),
        TaskItem(title: "Refactor auth middleware", description: "Clean up token validation and add rate limiting", assignedAgent: "Matrix", status: .queued, priority: .medium),
        TaskItem(title: "Security audit: API endpoints", description: "Review all public endpoints for auth bypass vulnerabilities", assignedAgent: "Prism", status: .inProgress, priority: .urgent),
        TaskItem(title: "Update README docs", description: "Reflect new agent architecture in documentation", assignedAgent: "Atlas", status: .queued, priority: .low),
        TaskItem(title: "Fix Slack message threading", description: "Thread replies not appearing in correct channel", assignedAgent: "Matrix", status: .done, priority: .medium, completedAt: Date().addingTimeInterval(-3600)),
    ]
}
