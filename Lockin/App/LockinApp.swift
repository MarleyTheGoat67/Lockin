import SwiftUI
import UserNotifications

@main
struct LockinApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var router = AppRouter()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationManager.registerCategories()
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
