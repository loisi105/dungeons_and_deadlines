import Foundation
import SwiftData

/// The App Group shared by the app and the widget extension.
/// Must match `Config/*.entitlements`.
public enum AppGroup {
    public static let identifier = "group.com.dungeonsanddeadlines.app"

    /// One shared instance, so `@AppStorage(store: AppGroup.defaults)` sees every write.
    nonisolated(unsafe) public static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// True when the process has the App Group entitlement (false in `swift test`).
    public static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}

public enum SharedContainer {
    public static let schema = Schema([
        RaidRecord.self, MemberRecord.self, TaskRecord.self, AttackRecord.self, FocusSessionRecord.self,
    ])

    /// One SQLite store in the App Group so widgets, Live Activity and controls read the same data.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("DDStore", schema: schema, isStoredInMemoryOnly: true)
        } else if AppGroup.isAvailable {
            configuration = ModelConfiguration("DDStore", schema: schema, groupContainer: .identifier(AppGroup.identifier))
        } else {
            configuration = ModelConfiguration("DDStore", schema: schema)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

/// The process-wide store. The app, the widget extension and intents all use it.
/// Tests replace it with an in-memory store.
@MainActor
public enum DDStore {
    private static var _shared: RaidStore?

    public static var shared: RaidStore {
        if let _shared { return _shared }
        let container: ModelContainer
        do {
            container = try SharedContainer.make()
        } catch {
            // A broken on-disk store must not crash widgets; fall back to memory.
            container = try! SharedContainer.make(inMemory: true)
        }
        let store = RaidStore(container: container)
        _shared = store
        return store
    }

    public static func use(_ store: RaidStore) {
        _shared = store
    }
}
