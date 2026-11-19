import Foundation

/// Free vs Premium. Premium unlocks creating multiplayer raids and unlimited solo bosses.
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
    }

    /// Nil if the player may create this raid; otherwise why not.
    public static func check(createMultiplayer: Bool, plan: Plan, raids: [Raid], playerID: String) -> Block? {
        guard plan == .free else { return nil }
        if createMultiplayer { return .multiplayerRequiresPremium }
        return activeSoloRaids(raids, playerID: playerID) >= freeActiveSoloRaids ? .soloLimitReached : nil
    }

    /// Solo raids this player owns that aren't finished.
    public static func activeSoloRaids(_ raids: [Raid], playerID: String) -> Int {
        raids.filter { !$0.isMultiplayer && $0.ownerID == playerID && ($0.status == .planning || $0.status == .active) }.count
    }
}
