import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Int = min(max(UserDefaults.standard.integer(forKey: "startTab"), 0), 3)
    @State private var showOnboarding: Bool = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(1)
            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .fullScreenCover(item: $router.focus) { presentation in
            FocusView(blockID: presentation.id, fromShield: presentation.fromShield)
                .environmentObject(store)
                .environmentObject(router)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(store)
        }
        .onReceive(timer) { _ in
            store.tick()
            if GuardLog.consumeShieldRequest() {
                showFocusIfRunning(fromShield: true)
            }
        }
        .onChange(of: store.activeBlockID) { newValue in
            if newValue != nil {
                showFocusIfRunning(fromShield: false)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.refresh()
                showFocusIfRunning(fromShield: GuardLog.consumeShieldRequest())
            }
        }
        .onAppear {
            if !store.settings.onboardingDone {
                showOnboarding = true
            } else {
                showFocusIfRunning(fromShield: false)
            }
        }
    }

    private func showFocusIfRunning(fromShield: Bool) {
        guard let block = store.activeBlock else { return }
        if let current = router.focus, current.id == block.id {
            if fromShield && !current.fromShield {
                router.focus = FocusPresentation(id: block.id, fromShield: true)
            }
            return
        }
        router.focus = FocusPresentation(id: block.id, fromShield: fromShield)
    }
}
