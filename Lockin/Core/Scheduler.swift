import Foundation

struct PlanResult {
    /// History, kept blocks and freshly planned blocks, sorted by start.
    var blocks: [FocusBlock]
    /// Tasks that cannot be finished before their deadline with the current free hours.
    var atRisk: Set<UUID>
    /// Minutes that found no free slot at all, per task.
    var unscheduled: [UUID: Int]
}

/// Turns the task list into focus blocks on the calendar.
///
/// Rules, in order of importance:
/// 1. Earliest deadline gets first pick of free time.
/// 2. Work happens only inside the user's free hours, with a break after each block.
/// 3. A task is spread out (two blocks per day) and days are capped, unless that
///    would miss the deadline - then the caps are dropped for that task.
/// 4. If it still does not fit, the rest is planned after the deadline and the
///    task is flagged as at risk.
/// 5. Within a day the hardest work goes first, when that breaks no deadline.
enum Scheduler {
    static let minimumBlockMinutes = 15
    static let blocksPerTaskPerDay = 2

    private struct Slot {
        var start: Date
        var end: Date
    }

    private struct Day {
        var start: Date
        var free: [Slot]
        var load: Int
        var perTask: [UUID: Int]
    }

    static func plan(
        tasks: [TaskItem],
        existing: [FocusBlock],
        settings: PlannerSettings,
        now: Date,
        calendar: Calendar = .current
    ) -> PlanResult {
        let active = tasks.filter { !$0.isDone }
        let activeIDs = Set(active.map { $0.id })
        let allIDs = Set(tasks.map { $0.id })
        var taskByID: [UUID: TaskItem] = [:]
        for task in active { taskByID[task.id] = task }

        // 1. Decide which existing blocks survive.
        var kept: [FocusBlock] = []
        for block in existing {
            switch block.status {
            case .completed, .missed, .skipped:
                kept.append(block)
            case .planned:
                if block.end <= now {
                    // Waiting for a check-in: presumed done until the user says otherwise.
                    if allIDs.contains(block.taskID) { kept.append(block) }
                } else if activeIDs.contains(block.taskID), block.start <= now || block.isPinned {
                    kept.append(block)
                }
            }
        }

        // 2. How much still needs a slot.
        var remaining: [UUID: Int] = [:]
        for task in active {
            let reserved = kept
                .filter { $0.taskID == task.id && $0.status == .planned }
                .reduce(0) { $0 + $1.minutes }
            remaining[task.id] = roundUpToFive(max(0, task.remainingMinutes - reserved))
        }

        // 3. Build the free time, day by day.
        let earliest = roundUpToFiveMinutes(now.addingTimeInterval(5 * 60))
        let today = calendar.startOfDay(for: now)
        let latestDeadline = active.map { $0.deadline }.max() ?? now
        let span = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: latestDeadline)).day ?? 0
        let dayCount = min(max(span + 1, 14) + 7, 90)

        var days: [Day] = []
        for offset in 0..<dayCount {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let window = settings.window(forWeekday: calendar.component(.weekday, from: dayStart))
            var day = Day(start: dayStart, free: [], load: 0, perTask: [:])
            if window.enabled, window.endMinute > window.startMinute {
                let windowStart = time(window.startMinute, on: dayStart, calendar: calendar)
                let windowEnd = time(window.endMinute, on: dayStart, calendar: calendar)
                let start = max(windowStart, earliest)
                if start < windowEnd {
                    day.free = [Slot(start: start, end: windowEnd)]
                }
            }
            days.append(day)
        }

        func dayIndex(of date: Date) -> Int? {
            let index = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? -1
            return days.indices.contains(index) ? index : nil
        }

        func breakSeconds(after taskID: UUID) -> TimeInterval {
            let extra = taskByID[taskID]?.difficulty.extraBreakMinutes ?? 0
            return TimeInterval((settings.breakMinutes + extra) * 60)
        }

        for block in kept {
            guard let index = dayIndex(of: block.start) else { continue }
            if block.status == .planned || block.status == .completed {
                days[index].load += block.minutes
            }
            if block.status == .planned {
                days[index].perTask[block.taskID, default: 0] += 1
            }
            // Kept blocks (and the break around them) are not available.
            let pause = breakSeconds(after: block.taskID)
            let busyStart = block.start.addingTimeInterval(-pause)
            let busyEnd = block.end.addingTimeInterval(pause)
            for dayOffset in [index - 1, index, index + 1] where days.indices.contains(dayOffset) {
                days[dayOffset].free = subtract(busyStart, busyEnd, from: days[dayOffset].free)
            }
        }

        let initialDays = days

        // 4. Place blocks, most urgent task first.
        var newBlocks: [FocusBlock] = []
        var newBlockDay: [Int] = []

        func place(_ task: TaskItem, before limit: Date?, blocksPerDay: Int?, dailyCap: Int?, late: Bool) {
            var left = remaining[task.id] ?? 0
            guard left > 0 else { return }
            let pause = breakSeconds(after: task.id)

            for index in days.indices {
                if left <= 0 { break }
                if let limit = limit, days[index].start >= limit { break }
                var slotIndex = 0
                while slotIndex < days[index].free.count && left > 0 {
                    if let blocksPerDay = blocksPerDay, days[index].perTask[task.id, default: 0] >= blocksPerDay { break }
                    var capLeft = Int.max
                    if let dailyCap = dailyCap {
                        capLeft = dailyCap - days[index].load
                        if capLeft <= 0 { break }
                    }

                    let slot = days[index].free[slotIndex]
                    let slotEnd = limit.map { min($0, slot.end) } ?? slot.end
                    let available = min(minutesBetween(slot.start, slotEnd), capLeft)

                    var chunk: Int
                    if left <= settings.sessionMinutes + 10, left <= available {
                        // Finish the task in one go instead of leaving a tiny leftover block.
                        chunk = left
                    } else {
                        chunk = min(settings.sessionMinutes, left, available)
                        chunk -= chunk % 5
                    }
                    if chunk <= 0 || (chunk < minimumBlockMinutes && chunk < left) {
                        slotIndex += 1
                        continue
                    }

                    let end = slot.start.addingTimeInterval(TimeInterval(chunk * 60))
                    newBlocks.append(FocusBlock(taskID: task.id, start: slot.start, end: end, isLate: late))
                    newBlockDay.append(index)
                    days[index].load += chunk
                    days[index].perTask[task.id, default: 0] += 1
                    left -= chunk

                    let nextStart = end.addingTimeInterval(pause)
                    if nextStart >= slot.end {
                        days[index].free.remove(at: slotIndex)
                    } else {
                        days[index].free[slotIndex].start = nextStart
                    }
                }
            }
            remaining[task.id] = left
        }

        let order = active.sorted { a, b in
            if a.deadline != b.deadline { return a.deadline < b.deadline }
            if a.difficulty != b.difficulty { return a.difficulty.rawValue > b.difficulty.rawValue }
            return a.createdAt < b.createdAt
        }

        var atRisk = Set<UUID>()
        for task in order {
            // Relaxed and spread out.
            place(task, before: task.deadline, blocksPerDay: blocksPerTaskPerDay, dailyCap: settings.maxDailyMinutes, late: false)
            // Deadline is tight: drop the caps.
            place(task, before: task.deadline, blocksPerDay: nil, dailyCap: nil, late: false)
            // Still not enough room: plan the rest late so it is not forgotten.
            if (remaining[task.id] ?? 0) > 0 {
                atRisk.insert(task.id)
                place(task, before: nil, blocksPerDay: nil, dailyCap: nil, late: true)
            }
        }

        // 5. Hardest work first within each day, if nothing breaks.
        if settings.hardestFirst {
            for index in days.indices {
                let onDay = newBlocks.indices
                    .filter { newBlockDay[$0] == index }
                    .sorted { newBlocks[$0].start < newBlocks[$1].start }
                guard onDay.count > 1 else { continue }

                let desired = onDay.sorted { a, b in
                    guard let taskA = taskByID[newBlocks[a].taskID], let taskB = taskByID[newBlocks[b].taskID] else {
                        return newBlocks[a].start < newBlocks[b].start
                    }
                    if taskA.difficulty != taskB.difficulty { return taskA.difficulty.rawValue > taskB.difficulty.rawValue }
                    if taskA.deadline != taskB.deadline { return taskA.deadline < taskB.deadline }
                    return newBlocks[a].start < newBlocks[b].start
                }
                if desired == onDay { continue }

                var free = initialDays[index].free
                var moves: [(index: Int, start: Date, end: Date)] = []
                var fits = true
                for blockIndex in desired {
                    let block = newBlocks[blockIndex]
                    let length = block.minutes
                    guard let slotIndex = free.firstIndex(where: { minutesBetween($0.start, $0.end) >= length }) else {
                        fits = false
                        break
                    }
                    let start = free[slotIndex].start
                    let end = start.addingTimeInterval(TimeInterval(length * 60))
                    if !block.isLate, let task = taskByID[block.taskID], end > task.deadline {
                        fits = false
                        break
                    }
                    moves.append((blockIndex, start, end))
                    let nextStart = end.addingTimeInterval(breakSeconds(after: block.taskID))
                    if nextStart >= free[slotIndex].end {
                        free.remove(at: slotIndex)
                    } else {
                        free[slotIndex].start = nextStart
                    }
                }
                if fits {
                    for move in moves {
                        newBlocks[move.index].start = move.start
                        newBlocks[move.index].end = move.end
                    }
                }
            }
        }

        var unscheduled: [UUID: Int] = [:]
        for (id, minutes) in remaining where minutes > 0 {
            unscheduled[id] = minutes
            atRisk.insert(id)
        }

        // Keep the identity of blocks that did not move, so the UI stays calm.
        let keptIDs = Set(kept.map { $0.id })
        var reusable = existing.filter { $0.status == .planned && !keptIDs.contains($0.id) }
        for index in newBlocks.indices {
            let block = newBlocks[index]
            if let match = reusable.firstIndex(where: { $0.taskID == block.taskID && $0.start == block.start && $0.end == block.end }) {
                newBlocks[index].id = reusable[match].id
                reusable.remove(at: match)
            }
        }

        let all = (kept + newBlocks).sorted { a, b in
            a.start != b.start ? a.start < b.start : a.id.uuidString < b.id.uuidString
        }
        return PlanResult(blocks: all, atRisk: atRisk, unscheduled: unscheduled)
    }

    // MARK: - Helpers

    private static func time(_ minute: Int, on dayStart: Date, calendar: Calendar) -> Date {
        if minute >= 24 * 60 {
            return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(TimeInterval(minute * 60))
    }

    private static func minutesBetween(_ start: Date, _ end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded(.down)))
    }

    private static func roundUpToFive(_ minutes: Int) -> Int {
        ((minutes + 4) / 5) * 5
    }

    private static func roundUpToFiveMinutes(_ date: Date) -> Date {
        let step: TimeInterval = 300
        let seconds = (date.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func subtract(_ busyStart: Date, _ busyEnd: Date, from slots: [Slot]) -> [Slot] {
        var result: [Slot] = []
        for slot in slots {
            if busyEnd <= slot.start || busyStart >= slot.end {
                result.append(slot)
                continue
            }
            if busyStart > slot.start {
                result.append(Slot(start: slot.start, end: busyStart))
            }
            if busyEnd < slot.end {
                result.append(Slot(start: busyEnd, end: slot.end))
            }
        }
        return result
    }
}
