# Premium (soft paywall)

## The rules

| | Free | Premium |
|---|---|---|
| Solo bosses | 1 unfinished at a time (finished ones don't count) | Unlimited |
| Boss looks for new raids | 3: Clock, Dragon, Goblin | All 12 |
| Create a group raid (multiplayer) | — | ✓ |
| Join someone else's raid by code | ✓ unlimited | ✓ unlimited |
| Everything else (focus, widgets, Live Activity, report, Game Center) | ✓ | ✓ |

The rule lives in one place: `PlanLimits` in GameCore (unit tested). Change
`PlanLimits.freeActiveSoloRaids` to adjust the free limit.

Boss looks: the look comes from the boss's name (`BossKind.forName` in DDDesign), so the gate is
on the name when creating. `BossKind.freeKinds` / `isFree` (DDDesign) lists the free looks, and
`PlanLimits.check(bossIsFree:plan:)` (GameCore, which can't see `BossKind`) is the rule. A name
without a keyword ("Q3 Taxes") always maps to one of the free looks, so a custom name never needs
Premium; a name with a Premium keyword ("Kraken", "Website" → spider) does. Only creating is gated:
joined raids and existing bosses keep their look, and widgets, Live Activity and teammates show
every look.

## Where the paywall shows

It's a **soft** paywall: it can always be dismissed with "Not now", and nobody loses access to
existing bosses or history.

- **Create sheet ("New boss…"):** when a limit applies, a notice at the top says why ("Free plan:
  1 active solo boss") with a "See Premium" button. Tapping Create anyway opens the paywall.
- **Mode picker:** on the free plan the segment reads "Raid · Premium" ("Raid" at accessibility
  sizes) and is always tappable; choosing it stays on Solo and opens the paywall. A footnote says
  group raids come with Premium and joining stays free.
- **Boss looks:** on the free plan the boss grid shows a lock on the 9 Premium looks (VoiceOver:
  "Premium"); tapping one opens the paywall and keeps the name. The dice only rolls free looks. A
  typed Premium name ("Kraken") shows a lock on the thumbnail and a note, and Create opens the
  paywall ("Free raids can fight the Clock, Dragon or Goblin. Premium unlocks all 12 bosses.").
- **Party tab → Premium:** "See Premium" (free) or "Manage subscription" (Premium).

The paywall uses Apple's `SubscriptionStoreView` (prices, free trial, Restore Purchases), with
the themed benefits as its header. If the store can't load (offline, another storefront,
products not set up yet), the paywall still explains Premium and says purchases aren't
available right now.

## Products

| Product ID | Type | Price (suggested) | Notes |
|---|---|---|---|
| `dd.premium.yearly` | Auto-renewable, 1 year | 19.99 | 1-week free trial |
| `dd.premium.monthly` | Auto-renewable, 1 month | 2.99 | |

Both are in the subscription group **Premium** (local test ID `21512345`). Family Sharing is on.
IDs are in `DungeonsAndDeadlines/App/Entitlements.swift`.

### App Store Connect

1. Create the subscription group "Premium" and the two subscriptions above.
2. Replace `Entitlements.subscriptionGroupID` with the real group ID (used by "Manage subscription").
3. Add the paid-apps agreement, tax and banking info, or products won't load in TestFlight.

### Local testing (simulator)

- `Config/Products.storekit` has both products. The shared scheme points to it in the Run and
  Test actions. If plans don't load when running from Xcode, select it in
  **Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration**.
  Then purchases, renewals and refunds can be tested in **Debug → StoreKit → Manage Transactions**.
- Launch arguments: `-premium` acts as a subscriber (no StoreKit needed), and `-showPaywall`
  opens the paywall on launch.
- The `xcodebuild` test runs on this Mac didn't load the StoreKit file (the paywall showed its
  "unavailable" state), so actual purchases haven't been verified yet.
