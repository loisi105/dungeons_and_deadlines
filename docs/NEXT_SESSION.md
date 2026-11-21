# Plan for the next session

State on 2026-11-21: everything is committed on `main` (not pushed). The full UI suite passes
(15 of 15) and the package tests pass (`cd Packages/DDKit && swift test`).

## Ground rules

- Use a separate DerivedData for any `xcodebuild` (`-derivedDataPath build/DerivedData`; `./build.sh`
  does). Running into the default folder locked the user's Xcode build database.
- One simulator at a time. iPhone sim `887F97A2-CE25-47A1-9E54-35A21B973338` (iPhone 18 Pro), iPad sim
  `105B33E3-B0BD-42A5-B91A-CDEF8D2F1995` (iPad Pro 11-inch). Screenshots lag a few seconds after a tap.
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for every command-line build.
- Commit only your own files with explicit `git add`. Ask before pushing.
- To see an audit failure: run the test with `-resultBundlePath`, then
  `xcrun xcresulttool export attachments`; the element screenshot names the culprit.

## Open items, in priority order

1. **Push** the 7 local commits (plus the two older unpushed ones, `0a8fa4d` and `5020306`).
2. **Look at it on the iPad and iPhone** (nothing was checked on the user's devices):
   - Sign in with Apple in Settings → Account, and a two-device raid. Firebase itself is set up and
     verified by REST calls (Anonymous auth, Firestore, rules). The Apple provider must be enabled in
     the Firebase console and the capability present on the app target.
   - The iPad task sheet with a long form while scrolling, and the iPad "Deadline" text clip on the
     11-inch Boss tab (pre-existing since `e0e6c30`).
   - All five attack animations by eye (`-slowMotion`): mage orb, tank shield, rogue daggers, healer
     beam and cross; no class = sword slash (checked in the simulator: the swing and slash show).
     Also a 3-task batch, a focus session ending, and `-fakeTeammates`.
3. **Family Controls (Distribution)**: the user must request it at
   https://developer.apple.com/contact/request/family-controls-distribution for the app,
   `.focusmonitor` and `.shieldconfig`. Without it TestFlight/App Store builds can't use Screen Time
   blocking.
4. **App Store Connect**: create the 2 subscriptions and 29 achievements with the new IDs
   (`docs/MONETIZATION.md`, `docs/GAME_CENTER.md`), upload `docs/appstore/subscription-image.png`,
   replace `Entitlements.subscriptionGroupID` (`21512345` is a placeholder) and the placeholder app ID in
   `Config/Products.storekit`.
5. **In-app Achievements screen** (offered, not built): all 29 with progress from
   `PlayerProgress.achievements`, hidden ones as "???". Works without App Store Connect.
6. **Download all of a player's raids after Sign in with Apple** on a new phone (today only the current
   raid syncs). Also: rules tests need Node and the Firebase CLI (never run).
7. Smaller: `docs/GAME_CENTER.md` still says the Access Point floats on the Raid tab; polish pass never
   covered iPad or AX5; delete the test document `raids/rulescheck-*` in the Firestore console.
8. The user once saw "invalid reuse after initialization failure" building for their iPad; it could not be
   reproduced (simulator, generic device and Release builds are clean). Ask for the file and line if it
   returns.

## Gotchas learned

- `List(selection:)` clears the selection when edit mode switches; set it afterwards.
- A `Binding` that reads a SwiftData record, passed to a pushed `NavigationLink` destination, froze the app
  at 100% CPU. Copy the value into `@State`. Don't fetch from the store inside `body` either.
- `.presentationSizing(.form)` is right for iPad sheets; skip detents there. The size class inside an iPad
  sheet is compact, so test `UIDevice.current.userInterfaceIdiom`.
- `defaultVisibility(.hidden, for: .tabBar)` did not hide a `TabSection` from the iPad top bar.
- App icon: image-name specializations in `icon.json` were ignored by `ictool`; two background layers
  switched with `hidden-specializations` work.
- The accessibility audit reports icon-and-title list buttons (`Label`) as possibly clipped even though they
  wrap (verified at AX3); the audit helper in `SmokeTests.swift` exempts the two known labels.
