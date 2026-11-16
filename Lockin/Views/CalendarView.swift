import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: Store
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedBlock: FocusBlock?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(selectedDay: $selectedDay)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                Divider()
                DayTimeline(day: selectedDay, selectedBlock: $selectedBlock)
            }
            .navigationTitle(selectedDay.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Today") {
                        selectedDay = calendar.startOfDay(for: Date())
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        shiftWeek(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous week")
                    Button {
                        shiftWeek(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next week")
                }
            }
            .sheet(item: $selectedBlock) { block in
                BlockDetailSheet(blockID: block.id)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func shiftWeek(_ direction: Int) {
        if let moved = calendar.date(byAdding: .day, value: 7 * direction, to: selectedDay) {
            selectedDay = moved
        }
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    @EnvironmentObject private var store: Store
    @Binding var selectedDay: Date

    private let calendar = Calendar.current

    private var days: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else { return [selectedDay] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    day: day,
                    minutes: store.plannedMinutes(on: day),
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                    isToday: calendar.isDateInToday(day)
                )
                .onTapGesture {
                    selectedDay = calendar.startOfDay(for: day)
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let minutes: Int
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2)
                .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 17, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
            Text(minutes > 0 ? Format.shortDuration(minutes) : " ")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Day timeline

private struct DayTimeline: View {
    @EnvironmentObject private var store: Store
    let day: Date
    @Binding var selectedBlock: FocusBlock?

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60
    private let gutter: CGFloat = 58

    var body: some View {
        let blocks = store.blocks(on: day)
        let window = store.settings.window(forWeekday: calendar.component(.weekday, from: day))

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary(blocks))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    ZStack(alignment: .topLeading) {
                        hourGrid
                        if window.enabled && window.endMinute > window.startMinute {
                            freeHours(window)
                        }
                        ForEach(blocks) { block in
                            chip(block)
                        }
                        if calendar.isDateInToday(day) {
                            nowLine
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                proxy.scrollTo(scrollHour(blocks, window), anchor: .top)
            }
            .onChange(of: day) { _ in
                proxy.scrollTo(scrollHour(store.blocks(on: day), window), anchor: .top)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func summary(_ blocks: [FocusBlock]) -> String {
        let title = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if blocks.isEmpty { return "\(title) - nothing planned" }
        let minutes = blocks.reduce(0) { $0 + $1.minutes }
        return "\(title) - \(blocks.count) \(blocks.count == 1 ? "block" : "blocks"), \(Format.duration(minutes))"
    }

    private func scrollHour(_ blocks: [FocusBlock], _ window: DayWindow) -> Int {
        if let first = blocks.first {
            return max(0, calendar.component(.hour, from: first.start) - 1)
        }
        if window.enabled {
            return max(0, window.startMinute / 60 - 1)
        }
        return 8
    }

    private func offset(for date: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(calendar.startOfDay(for: day)) / 60
        return CGFloat(minutes) / 60 * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.6))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .padding(.top, 8)
    }

    private func freeHours(_ window: DayWindow) -> some View {
        let top = CGFloat(window.startMinute) / 60 * hourHeight
        let height = CGFloat(window.endMinute - window.startMinute) / 60 * hourHeight
        return Rectangle()
            .fill(Color.accentColor.opacity(0.06))
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.leading, gutter)
            .offset(y: top + 8)
            .allowsHitTesting(false)
    }

    private func chip(_ block: FocusBlock) -> some View {
        let color = store.task(block.taskID)?.category.color ?? Color.gray
        let height = max(24, CGFloat(block.minutes) / 60 * hourHeight - 2)
        let done = block.status == .completed
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.title(for: block))
                    .font(.caption.weight(.semibold))
                    .strikethrough(done)
                    .lineLimit(1)
                if height >= 38 {
                    Text(Format.timeRange(block))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if block.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(color.opacity(done ? 0.10 : 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, gutter)
        .padding(.trailing, 12)
        .offset(y: offset(for: block.start) + 8)
        .onTapGesture {
            selectedBlock = block
        }
    }

    private var nowLine: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1.5)
            }
            .padding(.leading, gutter - 4)
            .offset(y: offset(for: context.date) + 8 - 4)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Block details

struct BlockDetailSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let blockID: UUID

    @State private var newStart: Date = Date()
    @State private var didLoad: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if let block = store.block(blockID) {
                    details(block)
                } else {
                    Text("This block was re-planned.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Focus block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func details(_ block: FocusBlock) -> some View {
        let now = Date()
        let isFuture = block.status == .planned && block.start > now
        return Form {
            Section {
                HStack(spacing: 12) {
                    if let task = store.task(block.taskID) {
                        CategoryIcon(category: task.category)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.title(for: block))
                            .font(.headline)
                        Text("\(Format.day(block.start)), \(Format.timeRange(block)) - \(Format.duration(block.minutes))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                if block.isLate {
                    Label("Planned after the deadline - nothing earlier was free.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                if block.status == .completed {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            if isFuture {
                Section {
                    Button {
                        store.startBlockNow(block.id)
                        dismiss()
                    } label: {
                        Label("Start now", systemImage: "play.fill")
                    }
                    Button {
                        store.skip(block.id)
                        dismiss()
                    } label: {
                        Label("Not then - plan it another time", systemImage: "arrow.uturn.forward")
                    }
                }

                Section("Move it yourself") {
                    DatePicker("New start", selection: $newStart, in: now..., displayedComponents: [.date, .hourAndMinute])
                    Button {
                        store.move(block.id, to: newStart)
                        dismiss()
                    } label: {
                        Label("Move and pin here", systemImage: "pin.fill")
                    }
                }
            }

            if block.awaitsCheckIn(at: now) {
                Section("Did you work?") {
                    Button {
                        store.checkIn(block.id, worked: true)
                        dismiss()
                    } label: {
                        Label("Yes, I worked", systemImage: "checkmark")
                    }
                    Button {
                        store.checkIn(block.id, worked: false)
                        dismiss()
                    } label: {
                        Label("No - plan it again", systemImage: "arrow.uturn.forward")
                    }
                }
            }
        }
        .onAppear {
            if !didLoad {
                newStart = max(block.start, now)
                didLoad = true
            }
        }
    }
}
