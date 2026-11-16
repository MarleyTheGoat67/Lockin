import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text("Welcome to Lockin")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Know what you have to do, when you will do it, and actually do it.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 32)

                    OnboardingPoint(
                        symbol: "checklist",
                        title: "Add your tasks",
                        text: "Say how hard each one is, how long it takes and when it is due."
                    )
                    OnboardingPoint(
                        symbol: "calendar",
                        title: "Lockin plans your calendar",
                        text: "Focus blocks are placed in your free hours before each deadline, hardest first. Miss one and it is planned again."
                    )
                    OnboardingPoint(
                        symbol: "bell.badge.fill",
                        title: "You get a notification",
                        text: "When a block starts, shortly before, and when it is over."
                    )
                    OnboardingPoint(
                        symbol: "lock.shield.fill",
                        title: "Social media is blocked",
                        text: "During a focus block, distracting apps send you back here. Set this up once in the Me tab."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Button {
                NotificationManager.requestPermission { _ in
                    store.settings.onboardingDone = true
                    dismiss()
                }
            } label: {
                Text("Allow notifications and start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled()
    }
}

private struct OnboardingPoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
