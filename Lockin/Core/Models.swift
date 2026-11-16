import Foundation

// MARK: - Difficulty

enum Difficulty: Int, Codable, CaseIterable, Identifiable {
    case easy = 1
    case medium = 2
    case hard = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    /// People underestimate hard work, so harder tasks get extra planned time.
    var bufferMultiplier: Double {
        switch self {
        case .easy: return 1.0
        case .medium: return 1.1
        case .hard: return 1.25
        }
    }

    /// Extra break minutes after a block of this difficulty.
    var extraBreakMinutes: Int {
        self == .hard ? 5 : 0
    }
}

// MARK: - Category

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case school
    case work
    case personal
    case chores
    case creative
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .school: return "School"
        case .work: return "Work"
        case .personal: return "Personal"
        case .chores: return "Chores"
        case .creative: return "Creative"
        case .other: return "Other"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .school: return "graduationcap.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .chores: return "house.fill"
        case .creative: return "paintbrush.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
}

// MARK: - Task

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: TaskCategory = .school
    var difficulty: Difficulty = .medium
    /// The user's own estimate, in minutes.
    var estimatedMinutes: Int = 60
    /// Focus minutes already confirmed as worked.
    var completedMinutes: Int = 0
    var deadline: Date
    var notes: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date()
    var doneAt: Date? = nil

    /// Estimate plus the difficulty buffer, rounded up to 5 minutes.
    var plannedMinutes: Int {
        let raw = Double(estimatedMinutes) * difficulty.bufferMultiplier
        return Int((raw / 5).rounded(.up)) * 5
    }

    var bufferMinutes: Int {
        max(0, plannedMinutes - estimatedMinutes)
    }

    var remainingMinutes: Int {
        isDone ? 0 : max(0, plannedMinutes - completedMinutes)
    }

    var progress: Double {
        if isDone { return 1 }
        guard plannedMinutes > 0 else { return 0 }
        return min(1, Double(completedMinutes) / Double(plannedMinutes))
    }
}

// MARK: - Focus block

enum BlockStatus: String, Codable {
    /// Scheduled. If its end time has passed it is waiting for a check-in.
    case planned
    /// The user confirmed they worked.
    case completed
    /// The user said they did not work; the time gets planned again.
    case missed
    /// The user skipped it in advance; the time gets planned again.
    case skipped
}

struct FocusBlock: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var taskID: UUID
    var start: Date
    var end: Date
    var status: BlockStatus = .planned
    /// Moved or started by hand: the planner will not touch it.
    var isPinned: Bool = false
    /// Planned after the task's deadline because nothing earlier was free.
    var isLate: Bool = false

    var minutes: Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    func isActive(at now: Date) -> Bool {
        status == .planned && start <= now && now < end
    }

    func awaitsCheckIn(at now: Date) -> Bool {
        status == .planned && end <= now
    }
}

// MARK: - Settings

struct DayWindow: Codable, Equatable {
    var enabled: Bool
    /// Minutes after midnight.
    var startMinute: Int
    var endMinute: Int
}

struct PlannerSettings: Codable, Equatable {
    /// Index 0 = Sunday ... 6 = Saturday (Calendar weekday - 1).
    var windows: [DayWindow] = PlannerSettings.defaultWindows
    var sessionMinutes: Int = 45
    var breakMinutes: Int = 10
    var maxDailyMinutes: Int = 180
    var hardestFirst: Bool = true
    var reminderLeadMinutes: Int = 5
    var strictMode: Bool = false
    var dailySummary: Bool = true
    var summaryHour: Int = 8
    var onboardingDone: Bool = false

    static var defaultWindows: [DayWindow] {
        let weekend = DayWindow(enabled: true, startMinute: 10 * 60, endMinute: 18 * 60)
        let weekday = DayWindow(enabled: true, startMinute: 16 * 60, endMinute: 21 * 60)
        return [weekend, weekday, weekday, weekday, weekday, weekday, weekend]
    }

    func window(forWeekday weekday: Int) -> DayWindow {
        let index = (weekday - 1 + 7) % 7
        guard index < windows.count else {
            return DayWindow(enabled: false, startMinute: 0, endMinute: 0)
        }
        return windows[index]
    }
}

// MARK: - Everything that is saved to disk

struct AppData: Codable, Equatable {
    var tasks: [TaskItem] = []
    var blocks: [FocusBlock] = []
    var settings: PlannerSettings = PlannerSettings()
}
