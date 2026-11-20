import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDDesign

/// Decides between onboarding, the raid picker and the game tabs.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("identity.nickname", store: AppGroup.defaults) private var nickname = ""
    @AppStorage("identity.currentRaidID", store: AppGroup.defaults) private var currentRaidID = ""
    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var raids: [RaidRecord]
    @State private var debugPaywall = LaunchOptions.showPaywall

    var body: some View {
        @Bindable var environment = environment
        Group {
            if nickname.isEmpty {
                OnboardingView()
            } else if let raid = selectedRaid {
                RaidTabView(raidID: raid.id)
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $debugPaywall) { PaywallView(reason: .soloLimitReached) }
        .sheet(isPresented: $environment.showCreateRaid) { CreateRaidView() }
        .fontDesign(.serif)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        // Game Center sign-in waits until onboarding is done, so its sheet doesn't
        // interrupt the first screen.
        .task(id: nickname.isEmpty) {
            if !nickname.isEmpty { environment.gameCenter.authenticate() }
        }
        .onAppear { KeyboardDismissal.shared.install() }
        // The one hook for phase alerts: any change to a raid's fight (start, end, deadline,
        // phase shift, delete), whether made here, by an intent or merged from sync.
        .onChange(of: phaseAlertKeys, initial: true) {
            environment.phaseNotifications.setNeedsReschedule()
        }
        // Ask for notification permission when a fight starts (or resumes) while the app is on
        // screen: from the Boss tab, the start-fight prompt in Tasks, or the leader's start
        // merged from sync. Scheduling itself never prompts.
        .onChange(of: raidStatuses) { old, new in
            guard scenePhase == .active else { return }
            // A raid that was already known and not running, now active. A raid that just
            // appeared (joined mid-fight, first sync) doesn't count.
            let started = new.contains { entry in
                guard entry.value == .active, let before = old[entry.key] else { return false }
                return before != .active
            }
            guard started else { return }
            Task {
                await environment.phaseNotifications.requestAuthorizationIfNeeded()
                environment.phaseNotifications.setNeedsReschedule()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                KeyboardDismissal.shared.install()
                environment.didBecomeActive()
            case .background: environment.didEnterBackground()
            default: break
            }
        }
    }

    /// What phase alerts depend on, per raid.
    private var phaseAlertKeys: [PhaseNotifications.Key] { raids.map { PhaseNotifications.Key($0.model) } }

    /// Each raid's status, to notice a fight starting.
    private var raidStatuses: [UUID: RaidStatus] {
        Dictionary(raids.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
    }

    /// The raid stored as current, or the newest unfinished one.
    private var selectedRaid: RaidRecord? {
        if let id = UUID(uuidString: currentRaidID), let raid = raids.first(where: { $0.id == id }) { return raid }
        return raids.first { $0.status == .active || $0.status == .planning }
    }
}
