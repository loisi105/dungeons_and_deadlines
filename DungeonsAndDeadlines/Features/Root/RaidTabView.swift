import SwiftUI
import SwiftData
import GameCore
import DDPersistence

/// The game: Liquid Glass tab bar over the Boss, Tasks and Raid tabs.
struct RaidTabView: View {
    let raidID: UUID

    @Query private var raids: [RaidRecord]
    @State private var showFocus = false

    init(raidID: UUID) {
        self.raidID = raidID
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
    }

    private var isFighting: Bool { raids.first?.status == .active }

    enum TabID: Hashable { case boss, tasks, raid }
    @State private var selection: TabID = Self.initialTab

    /// `-startTab tasks|raid` opens a specific tab (screenshots, manual checks).
    private static var initialTab: TabID {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-startTab"), i + 1 < args.count else { return .boss }
        switch args[i + 1] {
        case "tasks": return .tasks
        case "raid": return .raid
        default: return .boss
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Boss", systemImage: "flame.fill", value: TabID.boss) {
                BossView(raidID: raidID, showTasks: { selection = .tasks })
            }
            Tab("Tasks", systemImage: "scroll.fill", value: TabID.tasks) {
                TasksView(raidID: raidID)
            }
            Tab("Raid", systemImage: "person.3.fill", value: TabID.raid) {
                RaidView(raidID: raidID)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(FocusAccessoryModifier(enabled: isFighting) {
            FocusTimerAccessory(raidID: raidID) { showFocus = true }
        })
        .sheet(isPresented: $showFocus) { FocusView(raidID: raidID) }
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
