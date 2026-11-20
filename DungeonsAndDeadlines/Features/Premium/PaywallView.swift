import StoreKit
import SwiftUI
import GameCore
import DDDesign

/// Soft paywall: explains what Premium adds and can always be dismissed (the close X).
/// Purchasing uses Apple's native SubscriptionStoreView (prices, trial, restore).
struct PaywallView: View {
    /// Why the paywall appeared; nil when opened from the Party tab.
    let reason: PlanLimits.Block?

    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    /// nil while loading; false when the store can't offer the subscription right now.
    @State private var storeAvailable: Bool?

    var body: some View {
        NavigationStack {
            Group {
                if storeAvailable == true {
                    SubscriptionStoreView(productIDs: Entitlements.productIDs) {
                        header
                    }
                    .subscriptionStoreControlStyle(.prominentPicker)
                    .subscriptionStoreButtonLabel(.multiline)
                    .storeButton(.visible, for: .restorePurchases)
                    .storeButton(.hidden, for: .cancellation)
                    .containerBackground(Theme.parchment, for: .subscriptionStore)
                    .onInAppPurchaseCompletion { _, _ in
                        await entitlements.refresh()
                        if entitlements.isPremium { dismiss() }
                    }
                } else {
                    // Offline, another storefront, or products not set up yet: still explain Premium.
                    ScrollView {
                        VStack(spacing: 16) {
                            header
                            if storeAvailable == false {
                                Text("Purchases aren't available right now. Check your connection and try again later.")
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.readableSecondary)
                                    .dungeonPanel()
                                    .padding(.horizontal)
                            } else {
                                ProgressView("Loading plans…")
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(DungeonBackground())
            .fontDesign(.serif)
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton(identifier: "paywallNotNow")
        }
        // Page-size sheet on iPad, so the whole paywall fits instead of a cramped form sheet.
        .presentationSizing(.page)
        .task {
            let products = (try? await Product.products(for: Entitlements.productIDs)) ?? []
            storeAvailable = !products.isEmpty
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            BossAvatar(bossName: "Deadline Clock", phase: .enraged)
            Text("Dungeons & Deadlines Premium")
                .font(.title.weight(.black))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let reason {
                Text(reasonText(reason))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.readableSecondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                benefit("person.3.fill", "Raid with up to 4 friends", "Create group raids and share an invite code.")
                benefit("rectangle.stack.fill", "Unlimited solo bosses", "Fight several deadlines at once.")
                benefit("square.grid.3x3.fill", "All \(BossKind.allCases.count) bosses", "Krakens, liches, mimics and more. The Clock, Dragon and Goblin are free.")
                benefit("heart.fill", "Support the party", "Keep new bosses and features coming.")
                Text("Joining a friend's raid is always free.")
                    .readableFootnote()
            }
            .padding()
            .dungeonPanel()
        }
        .padding()
    }

    private func reasonText(_ reason: PlanLimits.Block) -> String {
        switch reason {
        case .multiplayerRequiresPremium:
            String(localized: "Creating a group raid is a Premium feature.")
        case .soloLimitReached:
            String(localized: "The free plan has \(PlanLimits.freeActiveSoloRaids) active solo boss at a time. Finish it, or go Premium for more.")
        case .premiumBoss:
            String(localized: "Free raids can fight the Clock, Dragon or Goblin. Premium unlocks all \(BossKind.allCases.count) bosses.")
        }
    }

    private func benefit(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        // Plain wrapping text (no Label/HStack), so nothing clips at large sizes.
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Image(systemName: symbol)) \(Text(title))")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(title)). \(Text(detail))"))
    }
}
