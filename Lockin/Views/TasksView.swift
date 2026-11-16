import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: Store
    @State private var showAdd: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if store.tasks.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No tasks yet")
                                .font(.headline)
                            Text("Tap + to add what you need to do. Lockin puts it in your calendar automatically.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !store.activeTasks.isEmpty {
                    Section("To do") {
                        ForEach(store.activeTasks) { task in
                            NavigationLink {
                                TaskDetailView(taskID: task.id)
                            } label: {
                                TaskRow(task: task, atRisk: store.atRisk.contains(task.id))
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.setDone(task.id, done: true)
                                } label: {
                                    Label("Done", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteTask(task.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !store.doneTasks.isEmpty {
                    Section("Done") {
                        ForEach(store.doneTasks) { task in
                            NavigationLink {
                                TaskDetailView(taskID: task.id)
                            } label: {
                                TaskRow(task: task, atRisk: false)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteTask(task.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
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

// MARK: - Row

struct TaskRow: View {
    let task: TaskItem
    let atRisk: Bool

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: task.category)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundColor(task.isDone ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if task.isDone {
                    Text("Done - \(Format.duration(task.completedMinutes)) of focus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(Format.deadline(task.deadline)) - \(Format.duration(task.remainingMinutes)) left")
                        .font(.caption)
                        .foregroundColor(task.deadline < Date() ? Color.red : Color.secondary)
                    HStack(spacing: 6) {
                        Pill(text: task.difficulty.label, color: task.difficulty.color)
                        if atRisk {
                            Pill(text: "At risk", color: .orange)
                        }
                    }
                    ProgressView(value: task.progress)
                        .tint(task.category.color)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / edit

struct TaskEditorView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    private let existing: TaskItem?

    @State private var title: String
    @State private var category: TaskCategory
    @State private var difficulty: Difficulty
    @State private var minutes: Int
    @State private var deadline: Date
    @State private var notes: String

    init(task: TaskItem?) {
        existing = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? .school)
        _difficulty = State(initialValue: task?.difficulty ?? .medium)
        _minutes = State(initialValue: task?.estimatedMinutes ?? 60)
        _deadline = State(initialValue: task?.deadline ?? TaskEditorView.defaultDeadline())
        _notes = State(initialValue: task?.notes ?? "")
    }

    /// Tomorrow at 18:00.
    private static func defaultDeadline() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draft: TaskItem {
        var task = existing ?? TaskItem(title: trimmedTitle, deadline: deadline)
        task.title = trimmedTitle
        task.category = category
        task.difficulty = difficulty
        task.estimatedMinutes = minutes
        task.deadline = deadline
        task.notes = notes
        return task
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What do you need to do?") {
                    TextField("e.g. Maths homework p. 42", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { item in
                            Label(item.label, systemImage: item.symbol).tag(item)
                        }
                    }
                }

                Section {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How hard is it?")
                } footer: {
                    Text(difficultyHint)
                }

                Section {
                    Stepper(value: $minutes, in: 15...600, step: 15) {
                        HStack {
                            Text("Time needed")
                            Spacer()
                            Text(Format.duration(minutes))
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach([30, 60, 120, 180], id: \.self) { preset in
                            Button(Format.shortDuration(preset)) {
                                minutes = preset
                            }
                            .buttonStyle(.bordered)
                            .tint(minutes == preset ? Color.accentColor : Color.secondary)
                        }
                    }
                } header: {
                    Text("How long will it take?")
                } footer: {
                    Text(planHint)
                }

                Section("When is it due?") {
                    DatePicker("Deadline", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(existing == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private var difficultyHint: String {
        switch difficulty {
        case .easy:
            return "Easy tasks are planned as they are."
        case .medium:
            return "Medium tasks get 10% extra time, just in case."
        case .hard:
            return "Hard tasks get 25% extra time, go first in the day, and get a longer break afterwards."
        }
    }

    private var planHint: String {
        let planned = draft.plannedMinutes
        let session = store.settings.sessionMinutes
        let sessions = max(1, Int((Double(planned) / Double(session)).rounded(.up)))
        let buffer = draft.bufferMinutes
        let bufferText = buffer > 0 ? " (includes \(Format.duration(buffer)) buffer)" : ""
        return "Lockin will plan \(Format.duration(planned))\(bufferText) as about \(sessions) focus \(sessions == 1 ? "block" : "blocks") before the deadline."
    }

    private func save() {
        if existing == nil {
            store.addTask(draft)
        } else {
            store.updateTask(draft)
        }
        dismiss()
    }
}

// MARK: - Detail

struct TaskDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID

    @State private var showEdit: Bool = false
    @State private var confirmDelete: Bool = false

    var body: some View {
        Group {
            if let task = store.task(taskID) {
                content(task)
            } else {
                Text("This task was deleted.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ task: TaskItem) -> some View {
        let now = Date()
        let upcoming = store.upcomingBlocks(from: now).filter { $0.taskID == task.id }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        CategoryIcon(category: task.category, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 6) {
                                Pill(text: task.category.label, color: task.category.color)
                                Pill(text: task.difficulty.label, color: task.difficulty.color)
                                if store.atRisk.contains(task.id) {
                                    Pill(text: "At risk", color: .orange)
                                }
                            }
                        }
                    }
                    ProgressView(value: task.progress)
                        .tint(task.category.color)
                    Text(progressText(task))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                LabeledContent("Deadline", value: Format.dayAndTime(task.deadline, now: now))
                LabeledContent("Your estimate", value: Format.duration(task.estimatedMinutes))
                if task.bufferMinutes > 0 {
                    LabeledContent("Buffer for difficulty", value: "+ \(Format.duration(task.bufferMinutes))")
                }
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.subheadline)
                }
            }

            if !task.isDone {
                Section {
                    Button {
                        store.startNow(task.id)
                    } label: {
                        Label("Start a focus session now", systemImage: "play.fill")
                    }
                    Button {
                        store.setDone(task.id, done: true)
                    } label: {
                        Label("Mark as done", systemImage: "checkmark.circle")
                    }
                    Button {
                        store.addTime(task.id, minutes: 30)
                    } label: {
                        Label("I need 30 min more", systemImage: "plus.circle")
                    }
                }

                Section("Planned focus blocks") {
                    if upcoming.isEmpty {
                        Text("Nothing planned.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(upcoming) { block in
                            BlockRow(block: block, now: now, showDay: true)
                        }
                    }
                }
            } else {
                Section {
                    Button {
                        store.setDone(task.id, done: false)
                    } label: {
                        Label("Not done after all - reopen", systemImage: "arrow.uturn.backward")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete task", systemImage: "trash")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            TaskEditorView(task: task)
                .environmentObject(store)
        }
        .confirmationDialog("Delete this task and its planned blocks?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteTask(task.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func progressText(_ task: TaskItem) -> String {
        if task.isDone {
            return "Done - \(Format.duration(task.completedMinutes)) of focus"
        }
        return "\(Format.duration(task.completedMinutes)) done, \(Format.duration(task.remainingMinutes)) left"
    }
}
