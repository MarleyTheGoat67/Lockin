import SwiftUI
import UserNotifications

@main
struct LockinApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var router = AppRouter()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationManager.registerCategories()

        // Launch arguments used by the simulator demo: -demoData YES [-demoFocus YES] [-startTab 0...3]
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "demoData") {
            Store.shared.seedDemoData(startFocus: defaults.bool(forKey: "demoFocus"))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
        }
    }
}

/// Lets any screen open the full-screen focus view.
final class AppRouter: ObservableObject {
    @Published var focus: FocusPresentation?
}

struct FocusPresentation: Identifiable, Equatable {
    let id: UUID
    var fromShield: Bool = false
}
