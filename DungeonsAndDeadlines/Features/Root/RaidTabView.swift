import SwiftUI
import SwiftData
import GameCore
import DDPersistence

/// The game: Liquid Glass tabs (bottom bar on iPhone, top bar or sidebar on iPad)
/// over the Boss, Tasks, Meter and Party tabs, plus a Bosses section in the iPad sidebar.
struct RaidTabView: View {
    let raidID: UUID

    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var raids: [RaidRecord]
    @State private var showFocus = false
    #if DEBUG
    @Environment(FakeTeammates.self) private var fakeTeammates
    #endif

    init(raidID: UUID) {
        self.raidID = raidID
    }

    private var isFighting: Bool { raids.first { $0.id == raidID }?.status == .active }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            // iPad sidebar: every boss, one tap to switch. Only in regular width, so the
            // iPhone tab bar keeps its four tabs (the Boss tab's switcher covers the same).
            if horizontalSizeClass == .regular {
                TabSection("Bosses") {
                    ForEach(raids) { raid in
                        Tab(raid.bossName, systemImage: raid.id == raidID ? "flame.fill" : "flame", value: AppTab.bossItem(raid.id)) {
                            BossView(raidID: raid.id).id(raid.id)
                        }
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.never) // the tab bar stays put while scrolling
        .onChange(of: environment.selectedTab) { _, tab in
            // Picking a boss in the sidebar makes it the current boss and shows its Boss tab.
            if case .bossItem(let id) = tab {
                LocalIdentity.currentRaidID = id
                environment.selectedTab = .boss
            }
        }
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
