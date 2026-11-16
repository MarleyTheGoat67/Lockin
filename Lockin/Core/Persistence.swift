import Foundation

/// Reads and writes the single JSON file that holds all app data.
/// Also used by the Shortcuts actions, which run without the UI.
enum Persistence {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lockin", isDirectory: true)
            .appendingPathComponent("data.json")
    }

    static func load(from url: URL = Persistence.fileURL) -> AppData {
        guard let raw = try? Data(contentsOf: url) else { return AppData() }
        return (try? JSONDecoder().decode(AppData.self, from: raw)) ?? AppData()
    }

    @discardableResult
    static func save(_ data: AppData, to url: URL = Persistence.fileURL) -> Bool {
        let encoder = JSONEncoder()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let raw = try encoder.encode(data)
            try raw.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// Answers "should social media be blocked right now?".
enum FocusGuard {
    static func activeBlock(in blocks: [FocusBlock], at now: Date) -> FocusBlock? {
        blocks
            .filter { $0.isActive(at: now) }
            .min { $0.end < $1.end }
    }

    /// Whole minutes left in the running focus block, rounded up. 0 when none is running.
    static func minutesLeft(in blocks: [FocusBlock], at now: Date) -> Int {
        guard let block = activeBlock(in: blocks, at: now) else { return 0 }
        return max(1, Int((block.end.timeIntervalSince(now) / 60).rounded(.up)))
    }
}
