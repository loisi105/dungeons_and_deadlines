import AppIntents
import WidgetKit
import GameCore
import DDPersistence
import DDIntents

/// Lets people pick which raid a widget shows (defaults to the current raid).
struct SelectRaidIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Raid"
    static let description = IntentDescription("Pick the boss this widget shows.")

    @Parameter(title: "Raid")
    var raid: RaidEntity?

    init() {}
}

struct BossEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: BossSnapshot?

    static let preview = BossEntry(
        date: .now,
        snapshot: BossSnapshot(
            raidID: UUID(), raidName: "Thesis", bossName: "Exam Dragon",
            startedAt: .now.addingTimeInterval(-86_400 * 4),
            deadline: .now.addingTimeInterval(86_400 * 3),
            state: BossState(maxHP: 1000, currentHP: 410, phase: .enraged, outcome: .ongoing, totalDamage: 590, memberStats: []),
            openTasks: [
                .init(id: UUID(), title: "Write conclusion", sizeLetter: "M", damage: 150),
                .init(id: UUID(), title: "Fix citations", sizeLetter: "S", damage: 50),
                .init(id: UUID(), title: "Final read-through", sizeLetter: "S", damage: 50),
            ],
            canComplete: true
        )
    )
}

struct BossTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BossEntry { .preview }

    func snapshot(for configuration: SelectRaidIntent, in context: Context) async -> BossEntry {
        if context.isPreview { return .preview }
        return await Self.entry(raidID: configuration.raid?.id, at: .now)
    }

    func timeline(for configuration: SelectRaidIntent, in context: Context) async -> Timeline<BossEntry> {
        let now = Date()
        let first = await Self.entry(raidID: configuration.raid?.id, at: now)
        guard let snapshot = first.snapshot, snapshot.state.outcome == .ongoing else {
            return Timeline(entries: [first], policy: .after(now.addingTimeInterval(3600)))
        }
        // One entry per upcoming phase change and at the deadline, so the boss
        // gets angrier on time even when the app isn't running.
        var entries = [first]
        for date in snapshot.refreshDates(after: now) {
            entries.append(await Self.entry(raidID: snapshot.raidID, at: date))
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800)))
    }

    static func entry(raidID: UUID?, at date: Date) async -> BossEntry {
        await MainActor.run { BossEntry(date: date, snapshot: BossSnapshot.make(raidID: raidID, at: date)) }
    }
}
