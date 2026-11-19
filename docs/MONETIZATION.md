# Premium (soft paywall)

## The rules

| | Free | Premium |
|---|---|---|
| Solo bosses | 1 unfinished at a time (finished ones don't count) | Unlimited |
| Create a group raid (multiplayer) | — | ✓ |
| Join someone else's raid by code | ✓ unlimited | ✓ unlimited |
| Everything else (focus, widgets, Live Activity, report, Game Center) | ✓ | ✓ |

The rule lives in one place: `PlanLimits` in GameCore (unit tested). Change
`PlanLimits.freeActiveSoloRaids` to adjust the free limit.

## Where the paywall shows

It's a **soft** paywall: it can always be dismissed with "Not now", and nobody loses access to
existing bosses or history.

- **Create sheet ("New boss…"):** when a limit applies, a notice at the top says why ("Free plan:
  1 active solo boss" or "Group raids are Premium") with a "See Premium" button. Tapping
  Create anyway opens the paywall.
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
