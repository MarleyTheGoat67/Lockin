import SwiftUI

extension TaskCategory {
    var color: Color {
        switch self {
        case .school: return .indigo
        case .work: return .blue
        case .personal: return .pink
        case .chores: return .orange
        case .creative: return .purple
        case .other: return .gray
        }
    }
}

extension Difficulty {
    var color: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

enum Format {
    /// "45 min", "2 h", "1 h 30 min"
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// "45m", "2h", "1h30"
    static func shortDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h\(rest)"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func timeRange(_ block: FocusBlock) -> String {
        "\(time(block.start)) - \(time(block.end))"
    }

    /// "Today", "Tomorrow" or "Mon 23 Nov"
    static func day(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dayAndTime(_ date: Date, now: Date = Date()) -> String {
        "\(day(date, now: now)) \(time(date))"
    }

    /// "Due today 18:00", "Due in 3 days", "Overdue since Mon 16 Nov"
    static func deadline(_ date: Date, now: Date = Date()) -> String {
        if date < now { return "Overdue since \(day(date, now: now))" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days <= 1 { return "Due \(day(date, now: now).lowercased()) \(time(date))" }
        if days < 7 { return "Due in \(days) days" }
        return "Due \(day(date, now: now))"
    }

    /// "in 2 h 5 min", "in 12 min", "now"
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        return "in \(duration(minutes))"
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardModifier())
    }
}

/// Small coloured label such as "Hard" or "At risk".
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// Round category icon.
struct CategoryIcon: View {
    let category: TaskCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(category.color)
            .frame(width: size, height: size)
            .background(category.color.opacity(0.15))
            .clipShape(Circle())
    }
}

/// Section title used inside cards.
struct CardTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }
}
