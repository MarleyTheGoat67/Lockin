import Foundation
import UserNotifications

/// Local notifications: block start, heads-up, block end (with check-in buttons),
/// deadline warnings and a morning summary. No server needed.
enum NotificationManager {
    static let checkInCategory = "LOCKIN_CHECKIN"
    static let workedAction = "LOCKIN_WORKED"
    static let missedAction = "LOCKIN_MISSED"

    /// iOS keeps at most 64 pending notifications per app, so only the next blocks get one.
    private static let maxBlocks = 15
    private static let maxDeadlines = 8
    private static let summaryDays = 5

    static func registerCategories() {
        let worked = UNNotificationAction(identifier: workedAction, title: "I worked on it", options: [])
        let missed = UNNotificationAction(identifier: missedAction, title: "Didn't happen - plan it again", options: [])
        let category = UNNotificationCategory(
            identifier: checkInCategory,
            actions: [worked, missed],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func checkPermission(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { completion(status) }
        }
    }

    static func sync(tasks: [TaskItem], blocks: [FocusBlock], settings: PlannerSettings, now: Date) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        var titles: [UUID: String] = [:]
        for task in tasks { titles[task.id] = task.title }

        let upcoming = blocks
            .filter { $0.status == .planned && $0.end > now && titles[$0.taskID] != nil }
            .sorted { $0.start < $1.start }

        for block in upcoming.prefix(maxBlocks) {
            let title = titles[block.taskID] ?? "Focus"
            let endText = timeText(block.end)

            if settings.reminderLeadMinutes > 0 {
                add(
                    id: "lead-\(block.id.uuidString)",
                    title: "Focus starts in \(settings.reminderLeadMinutes) min",
                    body: "\(title) - get your things ready.",
                    at: block.start.addingTimeInterval(TimeInterval(-settings.reminderLeadMinutes * 60)),
                    now: now
                )
            }
            add(
                id: "start-\(block.id.uuidString)",
                title: "Time to focus: \(title)",
                body: "\(block.minutes) min. Social media is blocked until \(endText).",
                at: block.start,
                now: now
            )
            add(
                id: "end-\(block.id.uuidString)",
                title: "Session over - nice work",
                body: "Did you work on \(title)? Check in so your plan stays right.",
                at: block.end,
                now: now,
                category: checkInCategory,
                userInfo: ["blockID": block.id.uuidString]
            )
        }

        // Deadline warnings: the evening before / 24 h ahead, only if work is left.
        let open = tasks
            .filter { !$0.isDone && $0.remainingMinutes > 0 }
            .sorted { $0.deadline < $1.deadline }
        for task in open.prefix(maxDeadlines) {
            add(
                id: "deadline-\(task.id.uuidString)",
                title: "Due in 24 hours: \(task.title)",
                body: "Still about \(durationText(task.remainingMinutes)) of work left.",
                at: task.deadline.addingTimeInterval(-86_400),
                now: now
            )
        }

        // Morning summary of the day's plan.
        if settings.dailySummary {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            for offset in 0..<summaryDays {
                guard
                    let day = calendar.date(byAdding: .day, value: offset, to: today),
                    let fireDate = calendar.date(bySettingHour: settings.summaryHour, minute: 0, second: 0, of: day)
                else { continue }
                let dayBlocks = upcoming.filter { calendar.isDate($0.start, inSameDayAs: day) }
                guard let first = dayBlocks.first else { continue }
                let minutes = dayBlocks.reduce(0) { $0 + $1.minutes }
                let count = dayBlocks.count
                add(
                    id: "summary-\(offset)",
                    title: "Today: \(count) focus \(count == 1 ? "block" : "blocks"), \(durationText(minutes))",
                    body: "First up at \(timeText(first.start)): \(titles[first.taskID] ?? "Focus").",
                    at: fireDate,
                    now: now
                )
            }
        }
    }

    private static func add(
        id: String,
        title: String,
        body: String,
        at date: Date,
        now: Date,
        category: String? = nil,
        userInfo: [String: String] = [:]
    ) {
        let delay = date.timeIntervalSince(now)
        guard delay > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let category = category {
            content.categoryIdentifier = category
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }
}

/// Shows banners while the app is open and handles the check-in buttons.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let rawID = response.notification.request.content.userInfo["blockID"] as? String
        let blockID = rawID.flatMap { UUID(uuidString: $0) }
        DispatchQueue.main.async {
            Store.shared.handleNotificationAction(action, blockID: blockID)
            completionHandler()
        }
    }
}
