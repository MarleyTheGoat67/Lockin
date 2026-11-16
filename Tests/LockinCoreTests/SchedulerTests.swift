import XCTest
@testable import LockinCore

final class SchedulerTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// Monday 2026-11-16.
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func plan(_ tasks: [TaskItem], existing: [FocusBlock] = [], settings: PlannerSettings = PlannerSettings(), now: Date) -> PlanResult {
        Scheduler.plan(tasks: tasks, existing: existing, settings: settings, now: now, calendar: calendar)
    }

    func assertValid(_ result: PlanResult, settings: PlannerSettings, now: Date, file: StaticString = #filePath, line: UInt = #line) {
        let planned = result.blocks.filter { $0.status == .planned && $0.end > now }.sorted { $0.start < $1.start }
        for block in planned where !block.isPinned && block.start > now {
            let weekday = calendar.component(.weekday, from: block.start)
            let window = settings.window(forWeekday: weekday)
            let dayStart = calendar.startOfDay(for: block.start)
            let startMinute = Int(block.start.timeIntervalSince(dayStart) / 60)
            let endMinute = Int(block.end.timeIntervalSince(dayStart) / 60)
            XCTAssertTrue(window.enabled, "block on a disabled day", file: file, line: line)
            XCTAssertGreaterThanOrEqual(startMinute, window.startMinute, file: file, line: line)
            XCTAssertLessThanOrEqual(endMinute, window.endMinute, file: file, line: line)
            XCTAssertGreaterThan(block.minutes, 0, file: file, line: line)
        }
        for (a, b) in zip(planned, planned.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                b.start.timeIntervalSince(a.end), TimeInterval(settings.breakMinutes * 60) - 1,
                "blocks overlap or have no break", file: file, line: line)
        }
    }

    func testSingleTaskIsSplitIntoSessionsBeforeDeadline() {
        let settings = PlannerSettings()
        let now = date(16, 12)
        let task = TaskItem(title: "Essay", difficulty: .easy, estimatedMinutes: 120, deadline: date(20, 18))
        let result = plan([task], settings: settings, now: now)
        let blocks = result.blocks
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.minutes }, 120)
        XCTAssertTrue(blocks.allSatisfy { $0.end <= task.deadline })
        XCTAssertTrue(result.atRisk.isEmpty)
        XCTAssertEqual(blocks.first?.start, date(16, 16))
        // Two blocks per day at most while there is plenty of time.
        let firstDay = blocks.filter { calendar.isDate($0.start, inSameDayAs: now) }
        XCTAssertEqual(firstDay.count, 2)
        assertValid(result, settings: settings, now: now)
    }

    func testHardTaskGetsBuffer() {
        let task = TaskItem(title: "Maths", difficulty: .hard, estimatedMinutes: 60, deadline: date(20, 18))
        XCTAssertEqual(task.plannedMinutes, 75)
        let result = plan([task], now: date(16, 12))
        XCTAssertEqual(result.blocks.reduce(0) { $0 + $1.minutes }, 75)
    }

    func testTightDeadlineDropsCaps() {
        let settings = PlannerSettings()
        let now = date(16, 12)
        // 4h needed, due tonight 21:00, window 16-21 (5h). Daily cap is 3h.
        let task = TaskItem(title: "Cram", difficulty: .easy, estimatedMinutes: 240, deadline: date(16, 21))
        let result = plan([task], settings: settings, now: now)
        XCTAssertEqual(result.blocks.reduce(0) { $0 + $1.minutes }, 240)
        XCTAssertTrue(result.blocks.allSatisfy { $0.end <= task.deadline })
        XCTAssertTrue(result.atRisk.isEmpty)
        assertValid(result, settings: settings, now: now)
    }

    func testImpossibleDeadlineIsAtRiskAndPlannedLate() {
        let settings = PlannerSettings()
        let now = date(16, 12)
        let task = TaskItem(title: "Too much", difficulty: .easy, estimatedMinutes: 480, deadline: date(16, 21))
        let result = plan([task], settings: settings, now: now)
        XCTAssertTrue(result.atRisk.contains(task.id))
        XCTAssertEqual(result.blocks.reduce(0) { $0 + $1.minutes }, 480)
        XCTAssertTrue(result.blocks.contains { $0.isLate && $0.start >= task.deadline })
        XCTAssertTrue(result.unscheduled.isEmpty)
        assertValid(result, settings: settings, now: now)
    }

    func testOverdueTaskIsStillPlanned() {
        let now = date(16, 12)
        let task = TaskItem(title: "Late", difficulty: .easy, estimatedMinutes: 30, deadline: date(15, 12))
        let result = plan([task], now: now)
        XCTAssertTrue(result.atRisk.contains(task.id))
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].start, date(16, 16))
    }

    func testEarliestDeadlineGoesFirst() {
        let now = date(16, 12)
        var settings = PlannerSettings()
        settings.hardestFirst = false
        let later = TaskItem(title: "Later", difficulty: .hard, estimatedMinutes: 40, deadline: date(19, 18))
        let sooner = TaskItem(title: "Sooner", difficulty: .easy, estimatedMinutes: 45, deadline: date(17, 18))
        let result = plan([later, sooner], settings: settings, now: now)
        XCTAssertEqual(result.blocks.first?.taskID, sooner.id)
        assertValid(result, settings: settings, now: now)
    }

    func testHardestFirstWithinDay() {
        let now = date(16, 12)
        let settings = PlannerSettings()
        let easy = TaskItem(title: "Easy", difficulty: .easy, estimatedMinutes: 45, deadline: date(17, 18))
        let hard = TaskItem(title: "Hard", difficulty: .hard, estimatedMinutes: 36, deadline: date(19, 18))
        let result = plan([easy, hard], settings: settings, now: now)
        let today = result.blocks.filter { calendar.isDate($0.start, inSameDayAs: now) }
        XCTAssertEqual(today.first?.taskID, hard.id)
        XCTAssertEqual(today.first?.start, date(16, 16))
        assertValid(result, settings: settings, now: now)
    }

    func testHardestFirstNeverBreaksADeadline() {
        let now = date(16, 12)
        let settings = PlannerSettings()
        // Easy task is due at 16:50 today, so it must stay first.
        let easy = TaskItem(title: "Easy", difficulty: .easy, estimatedMinutes: 45, deadline: date(16, 16, 50))
        let hard = TaskItem(title: "Hard", difficulty: .hard, estimatedMinutes: 36, deadline: date(19, 18))
        let result = plan([easy, hard], settings: settings, now: now)
        let easyBlock = result.blocks.first { $0.taskID == easy.id }!
        XCTAssertLessThanOrEqual(easyBlock.end, easy.deadline)
        XCTAssertFalse(result.atRisk.contains(easy.id))
        assertValid(result, settings: settings, now: now)
    }

    func testPinnedAndSkippedBlocksAreRespected() {
        let now = date(16, 12)
        let settings = PlannerSettings()
        let task = TaskItem(title: "Read", difficulty: .easy, estimatedMinutes: 90, deadline: date(20, 18))
        let other = TaskItem(title: "Other", difficulty: .easy, estimatedMinutes: 45, deadline: date(20, 18))
        let pinned = FocusBlock(taskID: task.id, start: date(16, 17), end: date(16, 17, 45), isPinned: true)
        let skipped = FocusBlock(taskID: other.id, start: date(16, 16), end: date(16, 16, 45), status: .skipped)
        let result = plan([task, other], existing: [pinned, skipped], settings: settings, now: now)
        XCTAssertTrue(result.blocks.contains(pinned))
        let fresh = result.blocks.filter { $0.status == .planned && $0.id != pinned.id }
        XCTAssertEqual(fresh.filter { $0.taskID == task.id }.reduce(0) { $0 + $1.minutes }, 45)
        XCTAssertEqual(fresh.filter { $0.taskID == other.id }.reduce(0) { $0 + $1.minutes }, 45)
        for block in fresh {
            XCTAssertFalse(block.start < date(16, 16, 55), "skipped slot was reused")
            XCTAssertFalse(block.start < pinned.end.addingTimeInterval(600) && block.end > pinned.start.addingTimeInterval(-600))
        }
        assertValid(result, settings: settings, now: now)
    }

    func testProgressAndCheckInAreCounted() {
        let now = date(16, 18)
        var task = TaskItem(title: "Read", difficulty: .easy, estimatedMinutes: 120, deadline: date(20, 18))
        task.completedMinutes = 45
        let waiting = FocusBlock(taskID: task.id, start: date(16, 17), end: date(16, 17, 45))
        let result = plan([task], existing: [waiting], now: now)
        let future = result.blocks.filter { $0.start > now }
        XCTAssertEqual(future.reduce(0) { $0 + $1.minutes }, 30)
    }

    func testRunningBlockIsKept() {
        let now = date(16, 17, 20)
        let task = TaskItem(title: "Read", difficulty: .easy, estimatedMinutes: 90, deadline: date(20, 18))
        let running = FocusBlock(taskID: task.id, start: date(16, 17), end: date(16, 17, 45))
        let result = plan([task], existing: [running], now: now)
        XCTAssertTrue(result.blocks.contains(running))
        XCTAssertEqual(FocusGuard.minutesLeft(in: result.blocks, at: now), 25)
        XCTAssertEqual(FocusGuard.minutesLeft(in: result.blocks, at: date(16, 17, 50)), 0)
        let next = result.blocks.first { $0.start > now }!
        XCTAssertGreaterThanOrEqual(next.start, date(16, 17, 55))
    }

    func testDoneAndDeletedTasksLoseFutureBlocks() {
        let now = date(16, 12)
        var done = TaskItem(title: "Done", difficulty: .easy, estimatedMinutes: 60, deadline: date(20, 18))
        done.isDone = true
        let stale = FocusBlock(taskID: done.id, start: date(16, 17), end: date(16, 17, 45), isPinned: true)
        let orphan = FocusBlock(taskID: UUID(), start: date(16, 18), end: date(16, 18, 45), isPinned: true)
        let result = plan([done], existing: [stale, orphan], now: now)
        XCTAssertTrue(result.blocks.isEmpty)
    }

    func testDisabledDaysAndDailyCap() {
        let now = date(16, 12)
        var settings = PlannerSettings()
        settings.windows[2].enabled = false // Tuesday
        settings.maxDailyMinutes = 60
        let task = TaskItem(title: "Big", difficulty: .easy, estimatedMinutes: 300, deadline: date(27, 18))
        let result = plan([task], settings: settings, now: now)
        XCTAssertEqual(result.blocks.reduce(0) { $0 + $1.minutes }, 300)
        XCTAssertFalse(result.blocks.contains { calendar.component(.weekday, from: $0.start) == 3 })
        var perDay: [Date: Int] = [:]
        for block in result.blocks { perDay[calendar.startOfDay(for: block.start), default: 0] += block.minutes }
        XCTAssertTrue(perDay.values.allSatisfy { $0 <= 60 })
        XCTAssertTrue(result.atRisk.isEmpty)
        assertValid(result, settings: settings, now: now)
    }

    func testReplanningIsStable() {
        let now = date(16, 12)
        let settings = PlannerSettings()
        let tasks = [
            TaskItem(title: "A", difficulty: .hard, estimatedMinutes: 150, deadline: date(19, 18)),
            TaskItem(title: "B", difficulty: .easy, estimatedMinutes: 60, deadline: date(18, 18)),
            TaskItem(title: "C", difficulty: .medium, estimatedMinutes: 200, deadline: date(24, 18)),
        ]
        let first = plan(tasks, settings: settings, now: now)
        let second = plan(tasks, existing: first.blocks, settings: settings, now: now)
        XCTAssertEqual(first.blocks.map { [$0.start, $0.end] }, second.blocks.map { [$0.start, $0.end] })
        XCTAssertEqual(first.blocks.map { $0.id }, second.blocks.map { $0.id })
        for task in tasks {
            XCTAssertEqual(first.blocks.filter { $0.taskID == task.id }.reduce(0) { $0 + $1.minutes }, task.plannedMinutes)
        }
        assertValid(first, settings: settings, now: now)
    }

    func testRandomisedPlansAreAlwaysValid() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let now = date(16, Int.random(in: 0...23, using: &generator), Int.random(in: 0...59, using: &generator))
            var settings = PlannerSettings()
            settings.sessionMinutes = [25, 30, 45, 50, 60, 90].randomElement(using: &generator)!
            settings.breakMinutes = [5, 10, 15].randomElement(using: &generator)!
            settings.maxDailyMinutes = [60, 120, 180, 300].randomElement(using: &generator)!
            let tasks = (0..<Int.random(in: 1...8, using: &generator)).map { index in
                TaskItem(
                    title: "T\(index)",
                    difficulty: Difficulty.allCases.randomElement(using: &generator)!,
                    estimatedMinutes: Int.random(in: 1...40, using: &generator) * 15,
                    deadline: now.addingTimeInterval(TimeInterval(Int.random(in: -1...14, using: &generator) * 86_400 + 3_600))
                )
            }
            let result = plan(tasks, settings: settings, now: now)
            assertValid(result, settings: settings, now: now)
            for task in tasks {
                let total = result.blocks.filter { $0.taskID == task.id }.reduce(0) { $0 + $1.minutes }
                XCTAssertEqual(total + (result.unscheduled[task.id] ?? 0), task.plannedMinutes)
                let late = result.blocks.contains { $0.taskID == task.id && $0.end > task.deadline }
                if late { XCTAssertTrue(result.atRisk.contains(task.id)) }
            }
        }
    }

    func testPersistenceRoundTrip() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lockin-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = AppData()
        data.tasks = [TaskItem(title: "A", deadline: date(20, 18))]
        data.blocks = [FocusBlock(taskID: data.tasks[0].id, start: date(16, 16), end: date(16, 16, 45))]
        data.settings.strictMode = true
        XCTAssertTrue(Persistence.save(data, to: url))
        XCTAssertEqual(Persistence.load(from: url), data)
    }
}
