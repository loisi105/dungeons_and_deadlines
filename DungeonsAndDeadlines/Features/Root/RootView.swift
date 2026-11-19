import SwiftUI
import SwiftData
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
        .fontDesign(.serif)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        // Game Center sign-in waits until onboarding is done, so its sheet doesn't
        // interrupt the first screen.
        .task(id: nickname.isEmpty) {
            if !nickname.isEmpty { environment.gameCenter.authenticate() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: environment.didBecomeActive()
            case .background: environment.didEnterBackground()
            default: break
            }
        }
        .alert("Focus paused", isPresented: $environment.pausedByBackground) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You were away for more than 2 minutes, so your focus timer paused when you left. Resume it from the timer.")
        }
    }

    /// The raid stored as current, or the newest unfinished one.
    private var selectedRaid: RaidRecord? {
        if let id = UUID(uuidString: currentRaidID), let raid = raids.first(where: { $0.id == id }) { return raid }
        return raids.first { $0.status == .active || $0.status == .planning }
    }
}
