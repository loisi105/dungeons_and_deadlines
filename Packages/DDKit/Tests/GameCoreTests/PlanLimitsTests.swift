import Foundation
import Testing
@testable import GameCore

@Suite("Plan limits")
struct PlanLimitsTests {
    func raid(_ status: RaidStatus, multiplayer: Bool = false, owner: String = "me") -> Raid {
        Raid(name: "R", bossName: "B", ownerID: owner, createdAt: .now, deadline: .now, status: status, isMultiplayer: multiplayer)
    }

    @Test("Free: first solo boss is fine, a second unfinished one is blocked")
    func soloLimit() {
        #expect(PlanLimits.check(createMultiplayer: false, plan: .free, raids: [], playerID: "me") == nil)
        #expect(PlanLimits.check(createMultiplayer: false, plan: .free, raids: [raid(.active)], playerID: "me") == .soloLimitReached)
        #expect(PlanLimits.check(createMultiplayer: false, plan: .free, raids: [raid(.planning)], playerID: "me") == .soloLimitReached)
    }

    @Test("Finished bosses, joined raids and other people's raids don't count")
    func whatCounts() {
        let raids = [raid(.won), raid(.lost), raid(.active, multiplayer: true), raid(.active, multiplayer: true, owner: "friend")]
        #expect(PlanLimits.check(createMultiplayer: false, plan: .free, raids: raids, playerID: "me") == nil)
    }

    @Test("Free can't create multiplayer raids; Premium can do anything")
    func multiplayer() {
        #expect(PlanLimits.check(createMultiplayer: true, plan: .free, raids: [], playerID: "me") == .multiplayerRequiresPremium)
        #expect(PlanLimits.check(createMultiplayer: true, plan: .premium, raids: [raid(.active)], playerID: "me") == nil)
        #expect(PlanLimits.check(createMultiplayer: false, plan: .premium, raids: [raid(.active), raid(.active)], playerID: "me") == nil)
    }
}
