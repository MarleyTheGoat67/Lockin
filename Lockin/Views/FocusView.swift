import SwiftUI

/// Full-screen view shown while a focus block is running, and right after it ends.
struct FocusView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: AppRouter
    let blockID: UUID
    var fromShield: Bool = false

    @State private var confirmEnd: Bool = false

    private var cameFromBlockedApp: Bool {
        fromShield || (router.focus?.fromShield ?? false)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.11, blue: 0.36), Color(red: 0.03, green: 0.03, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            TimelineView(.periodic(from: Date(), by: 1)) { context in
                screen(now: context.date)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("End this session early?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) {
                store.endEarly(blockID)
                close()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The minutes you worked so far are counted. The rest is planned again.")
        }
    }

    private func close() {
        router.focus = nil
    }

    @ViewBuilder
    private func screen(now: Date) -> some View {
        if let block = store.block(blockID), block.status == .planned {
            if now < block.end {
                running(block, now: now)
            } else {
                finished(block)
            }
        } else {
            ended
        }
    }

    // MARK: - Running

    private func running(_ block: FocusBlock, now: Date) -> some View {
        let total = max(1, block.end.timeIntervalSince(block.start))
        let left = max(0, block.end.timeIntervalSince(now))
        let fraction = min(1, max(0, 1 - left / total))

        return VStack(spacing: 20) {
            HStack {
                Button {
                    close()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Hide focus screen")
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("Social media blocked")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }

            if cameFromBlockedApp {
                Text("Nice try. That app stays closed until \(Format.time(block.end)).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(clock(left))
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text("until \(Format.time(block.end))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(width: 260, height: 260)

            VStack(spacing: 6) {
                Text(store.title(for: block))
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                if let task = store.task(block.taskID) {
                    Text("\(Format.duration(task.remainingMinutes)) left on this task - \(lowercasedFirst(Format.deadline(task.deadline, now: now)))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    store.setDone(block.taskID, done: true)
                    close()
                } label: {
                    Label("I finished the whole task", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundColor(Color(red: 0.13, green: 0.11, blue: 0.36))
                        .background(Color.white)
                        .clipShape(Capsule())
                }

                if store.settings.strictMode {
                    HoldButton(title: "Hold 8 seconds to end early", seconds: 8) {
                        store.endEarly(blockID)
                        close()
                    }
                } else {
                    Button {
                        confirmEnd = true
                    } label: {
                        Text("End session early")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Time is up

    private func finished(_ block: FocusBlock) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundColor(.white)
            Text("Session complete")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Did you work on \(store.title(for: block))? Your apps are unlocked again.")
                .font(.body)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                answerButton("Yes, I worked", filled: true) {
                    store.checkIn(block.id, worked: true)
                    close()
                }
                answerButton("Yes - and the task is finished", filled: false) {
                    store.checkIn(block.id, worked: true)
                    store.setDone(block.taskID, done: true)
                    close()
                }
                answerButton("No, plan it again", filled: false) {
                    store.checkIn(block.id, worked: false)
                    close()
                }
            }
        }
    }

    private func answerButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(filled ? Color(red: 0.13, green: 0.11, blue: 0.36) : Color.white)
                .background(filled ? Color.white : Color.white.opacity(0.14))
                .clipShape(Capsule())
        }
    }

    // MARK: - Nothing running any more

    private var ended: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "lock.open.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
            Text("No focus block running")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
            Text("Your apps are unlocked.")
                .foregroundColor(.white.opacity(0.75))
            Spacer(minLength: 0)
            answerButton("Close", filled: true) {
                close()
            }
        }
    }
}

/// A button that only fires after being held down. Used in strict mode.
struct HoldButton: View {
    let title: String
    let seconds: Double
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Color.white.opacity(0.12)
            GeometryReader { geometry in
                Color.white.opacity(0.28)
                    .frame(width: geometry.size.width * progress)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
        }
        .frame(height: 48)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: seconds, maximumDistance: 80, perform: {
            progress = 0
            action()
        }, onPressingChanged: { pressing in
            withAnimation(.linear(duration: pressing ? seconds : 0.2)) {
                progress = pressing ? 1 : 0
            }
        })
        .accessibilityLabel(title)
    }
}
