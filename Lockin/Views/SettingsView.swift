import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmErase: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                statsSection
                blockingSection
                sessionSection
                freeHoursSection
                notificationSection
                planSection
            }
            .navigationTitle("Me")
            .onAppear(perform: refreshNotificationStatus)
            .confirmationDialog("Erase all tasks and history?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    store.eraseEverything()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section("Your progress") {
            StatRow(symbol: "flame.fill", color: .orange, title: "Streak", value: "\(store.streakDays) \(store.streakDays == 1 ? "day" : "days")")
            StatRow(symbol: "timer", color: .indigo, title: "Focus time, last 7 days", value: Format.duration(store.completedMinutes(lastDays: 7)))
            StatRow(symbol: "checkmark.circle.fill", color: .green, title: "Sessions, last 7 days", value: "\(store.completedSessions(lastDays: 7))")
            StatRow(symbol: "hand.raised.fill", color: .red, title: "Distractions blocked, last 7 days", value: "\(GuardLog.hits(lastDays: 7))")
        }
    }

    private var blockingSection: some View {
        Section {
            NavigationLink {
                BlockingSetupView()
            } label: {
                Label("Set up social media blocking", systemImage: "lock.shield.fill")
            }
            Toggle(isOn: $store.settings.strictMode) {
                Label("Strict mode", systemImage: "lock.fill")
            }
        } header: {
            Text("Blocking")
        } footer: {
            Text("Strict mode: to end a session early you have to hold a button for 8 seconds. Enough time to change your mind.")
        }
    }

    private var sessionSection: some View {
        Section {
            Picker("Focus block length", selection: $store.settings.sessionMinutes) {
                ForEach([25, 30, 45, 50, 60, 90], id: \.self) { value in
                    Text(Format.duration(value)).tag(value)
                }
            }
            Picker("Break after a block", selection: $store.settings.breakMinutes) {
                ForEach([5, 10, 15, 20, 30], id: \.self) { value in
                    Text(Format.duration(value)).tag(value)
                }
            }
            Stepper(value: $store.settings.maxDailyMinutes, in: 30...600, step: 30) {
                HStack {
                    Text("Most focus per day")
                    Spacer()
                    Text(Format.duration(store.settings.maxDailyMinutes))
                        .foregroundColor(.secondary)
                }
            }
            Toggle("Hardest task first", isOn: $store.settings.hardestFirst)
        } header: {
            Text("Focus blocks")
        } footer: {
            Text("The daily limit is ignored only when a deadline could not be met otherwise.")
        }
    }

    private var freeHoursSection: some View {
        Section {
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { index in
                DayWindowRow(index: index)
            }
        } header: {
            Text("When can you work?")
        } footer: {
            Text("Lockin only plans focus blocks inside these hours.")
        }
    }

    private var notificationSection: some View {
        Section {
            Button {
                notificationButtonTapped()
            } label: {
                HStack {
                    Label("Notifications", systemImage: "bell.badge.fill")
                    Spacer()
                    Text(notificationStatusText)
                        .foregroundColor(.secondary)
                }
            }
            Picker("Heads-up before a block", selection: $store.settings.reminderLeadMinutes) {
                Text("Off").tag(0)
                ForEach([5, 10, 15, 30], id: \.self) { value in
                    Text(Format.duration(value)).tag(value)
                }
            }
            Toggle("Morning summary", isOn: $store.settings.dailySummary)
            if store.settings.dailySummary {
                Picker("Summary time", selection: $store.settings.summaryHour) {
                    ForEach(5..<13, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
            }
        } header: {
            Text("Notifications")
        }
    }

    private var planSection: some View {
        Section {
            Button {
                store.replanEverything()
            } label: {
                Label("Re-plan everything", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Label("Erase all data", systemImage: "trash")
            }
        } header: {
            Text("Plan")
        } footer: {
            Text("Re-plan forgets blocks you moved by hand and builds the calendar from scratch.\n\nInstalled with a free Apple ID? Re-install with Sideloadly every 7 days. Your data stays as long as you do not delete the app first.")
        }
    }

    // MARK: - Notifications

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "On"
        case .denied:
            return "Off - open Settings"
        case .notDetermined:
            return "Tap to allow"
        @unknown default:
            return ""
        }
    }

    private func refreshNotificationStatus() {
        NotificationManager.checkPermission { status in
            notificationStatus = status
        }
    }

    private func notificationButtonTapped() {
        if notificationStatus == .notDetermined {
            NotificationManager.requestPermission { _ in
                refreshNotificationStatus()
                store.refresh()
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct StatRow: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundColor(color)
            }
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }
}

/// One weekday: on/off and from-to times.
private struct DayWindowRow: View {
    @EnvironmentObject private var store: Store
    /// 0 = Sunday ... 6 = Saturday
    let index: Int

    private var window: DayWindow {
        store.settings.windows[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(Calendar.current.weekdaySymbols[index], isOn: $store.settings.windows[index].enabled)
            if window.enabled {
                HStack(spacing: 8) {
                    Text("From")
                        .foregroundColor(.secondary)
                    DatePicker("From", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .foregroundColor(.secondary)
                    DatePicker("To", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                if window.endMinute <= window.startMinute {
                    Text("The end has to be after the start.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding<Date>(
            get: {
                let current = store.settings.windows[index]
                let minute = min(start ? current.startMinute : current.endMinute, 23 * 60 + 59)
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                if start {
                    store.settings.windows[index].startMinute = minute
                } else {
                    store.settings.windows[index].endMinute = minute
                }
            }
        )
    }
}

// MARK: - Blocking setup guide

struct BlockingSetupView: View {
    @State private var lastCheck: Date? = GuardLog.lastCheck

    private let steps: [(String, String)] = [
        ("Open the Shortcuts app", "Go to the Automation tab and tap + (New Automation)."),
        ("Choose \"App\"", "Pick the apps to block - Instagram, TikTok, Snapchat, YouTube, any you like. Tick \"Is Opened\" and choose \"Run Immediately\". On iOS 16: turn off \"Ask Before Running\" at the end instead."),
        ("Add the first action", "Tap \"New Blank Automation\", then Add Action. Search for Lockin and choose \"Focus Minutes Left\"."),
        ("Add an If", "Add the action \"If\". Set it to: Focus Minutes Left - is greater than - 0."),
        ("Add the shield", "Search for Lockin again, choose \"Show Lockin Shield\" and drag it between If and Otherwise. Leave Otherwise empty."),
        ("Tap Done and test it", "Start a focus session in Lockin, then open one of the blocked apps. You land right back here."),
    ]

    var body: some View {
        List {
            Section {
                Text("While a focus block runs, opening a blocked app sends you straight back to Lockin. Outside focus time the apps work normally.")
                    .font(.subheadline)
                Text("This uses an automation in Apple's Shortcuts app. You set it up once, it takes about two minutes.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section("Steps") {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.0)
                                .font(.subheadline.weight(.semibold))
                            Text(step.1)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            }

            Section {
                HStack {
                    Image(systemName: lastCheck == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundColor(lastCheck == nil ? Color.secondary : Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastCheck == nil ? "Not connected yet" : "Automation is working")
                            .font(.subheadline.weight(.semibold))
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Good to know: someone determined can switch the automation off in Shortcuts. Strict mode and the blocked-attempts counter are there to make that a conscious choice.")
            }
        }
        .navigationTitle("App blocking")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            lastCheck = GuardLog.lastCheck
        }
    }

    private var statusDetail: String {
        guard let lastCheck = lastCheck else {
            return "Open a blocked app once after setting it up, then come back here."
        }
        return "Last check: \(Format.dayAndTime(lastCheck))"
    }
}
