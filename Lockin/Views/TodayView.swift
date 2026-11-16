import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @State private var showAdd: Bool = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                ScrollView {
                    TodayContent(now: context.date, showAdd: $showAdd)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .sheet(isPresented: $showAdd) {
                TaskEditorView(task: nil)
                    .environmentObject(store)
            }
        }
    }
}

private struct TodayContent: View {
    @EnvironmentObject private var store: Store
    let now: Date
    @Binding var showAdd: Bool

    var body: some View {
        VStack(spacing: 16) {
            if store.tasks.isEmpty {
                EmptyStartCard(showAdd: $showAdd)
            } else {
                WorkloadCard(now: now)
                NowNextCard(now: now)
                ForEach(store.blocksAwaitingCheckIn(at: now)) { block in
                    CheckInCard(block: block)
                }
                ForEach(store.tasksNeedingDecision(at: now)) { task in
                    DecisionCard(task: task)
                }
                RiskCard()
                WeekLoadCard(now: now)
                TodayScheduleCard(now: now)
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyStartCard: View {
    @Binding var showAdd: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text("Nothing to do yet")
                .font(.title3.weight(.semibold))
            Text("Add a task with a deadline and how long it takes. Lockin plans the focus time for you and blocks distractions while you work.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Text("Add your first task")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 12)
        .card()
        .padding(.top, 24)
    }
}

// MARK: - How much work is there?

private struct WorkloadCard: View {
    @EnvironmentObject private var store: Store
    let now: Date

    var body: some View {
        let open = store.activeTasks
        let remaining = store.totalRemainingMinutes
        let plannedToday = store.plannedMinutes(on: now)
        let doneToday = store.completedMinutes(on: now)

        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Your workload")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.duration(remaining))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("left")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            Text("\(open.count) open \(open.count == 1 ? "task" : "tasks")\(nextDeadlineText(open))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if plannedToday > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(min(doneToday, plannedToday)), total: Double(plannedToday))
                    Text("Today: \(Format.duration(doneToday)) done of \(Format.duration(plannedToday)) planned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No focus time planned today.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .card()
    }

    private func nextDeadlineText(_ open: [TaskItem]) -> String {
        guard let next = open.first else { return "" }
        return " - next deadline: \(Format.dayAndTime(next.deadline, now: now))"
    }
}

// MARK: - Running / next block

private struct NowNextCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: AppRouter
    let now: Date

    var body: some View {
        if let active = store.activeBlock {
            running(active)
        } else if let next = store.upcomingBlocks(from: now).first {
            upcoming(next)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                CardTitle(text: "Next up")
                Text("Nothing scheduled")
                    .font(.headline)
                Text("Everything is done or there are no free hours. Check your free hours in the Me tab.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .card()
        }
    }

    private func running(_ block: FocusBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("FOCUS NOW")
            }
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.85))

            Text(store.title(for: block))
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text("Until \(Format.time(block.end)) - ends \(Format.countdown(to: block.end, now: now))")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))

            Button {
                router.focus = FocusPresentation(id: block.id)
            } label: {
                Text("Open focus screen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.25))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func upcoming(_ block: FocusBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Next up")
            HStack(spacing: 12) {
                if let task = store.task(block.taskID) {
                    CategoryIcon(category: task.category)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.title(for: block))
                        .font(.headline)
                    Text("\(Format.dayAndTime(block.start, now: now)) - \(Format.duration(block.minutes)) - \(Format.countdown(to: block.start, now: now))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    store.startBlockNow(block.id)
                } label: {
                    Label("Start now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.skip(block.id)
                } label: {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
    }
}

// MARK: - Did you work?

private struct CheckInCard: View {
    @EnvironmentObject private var store: Store
    let block: FocusBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Check in")
            Text("Did you work on \(store.title(for: block))?")
                .font(.headline)
            Text("\(Format.day(block.start)) \(Format.timeRange(block)) - \(Format.duration(block.minutes))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Button {
                    store.checkIn(block.id, worked: true)
                } label: {
                    Label("Yes", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    store.checkIn(block.id, worked: false)
                } label: {
                    Text("No, plan it again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
    }
}

// MARK: - Planned time used up: finished?

private struct DecisionCard: View {
    @EnvironmentObject private var store: Store
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Finished?")
            Text(task.title)
                .font(.headline)
            Text("You worked all the time you planned for this. Is it done?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Button {
                    store.setDone(task.id, done: true)
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    store.addTime(task.id, minutes: 30)
                } label: {
                    Text("Need 30 min more")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
    }
}

// MARK: - Deadline warnings

private struct RiskCard: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let risky = store.activeTasks.filter { store.atRisk.contains($0.id) }
        if !risky.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("DEADLINE AT RISK")
                }
                .font(.caption.weight(.bold))
                .foregroundColor(.orange)

                ForEach(risky) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(Format.duration(task.remainingMinutes)) left - \(Format.deadline(task.deadline))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text("There are not enough free hours before the deadline. Add free hours in the Me tab, start a session now, or move the deadline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .card()
        }
    }
}

// MARK: - Next 7 days

private struct WeekLoadCard: View {
    @EnvironmentObject private var store: Store
    let now: Date

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        let loads = days.map { store.plannedMinutes(on: $0) }
        let scale = max(loads.max() ?? 0, 60)

        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Next 7 days")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    WeekBar(day: day, minutes: loads[index], scale: scale, isToday: index == 0)
                }
            }
        }
        .card()
    }
}

private struct WeekBar: View {
    let day: Date
    let minutes: Int
    let scale: Int
    let isToday: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(minutes > 0 ? Format.shortDuration(minutes) : "-")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.4))
                .frame(height: barHeight)
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundColor(isToday ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var barHeight: CGFloat {
        guard minutes > 0 else { return 4 }
        return max(8, CGFloat(minutes) / CGFloat(scale) * 80)
    }
}

// MARK: - Today's schedule

private struct TodayScheduleCard: View {
    @EnvironmentObject private var store: Store
    let now: Date

    var body: some View {
        let blocks = store.blocks(on: now)
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Today's plan")
            if blocks.isEmpty {
                Text("Nothing planned for today.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(blocks) { block in
                    BlockRow(block: block, now: now)
                }
            }
        }
        .card()
    }
}

/// One line of a schedule: time, task, state.
struct BlockRow: View {
    @EnvironmentObject private var store: Store
    let block: FocusBlock
    var now: Date = Date()
    var showDay: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(store.task(block.taskID)?.category.color ?? Color.gray)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.title(for: block))
                    .font(.subheadline.weight(.medium))
                    .strikethrough(block.status == .completed)
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            stateIcon
        }
    }

    private var timeText: String {
        let range = "\(Format.timeRange(block)) - \(Format.duration(block.minutes))"
        return showDay ? "\(Format.day(block.start, now: now)), \(range)" : range
    }

    @ViewBuilder
    private var stateIcon: some View {
        if block.status == .completed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if block.isActive(at: now) {
            Pill(text: "Now", color: .indigo)
        } else if block.awaitsCheckIn(at: now) {
            Pill(text: "Check in", color: .orange)
        } else if block.isLate {
            Pill(text: "After deadline", color: .red)
        } else if block.isPinned {
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
