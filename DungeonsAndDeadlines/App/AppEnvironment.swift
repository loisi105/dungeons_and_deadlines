import SwiftUI
import DDPersistence
import DDIntents
import GameCore

/// Launch arguments used by UI tests and debugging.
enum LaunchOptions {
    /// In-memory store and a fresh identity, so every UI test starts clean.
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    /// Starts the FakeTeammate simulation as soon as a solo raid is active.
    static var fakeTeammates: Bool { ProcessInfo.processInfo.arguments.contains("-fakeTeammates") }
    /// Connects Firebase to the local Emulator Suite instead of the cloud project.
    static var useFirebaseEmulator: Bool { ProcessInfo.processInfo.arguments.contains("-useFirebaseEmulator") }

    /// Seeds a solo raid mid-fight, for screenshots and manual accessibility checks.
    static var seedDemo: Bool { ProcessInfo.processInfo.arguments.contains("-seedDemo") }
    /// `-meterAsList` opens the damage meter in list mode (screenshots).
    static var meterAsList: Bool { ProcessInfo.processInfo.arguments.contains("-meterAsList") }

    @MainActor
    static func applyBeforeLaunch() {
        defer {
            if seedDemo { seedDemoRaid() }
            if meterAsList { AppGroup.defaults.set(true, forKey: "settings.meterAsList") }
        }
        guard isUITesting else { return }
        let defaults = AppGroup.defaults
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("identity.") || key.hasPrefix("settings.") {
            defaults.removeObject(forKey: key)
        }
        if let container = try? SharedContainer.make(inMemory: true) {
            DDStore.use(RaidStore(container: container))
        }
    }
}

extension LaunchOptions {
    @MainActor
    static func seedDemoRaid() {
        let store = DDStore.shared
        guard store.raids().isEmpty else { return }
        LocalIdentity.setNickname("Ada")
        let me = LocalIdentity.current
        guard let raid = try? store.createRaid(
            name: "Thesis", bossName: "Exam Dragon",
            deadline: Date.now.addingTimeInterval(86_400 * 5), multiplayer: false, owner: me, role: .mage
        ) else { return }
        let titles: [(String, TaskSize)] = [("Outline", .s), ("Literature review", .l), ("Draft chapter 1", .m), ("Fix citations", .s)]
        let tasks = titles.compactMap { try? store.addTask(raidID: raid.id, title: $0.0, size: $0.1) }
        try? store.startFight(raid.id, by: me.memberID)
        if let first = tasks.first { try? store.completeTask(first.id, by: me.memberID) }
    }
}

/// App-wide services, created once at launch and injected through the environment.
@MainActor
@Observable
final class AppEnvironment {
    let announcer = Announcer()
    let sync = SyncEngine()
    let gameCenter = GameCenterService()
    #if DEBUG
    let fakeTeammates = FakeTeammates()
    #endif

    var store: RaidStore { DDStore.shared }

    func bootstrap() {
        sync.configure()
        GameActions.onChange = { [sync, gameCenter] raidID in
            sync.scheduleFlush(raidID: raidID)
            gameCenter.scheduleSync()
        }
        #if DEBUG
        fakeTeammates.autoStart = LaunchOptions.fakeTeammates
        #endif
    }

    /// Runs when the app returns to the foreground: applies the focus background rule
    /// and refreshes everything that may have changed while away.
    func didBecomeActive() {
        let me = LocalIdentity.current
        if (try? store.resumeFocusFromBackground(memberID: me.memberID)) == true {
            announcer.announce(String(localized: "Focus paused because you left the app for more than 2 minutes."), important: true)
            pausedByBackground = true
        }
        if let raid = store.currentRaid() { try? store.settleOutcome(raid.id) }
        #if os(iOS)
        LiveActivityController.reconcile()
        #endif
        GameActions.reloadSystemSurfaces()
        sync.appDidBecomeActive()
        gameCenter.scheduleSync()
    }

    func didEnterBackground() {
        try? store.markFocusBackgrounded(memberID: LocalIdentity.current.memberID)
        sync.appDidEnterBackground()
    }

    /// Shown once as an alert after the background rule paused a session.
    var pausedByBackground = false
}
