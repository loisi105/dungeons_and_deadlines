import StoreKit
import SwiftUI
import GameCore

/// Premium status from StoreKit 2. Premium unlocks creating multiplayer raids,
/// unlimited solo bosses and all 12 boss looks; everything else (including joining raids) is free.
///
/// Products are set up in App Store Connect (docs/MONETIZATION.md) and, for local
/// testing, in Config/Products.storekit (selected in the scheme's Run action).
@MainActor
@Observable
final class Entitlements {
    static let subscriptionGroupID = "21512345"
    static let productIDs = ["dd.premium.yearly", "dd.premium.monthly"]

    private(set) var isPremium = false
    var plan: Plan { isPremium ? .premium : .free }

    private var updates: Task<Void, Never>?

    func start() {
        if LaunchOptions.forcePremium {
            isPremium = true
            return
        }
        // Purchases made elsewhere (other devices, Ask to Buy, renewals) arrive here.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !LaunchOptions.forcePremium else { return }
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    /// Nil if the player may create this raid; otherwise the reason to show the paywall.
    func block(createMultiplayer: Bool, raids: [Raid], playerID: String) -> PlanLimits.Block? {
        PlanLimits.check(createMultiplayer: createMultiplayer, plan: plan, raids: raids, playerID: playerID)
    }

    /// Nil if the player may create a raid with this boss look (`BossKind.isFree`); otherwise `.premiumBoss`.
    func block(bossIsFree: Bool) -> PlanLimits.Block? {
        PlanLimits.check(bossIsFree: bossIsFree, plan: plan)
    }
}
