import AppIntents
import Foundation

/// Small log shared between the Shortcuts actions and the UI.
enum GuardLog {
    private static let lastCheckKey = "guard.lastCheck"
    private static let hitsKey = "guard.hits"
    private static let shieldKey = "guard.shieldRequested"

    /// The automation asked "is a focus block running?".
    static func recordCheck() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
    }

    /// The automation sent the user back to Lockin: one blocked attempt.
    static func recordHit() {
        var hits = UserDefaults.standard.array(forKey: hitsKey) as? [Double] ?? []
        hits.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(Array(hits.suffix(500)), forKey: hitsKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: shieldKey)
    }

    static var lastCheck: Date? {
        let value = UserDefaults.standard.double(forKey: lastCheckKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    static func hits(lastDays days: Int) -> Int {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86_400
        let hits = UserDefaults.standard.array(forKey: hitsKey) as? [Double] ?? []
        return hits.filter { $0 >= cutoff }.count
    }

    /// True once, right after the shield action sent the user here.
    static func consumeShieldRequest() -> Bool {
        let value = UserDefaults.standard.double(forKey: shieldKey)
        guard value > 0 else { return false }
        UserDefaults.standard.removeObject(forKey: shieldKey)
        return Date().timeIntervalSince1970 - value < 30
    }
}

/// Shortcuts action 1: how many minutes of focus are left (0 = no block running).
struct FocusMinutesLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "Focus Minutes Left"
    static var description = IntentDescription(
        "Gives the minutes left in the Lockin focus block that is running right now. Gives 0 when no block is running."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        GuardLog.recordCheck()
        let data = Persistence.load()
        let minutes = FocusGuard.minutesLeft(in: data.blocks, at: Date())
        return .result(value: minutes)
    }
}

/// Shortcuts action 2: leave the distracting app and show the Lockin focus screen.
struct ShowShieldIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Lockin Shield"
    static var description = IntentDescription(
        "Opens Lockin on its focus screen. Use it inside an If block after Focus Minutes Left."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        GuardLog.recordHit()
        return .result()
    }
}
