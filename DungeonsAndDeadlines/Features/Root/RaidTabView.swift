import SwiftUI
import SwiftData
import GameCore
import DDPersistence

/// The game: Liquid Glass tab bar over the Boss, Tasks and Raid tabs.
struct RaidTabView: View {
    let raidID: UUID

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
            Tab("Boss", systemImage: "lizard.fill", value: TabID.boss) {
                BossView(raidID: raidID, showTasks: { selection = .tasks })
            }
            Tab("Tasks", systemImage: "checklist", value: TabID.tasks) {
                TasksView(raidID: raidID)
            }
            Tab("Raid", systemImage: "person.3.fill", value: TabID.raid) {
                RaidView(raidID: raidID)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
