#if DEBUG
import Foundation
import GameCore
import DDPersistence
import DDIntents

/// Simulated teammates for testing raid UI without a backend.
/// Only works in solo raids, so fake hits are never uploaded.
@MainActor
@Observable
final class FakeTeammates {
    static let roster: [(name: String, role: Role)] = [("Mia", .mage), ("Leo", .tank), ("Zoe", .rogue), ("Sam", .healer)]

    private(set) var runningRaidID: UUID?
    /// Set by the `-fakeTeammates` launch argument: start as soon as a solo fight is active.
    var autoStart = false
    var secondsBetweenHits: Double = 4

    private var task: Task<Void, Never>?
    private var store: RaidStore { DDStore.shared }

    var isRunning: Bool { runningRaidID != nil }

    func canRun(in raidID: UUID) -> Bool {
        store.raid(raidID)?.isMultiplayer == false
    }

    func start(raidID: UUID, count: Int = 3) {
        guard canRun(in: raidID) else { return }
        stop()
        for entry in Self.roster.prefix(count) {
            store.mergeRemote(member: Member(id: fakeID(entry.name), raidID: raidID, nickname: entry.name, role: entry.role, joinedAt: .now))
        }
        runningRaidID = raidID
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.secondsBetweenHits ?? 4))
                guard let self, !Task.isCancelled else { return }
                self.tick(raidID)
            }
        }
        GameActions.changed(raidID)
    }

    func stop() {
        task?.cancel()
        task = nil
        if let raidID = runningRaidID {
            for entry in Self.roster {
                try? store.updateMember(raidID: raidID, memberID: fakeID(entry.name)) { $0.activeFocusSince = nil }
            }
            GameActions.changed(raidID)
        }
        runningRaidID = nil
    }

    private func fakeID(_ name: String) -> String { "fake-\(name.lowercased())" }

    private func tick(_ raidID: UUID) {
        guard let raid = store.raid(raidID), raid.status == .active, store.bossState(raidID)?.outcome == .ongoing else {
            stop()
            return
        }
        let fakes = store.members(raidID).filter { $0.id.hasPrefix("fake-") }
        guard let member = fakes.randomElement() else { return }

        let open = store.tasks(raidID).filter { !$0.isDone }
        if Bool.random(), Int.random(in: 0..<3) == 0, let task = open.randomElement() {
            _ = try? store.completeTask(task.id, by: member.id)
        } else {
            // A 5–20 minute focus chunk. Toggle "attacking" so the meter and Live Activity show it.
            let minutes = Int.random(in: 5...20)
            let context = DamageCalculator.Context(
                memberID: member.id, attacks: store.attacks(raidID), memberCount: store.members(raidID).count,
                lockedMaxHP: raid.lockedMaxHP, now: .now
            )
            if let attack = store.calculator.focusAttack(raidID: raidID, seconds: minutes * 60, context: context) {
                try? store.insertAttack(attack, syncState: .synced)
            }
            try? store.updateMember(raidID: raidID, memberID: member.id) { m in
                m.activeFocusSince = m.activeFocusSince == nil ? .now : nil
            }
        }
        GameActions.changed(raidID)
    }
}
#endif
