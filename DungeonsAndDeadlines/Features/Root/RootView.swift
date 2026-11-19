import SwiftUI
import SwiftData
import DDPersistence

/// Decides between onboarding, the raid picker and the game tabs.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("identity.nickname", store: AppGroup.defaults) private var nickname = ""
    @AppStorage("identity.currentRaidID", store: AppGroup.defaults) private var currentRaidID = ""
    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var raids: [RaidRecord]

    var body: some View {
        @Bindable var environment = environment
        Group {
            if nickname.isEmpty {
                OnboardingView()
            } else if let raid = selectedRaid {
                RaidTabView(raidID: raid.id)
                    .id(raid.id)
            } else {
                WelcomeView()
            }
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
