import Foundation

/// Free vs Premium. Premium unlocks creating multiplayer raids, unlimited solo bosses
/// and every boss look.
public enum Plan: String, Sendable {
    case free, premium
}

/// What the free tier allows. Joining other people's raids is always free and unlimited.
public enum PlanLimits {
    /// Unfinished (planning or fighting) solo bosses a free player can have at once.
    /// Finished bosses don't count, so the free tier never locks anyone out of their history.
    public static let freeActiveSoloRaids = 1

    public enum Block: String, Sendable, Equatable {
        /// Creating a multiplayer raid needs Premium.
        case multiplayerRequiresPremium
        /// A free player already has an unfinished solo boss.
        case soloLimitReached
        /// A free player picked a boss look that needs Premium.
        case premiumBoss
    }

    /// Nil if the player may create this raid; otherwise why not.
    public static func check(createMultiplayer: Bool, plan: Plan, raids: [Raid], playerID: String) -> Block? {
        guard plan == .free else { return nil }
        if createMultiplayer { return .multiplayerRequiresPremium }
        return activeSoloRaids(raids, playerID: playerID) >= freeActiveSoloRaids ? .soloLimitReached : nil
    }

    /// Nil if the player may create a raid with this boss look; otherwise why not.
    /// Which looks are free is `BossKind.isFree` in DDDesign (Clock, Dragon, Goblin), which
    /// GameCore can't see. Only creating is gated: joining a raid or keeping a boss is always free.
    public static func check(bossIsFree: Bool, plan: Plan) -> Block? {
        plan == .free && !bossIsFree ? .premiumBoss : nil
    }

    /// Solo raids this player owns that aren't finished.
    public static func activeSoloRaids(_ raids: [Raid], playerID: String) -> Int {
        raids.filter { !$0.isMultiplayer && $0.ownerID == playerID && ($0.status == .planning || $0.status == .active) }.count
    }
}
