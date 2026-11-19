import SwiftUI
import SwiftData
import GameCore
import DDPersistence

/// The game: Liquid Glass tab bar over the Boss, Tasks and Raid tabs.
struct RaidTabView: View {
    let raidID: UUID

    @Query private var raids: [RaidRecord]
    @State private var showFocus = false
    #if DEBUG
    @Environment(FakeTeammates.self) private var fakeTeammates
    #endif

    init(raidID: UUID) {
        self.raidID = raidID
    }

    private var isFighting: Bool { raids.first { $0.id == raidID }?.status == .active }

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment
        TabView(selection: $environment.selectedTab) {
            Tab("Boss", systemImage: "flame.fill", value: AppTab.boss) {
                BossView(raidID: raidID, showTasks: { environment.selectedTab = .tasks }).id(raidID)
            }
            Tab("Tasks", systemImage: "scroll.fill", value: AppTab.tasks) {
                TasksView(raidID: raidID).id(raidID)
            }
            Tab("Meter", systemImage: "chart.bar.fill", value: AppTab.meter) {
                MeterView(raidID: raidID).id(raidID)
            }
            Tab("Raid", systemImage: "person.3.fill", value: AppTab.raid) {
                RaidView(raidID: raidID).id(raidID)
            }
        }
        .tabBarMinimizeBehavior(.never) // the tab bar stays put while scrolling
        .modifier(FocusAccessoryModifier(enabled: isFighting) {
            FocusTimerAccessory(raidID: raidID) { showFocus = true }.id(raidID)
        })
        .sheet(isPresented: $showFocus) { FocusView(raidID: raidID) }
        #if DEBUG
        .task(id: isFighting) {
            if isFighting, fakeTeammates.autoStart, !fakeTeammates.isRunning { fakeTeammates.start(raidID: raidID) }
        }
        #endif
    }
}

/// Shows the focus mini-player above the tab bar only while the fight is on.
private struct FocusAccessoryModifier<Accessory: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let accessory: () -> Accessory

    func body(content: Content) -> some View {
        if enabled {
            content.tabViewBottomAccessory { accessory() }
        } else {
            content
        }
    }
}
