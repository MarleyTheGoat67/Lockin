import Foundation
import Combine

/// The single source of truth for the UI. Always used on the main thread.
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var blocks: [FocusBlock] = []
    @Published private(set) var atRisk: Set<UUID> = []
    /// The block that is running right now, if any.
    @Published private(set) var activeBlockID: UUID?
    @Published var settings: PlannerSettings = PlannerSettings() {
        didSet {
            if settings != oldValue && !isLoading { commit() }
        }
    }

    private var isLoading = false

    private init() {
        isLoading = true
        let data = Persistence.load()
        tasks = data.tasks
        blocks = data.blocks
        settings = data.settings
        isLoading = false
        commit()
    }

    // MARK: - Lookups

    func task(_ id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    func block(_ id: UUID) -> FocusBlock? {
        blocks.first { $0.id == id }
    }

    func title(for block: FocusBlock) -> String {
        task(block.taskID)?.title ?? "Deleted task"
    }

    var activeBlock: FocusBlock? {
        FocusGuard.activeBlock(in: blocks, at: Date())
    }

    var activeTasks: [TaskItem] {
        tasks.filter { !$0.isDone }.sorted { $0.deadline < $1.deadline }
    }

    var doneTasks: [TaskItem] {
        tasks.filter { $0.isDone }.sorted { ($0.doneAt ?? $0.createdAt) > ($1.doneAt ?? $1.createdAt) }
    }

    /// Total focus minutes still to do across all open tasks.
    var totalRemainingMinutes: Int {
        tasks.reduce(0) { $0 + $1.remainingMinutes }
    }

    /// Planned blocks that have not ended yet, soonest first.
    func upcomingBlocks(from now: Date = Date()) -> [FocusBlock] {
        blocks.filter { $0.status == .planned && $0.end > now }.sorted { $0.start < $1.start }
    }

    /// Blocks whose time has passed and that the user has not confirmed yet.
    func blocksAwaitingCheckIn(at now: Date = Date()) -> [FocusBlock] {
        blocks.filter { $0.awaitsCheckIn(at: now) && task($0.taskID) != nil }.sorted { $0.start < $1.start }
    }

    /// Open tasks whose planned time is used up: finished, or more time needed?
    func tasksNeedingDecision(at now: Date = Date()) -> [TaskItem] {
        tasks.filter { task in
            guard !task.isDone, task.remainingMinutes == 0 else { return false }
            return !blocks.contains { $0.taskID == task.id && $0.status == .planned }
        }
    }

    /// Everything on a given day that should show on the calendar.
    func blocks(on day: Date, calendar: Calendar = .current) -> [FocusBlock] {
        blocks
            .filter { $0.status == .planned || $0.status == .completed }
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    func plannedMinutes(on day: Date, calendar: Calendar = .current) -> Int {
        blocks(on: day, calendar: calendar).reduce(0) { $0 + $1.minutes }
    }

    func completedMinutes(on day: Date, calendar: Calendar = .current) -> Int {
        blocks
            .filter { $0.status == .completed && calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.minutes }
    }

    // MARK: - Stats

    /// Days in a row (ending today or yesterday) with at least one completed block.
    var streakDays: Int {
        let calendar = Calendar.current
        let daysWithWork = Set(blocks.filter { $0.status == .completed }.map { calendar.startOfDay(for: $0.start) })
        var day = calendar.startOfDay(for: Date())
        if !daysWithWork.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while daysWithWork.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    func completedMinutes(lastDays days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 86_400))
        return blocks.filter { $0.status == .completed && $0.start >= cutoff }.reduce(0) { $0 + $1.minutes }
    }

    func completedSessions(lastDays days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 86_400))
        return blocks.filter { $0.status == .completed && $0.start >= cutoff }.count
    }

    // MARK: - Tasks

    func addTask(_ task: TaskItem) {
        tasks.append(task)
        commit()
    }

    func updateTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        commit()
    }

    func deleteTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        blocks.removeAll { $0.taskID == id && $0.status == .planned }
        commit()
    }

    func setDone(_ id: UUID, done: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        if done {
            // Credit a session that is running right now.
            if let running = blocks.firstIndex(where: { $0.taskID == id && $0.isActive(at: now) }) {
                finish(blockAt: running, at: now)
            }
        }
        tasks[index].isDone = done
        tasks[index].doneAt = done ? now : nil
        commit()
    }

    func addTime(_ id: UUID, minutes: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks[index]
        // Make sure at least `minutes` are open again, whatever the buffer was.
        let needed = task.completedMinutes + minutes
        let estimate = Int((Double(needed) / task.difficulty.bufferMultiplier).rounded(.up))
        tasks[index].estimatedMinutes = max(task.estimatedMinutes + 5, estimate)
        commit()
    }

    // MARK: - Blocks

    /// Start a focus session for a task right now.
    func startNow(_ taskID: UUID) {
        guard let task = task(taskID), !task.isDone else { return }
        let now = Date()
        if let running = blocks.firstIndex(where: { $0.isActive(at: now) }) {
            if blocks[running].taskID == taskID { return }
            finish(blockAt: running, at: now)
        }
        let wanted = task.remainingMinutes > 0 ? min(task.remainingMinutes, settings.sessionMinutes) : settings.sessionMinutes
        let length = max(wanted, 10)
        blocks.append(FocusBlock(
            taskID: taskID,
            start: now,
            end: now.addingTimeInterval(TimeInterval(length * 60)),
            isPinned: true
        ))
        commit()
    }

    /// Pull a planned block forward so it starts now.
    func startBlockNow(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].status == .planned else { return }
        let now = Date()
        if blocks[index].isActive(at: now) { return }
        if let running = blocks.firstIndex(where: { $0.isActive(at: now) }) {
            finish(blockAt: running, at: now)
        }
        let length = blocks[index].minutes
        blocks[index].start = now
        blocks[index].end = now.addingTimeInterval(TimeInterval(length * 60))
        blocks[index].isPinned = true
        commit()
    }

    /// "Not now": frees the block and plans the time somewhere else.
    func skip(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].status == .planned else { return }
        blocks[index].status = .skipped
        commit()
    }

    func move(_ id: UUID, to newStart: Date) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].status == .planned else { return }
        let length = blocks[index].minutes
        blocks[index].start = newStart
        blocks[index].end = newStart.addingTimeInterval(TimeInterval(length * 60))
        blocks[index].isPinned = true
        blocks[index].isLate = false
        commit()
    }

    /// Answer "did you work?" for a block whose time has passed.
    func checkIn(_ id: UUID, worked: Bool) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].status == .planned else { return }
        if worked {
            blocks[index].status = .completed
            credit(blocks[index].taskID, minutes: blocks[index].minutes)
        } else {
            blocks[index].status = .missed
        }
        commit()
    }

    /// Stop the running session and count the minutes worked so far.
    func endEarly(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].status == .planned else { return }
        finish(blockAt: index, at: Date())
        commit()
    }

    /// Forget all manual moves and plan everything again from scratch.
    func replanEverything() {
        let now = Date()
        blocks.removeAll { $0.status == .planned && $0.start > now }
        blocks.removeAll { $0.status == .skipped && $0.end > now }
        commit()
    }

    func eraseEverything() {
        tasks = []
        blocks = []
        commit()
    }

    // MARK: - Time passing

    /// Called every few seconds while the app is open.
    func tick() {
        let current = activeBlock?.id
        if current != activeBlockID {
            activeBlockID = current
        }
    }

    /// Called when the app comes to the foreground.
    func refresh() {
        commit()
    }

    func handleNotificationAction(_ action: String, blockID: UUID?) {
        guard let blockID = blockID else { return }
        if action == NotificationManager.workedAction {
            checkIn(blockID, worked: true)
        } else if action == NotificationManager.missedAction {
            checkIn(blockID, worked: false)
        }
    }

    // MARK: - Internals

    private func credit(_ taskID: UUID, minutes: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].completedMinutes += minutes
    }

    private func finish(blockAt index: Int, at now: Date) {
        guard blocks[index].status == .planned else { return }
        if now < blocks[index].end {
            blocks[index].end = max(now, blocks[index].start.addingTimeInterval(60))
        }
        blocks[index].status = .completed
        credit(blocks[index].taskID, minutes: blocks[index].minutes)
    }

    /// Re-plan, save and re-schedule notifications after any change.
    private func commit() {
        let now = Date()
        let historyCutoff = now.addingTimeInterval(-120 * 86_400)
        let current = blocks.filter { $0.end >= historyCutoff }

        let result = Scheduler.plan(tasks: tasks, existing: current, settings: settings, now: now)
        blocks = result.blocks
        atRisk = result.atRisk
        activeBlockID = FocusGuard.activeBlock(in: blocks, at: now)?.id

        Persistence.save(AppData(tasks: tasks, blocks: blocks, settings: settings))
        NotificationManager.sync(tasks: tasks, blocks: blocks, settings: settings, now: now)
    }
}
