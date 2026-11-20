# Handoff

Last updated: 2026-11-19 (after M7). Read this first, then [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for milestone details.

## TL;DR

- **Done and committed on `main`:** M0–M7, the pixel-art theme, Game Center, a boss switcher, one-tap task completion, a soft paywall ([MONETIZATION.md](MONETIZATION.md)), follow-up fights after the deadline, deleting old bosses, class attack animations, keyboard dismissal, and an iPad layout (sidebar, two-column boss, large widget).
  - Solo and multiplayer raids (multiplayer uses Firebase over REST).
  - Focus timer, Live Activity, Control Center toggle, Siri shortcuts, widgets.
  - Damage meter, end-of-raid report, achievements and leaderboards.
- **Tests:** all 65 package tests and all 8 UI flows (each with accessibility audits) pass.
- **What's left:** setup that needs accounts (Firebase project, App Store Connect, a signing team), checks that need a person or the simulator tool, and the M8 stretch goals. See [What's left](#whats-left).
- **Rule from the user:** commit after each milestone.
- **Devices:** an iPhone 17 and an iPad mini (A17 Pro) are used for testing; both build and sign under the FH team.

## Commits

| Commit | Milestone |
|---|---|
| `864486d` | M0–M2: Xcode project, DDKit package, GameCore rules, local solo game |
| `1a5c2d1` | (Nico) Layered icon art in `docs/icon/`, the art-style reference |
| `2a6e7e9` | M3: focus timer, tab-bar timer accessory, Live Activity, Control Center toggle, App Shortcuts |
| `c003ebc` | Theme: pixel-fantasy art style from the icon art, 12 bosses, faster launch (Firebase SDK removed) |
| `b502342` | M4: Home Screen, Lock Screen and StandBy widgets |
| `ea1f943`, `83344e6` | M5: damage meter, fake teammates |
| `0cef81b` | Game Center: sign-in, achievements, leaderboards, Access Point |
| `14a73cd` | M6: multiplayer raids over Firebase REST (DDSync target) |
| `ec6c24c` | M7: end-of-raid report with titles |
| `a381a11` | Tasks: one-tap checkbox, completing during planning asks to start the fight, no double hits |
| `78c6445` | Boss switcher on the Boss and Tasks tabs |
| `0737c4c` | Soft paywall: free = 1 active solo boss, Premium = group raids + unlimited bosses (StoreKit 2) |

### Since the paywall

| Commit | Change |
|---|---|
| `fdf1660` | Device builds: `at.fhooe.sail` bundle IDs, FH team signing |
| `83597b3` | Tapping outside a text field hides the keyboard (app-wide) |
| `36bc772` | Fix: paywall from the Party tab closed right after opening |
| `7d88739` | Tab bar stays fixed while scrolling |
| `8e0afae` | Follow-up tasks after a win/loss and "Resume the fight"; native close buttons |
| `1905eff` | Delete old solo bosses (frees the free-plan slot) |
| `3269e3d` | Completing a task jumps to the boss and plays a class attack |
| `e0e6c30` | iPad: sidebar with Bosses, two-column Boss tab, readable list widths, large widget |
| `c8800a8` + next | Screen Time: "Block apps while focusing" (shield core, DeviceActivity safety net, shield screen, settings UI). See [Screen Time blocking](#screen-time-blocking). |

## Decisions that changed since the plan docs

| Topic | Plan said | Now |
|---|---|---|
| Toolchain | Xcode 26 | Built with **Xcode 27.2**, iOS 27.2 simulator. Deployment target is still **iOS 26.0**. |
| Firebase | iOS SDK | **REST, no SDK.** The SDK added ~1.4 s to every launch (measured: app code starts at 1.75 s with it vs 0.32 s without). Same Firebase project, Auth, Firestore and security rules. Teammates' changes arrive by polling the current raid every 5 s while the app is in the foreground. The user chose this. Code: `Packages/DDKit/Sources/DDSync`. |
| Store | `@ModelActor RaidStore` | `@MainActor RaidStore` on `mainContext`, so `@Query` views see writes immediately. |
| Intents from widgets/controls | Write locally, sync later | Write intents also conform to `LiveActivityIntent`, so iOS runs them **in the app process**. The app's store, Live Activity and sync all see the change at once. |
| Art style | SF Symbol placeholders | **Pixel fantasy, taken from Nico's icon layers** (`docs/icon/*.svg`): 64×64 grids, one-pixel dark outline, three-tone shading, cream/gold/night-purple palette. The user wanted the remote art used as the style reference. |
| App icon | — | Background + boss layers only. **No sword** (the user asked). Built by `tools/make_icon.py`. |
| Liquid Glass | Glass buttons | System chrome stays Liquid Glass (tab bar, toolbars, sheets, timer accessory). In-content actions use the pixel `RPGButtonStyle`. |
| Game Center | Not planned | **The user asked for GameKit** ("better Apple support"): sign-in, achievements, leaderboards, Access Point. Raids stay on Firebase. |
| Tabs | Boss, Tasks, Meter, Raid | Same, with flavor titles: Tasks → "Quest Log", Raid → "Party", Meter → "Meter". |

## Repo map

```
DungeonsAndDeadlines/          app (MainActor default isolation)
  App/                         entry, AppEnvironment (+ LaunchOptions), Announcer, AppShortcuts, GameCenterService
  Features/                    Root, Boss, Tasks, Focus, Raid, Meter, Debug, Report
  Sync/SyncEngine.swift        sign-in, debounced uploads, foreground polling (wraps DDSync.RaidSync)
DDWidgets/                     widget extension: BossWidget, FocusLiveActivity, FocusControl
DDFocusMonitor/                DeviceActivity monitor extension: lifts the Screen Time shield when the safety net ends
DDShieldConfig/                shield configuration extension: the screen shown over a blocked app
DungeonsAndDeadlinesUITests/   SmokeTests (flows + accessibility audits), LaunchPerformanceTests
Packages/DDKit/                GameCore, DDPersistence, DDIntents, DDDesign, DDSync, DDScreenTime (+ tests)
  Sources/DDDesign/Art/        PixelArt, PixelPainter, Bosses, IconArt.generated.swift
  Sources/DDDesign/Theme/      Theme colors, RPGButtonStyle, PixelShapes, BossAvatar, SwordSlash
Config/                        entitlements, Info.plists (not compiled)
tools/                         svg2grid.py (icon SVG → Swift grids), make_icon.py (icon + launch image)
firebase/                      firestore.rules, rules tests, emulator config, setup README
docs/                          ARCHITECTURE, IMPLEMENTATION_PLAN, GAME_CENTER, HANDOFF, icon/
```

## Build and test

`xcode-select` on this Mac points at the Command Line Tools, so set `DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

```bash
./build.sh build -quiet
```

```bash
./build.sh test -skip-testing:DungeonsAndDeadlinesUITests/LaunchPerformanceTests
```

```bash
cd Packages/DDKit && swift test
```

- `build.sh` uses the **iPhone 18 Pro** simulator (override with `SIMULATOR=...`) and keeps derived data and packages in `build/` (git-ignored).
- `xcodebuild -quiet` prints a harmless `error: the following command failed with exit code 0`. Ignore it.
- Package tests (65) run on macOS: GameCore 34, persistence 11, intents 5, design and art 6 (including the paint-speed check), sync 9 (two-player flows against an in-memory fake Firestore).
- UI tests (8): onboarding, solo plan → fight → hit (checkbox and swipe), focus timer with backgrounding, meter with fake teammates, victory report, switching bosses, free-plan paywall, plus an on-demand launch metric.
- The UI tests write each audit issue as a line starting with `AUDIT [...]`. Find them with `grep AUDIT build/test.log`.
- To dump the boss art as PNGs for review: `DD_DUMP_ART=/some/dir swift test --filter DDDesignTests` (writes `sheet.png`).
- The iOS Simulator MCP tool won't attach until the user runs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Until then, use `xcrun simctl` (install, launch, `io screenshot`) as this session did.

### Launch arguments (debug/testing)

| Argument | Effect |
|---|---|
| `-uiTesting` | In-memory store, fresh identity, no Firebase/Game Center |
| `-seedDemo` | Solo raid "Thesis" vs "Exam Dragon", 4 tasks, fight started, one task done |
| `-startTab boss\|tasks\|meter\|raid` | Opens that tab |
| `-fakeTeammates` | Starts 3 simulated teammates once a solo fight is active |
| `-seedFinished` | A won 4-player raid with a late task and an undone task (report) |
| `-meterAsList` | Damage meter opens in list mode |
| `-premium` | Acts as a Premium subscriber |
| `-showPaywall` | Opens the paywall on launch |
| `-slowMotion` | (debug) Plays the task attack 5× slower, for reviewing it |
| `-useFirebaseEmulator` | Use the local Firebase emulator (works without `GoogleService-Info.plist`) |

Example: check a screen at the largest text size:

```bash
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
```

```bash
xcrun simctl launch booted at.fhooe.sail.dungeonsanddeadlines -uiTesting -seedDemo -startTab raid
```

## What's left

### Setup that needs accounts (the user's decision and credentials)

1. **Firebase project.** Create it, enable Anonymous Auth and Firestore, put `GoogleService-Info.plist` into `DungeonsAndDeadlines/Resources/` (git-ignored), and deploy `firebase/firestore.rules`. See [firebase/README.md](../firebase/README.md).
2. **Rules tests and an emulator session.** These have never run, because Node and the Firebase CLI aren't installed on this Mac. Run `cd firebase/rules-tests && npm install && npm test`, then try two simulators with `-useFirebaseEmulator`. The sync logic itself is covered by the fake-Firestore tests.
3. **Game Center.** Create the IDs in App Store Connect ([GAME_CENTER.md](GAME_CENTER.md)).
4. **Premium.** Create the subscription group and products in App Store Connect ([MONETIZATION.md](MONETIZATION.md)). Check that the local StoreKit file loads when running from Xcode, and try a purchase.
5. **Screen Time (Family Controls) for TestFlight/App Store.** Development builds can use the
   `com.apple.developer.family-controls` entitlement right away (paid team, automatic signing).
   Distribution needs Apple's approval: submit the Family Controls entitlement request
   (https://developer.apple.com/contact/request/family-controls-distribution, signed in as the
   team's Account Holder) **once per bundle ID**: the app, `…dungeonsanddeadlines.focusmonitor` and
   `…dungeonsanddeadlines.shieldconfig`. Reported wait: one to several weeks. Until then, archive
   builds fail to provision (or ship without blocking, if the capability is removed for that build).
6. **Signing:** done. Team **FH OO Studienbetriebs GmbH** (`UBQ8UHSHKQ`), automatic signing. IDs: app `at.fhooe.sail.dungeonsanddeadlines`, widgets `…dungeonsanddeadlines.widgets`, UI tests `…dungeonsanddeadlines.uitests`, App Group `group.at.fhooe.sail.dungeonsanddeadlines`. Device builds sign and provision. If `codesign` fails with `errSecInternalComponent` when building from a terminal, allow keychain access to the signing key (or build from Xcode).

### M8 stretch (pick by time left)

See [IMPLEMENTATION_PLAN.md, M8](IMPLEMENTATION_PLAN.md#m8-stretch-pick-by-time-left):
- push updates for teammates' hits on the Lock Screen (needs a Cloud Function and an APNs key)
- notifications
- Sign in with Apple linking
- peer confirmation of tasks
- cosmetics
- taunts

Also possible:
- Game Center friend invites to raids
- more bosses (add a `paintX()` in `Bosses.swift` plus a name keyword)

### Known limitations

- Leaving a raid deletes your member document, but you stay in `memberIDs`, because the rules don't allow removing yourself there.
- Teammates' hits reach your phone only while the app is open (polling). Closed-app updates are the M8 push item above.
- Phase alerts are scheduled locally on each phone, so on teammates' phones they only update when the app polls or opens. If the leader changes the boss's mood, or the boss dies, while a teammate's app is in the background, an outdated alert can still fire there.

## Screen Time blocking

"Block apps while focusing" shields the apps, categories and websites the player picks while a
focus timer **runs**. Pausing or stopping lifts it.

- **Where the shield follows the timer:** `GameActions.changed()` calls `FocusShield.reconcile()`
  (DDIntents) after every change, so the app buttons, the timer accessory, the Live Activity, the
  Control Center control and Siri (all `LiveActivityIntent`s, so they run in the app process) are
  covered in one place. The app also re-checks at launch and on becoming active.
- **Rules** (`GameCore.FocusShieldPlan`, unit-tested): on only if the setting is on, something is
  picked and the timer is running; ends at the daily focus cap (`DamageConfig.dailyFocusCapMinutes`,
  180) or midnight, whichever is first.
- **Safety net:** each time the shield goes up, a one-off DeviceActivity schedule `focusSafetyNet`
  is started that ends at the same moment (at least 15 minutes long, Apple's minimum). Its
  `intervalDidEnd` runs in `DDFocusMonitor` and clears the shield even if the app was killed.
- **Real Screen Time code** lives in the `DDScreenTime` package target (named
  `ManagedSettingsStore` "dungeonsFocus", the saved `FamilyActivitySelection` in
  `AppGroup.defaults`, authorization). DDIntents only knows the `FocusShielding` protocol;
  `FocusShield.shielder` is nil in package tests, widgets and `-uiTesting`, so those never ask for
  authorization or touch shields.
- **Settings:** Party tab → You → "Block apps while focusing" (asks for Screen Time access the first
  time it's turned on) and "Apps to block". The focus timer sheet has a one-line shortcut.
- **No Premium gate.** Blocking is free. Gating it would be one check in `FocusBlocking.turnOn()`
  plus a paywall reason, if wanted.

### Testing it on the iPhone 17 / iPad mini

Shields don't apply in the Simulator, so this needs a device (Developer Mode on, built from Xcode
with the FH team so the development Family Controls entitlement is in the profile):

1. Party tab → turn on **Block apps while focusing** → allow Screen Time access (Face ID / passcode)
   → pick e.g. Instagram (or the Social category) → Done.
2. Start a focus timer, go Home, open Instagram: the pixel shield shows "<boss> is still standing"
   and **Back to the fight** (closes Instagram).
3. Pause from the Live Activity or the Dynamic Island → Instagram opens. Resume → blocked again.
4. Stop from Control Center (or say "Stop focus in Dungeons and Deadlines") → unblocked.
5. Safety net: start a timer, then swipe the app away in the app switcher. Instagram stays blocked
   (the timer is still running). To see the safety net fire without waiting for the cap, temporarily
   set `dailyFocusCapMinutes` low (e.g. 16) in `DamageConfig.standard`, start a timer, kill the app,
   and check that Instagram opens again after ~16 minutes. Revert the change afterwards.
6. Turn the setting off while a timer runs → unblocked at once. Revoke access in Settings → Screen
   Time → Apps with Screen Time access → the Party tab shows the "access is off" note.

## Not verified yet

These need a person (or the simulator tool once `xcode-select` is fixed):
- Widgets on a real Home Screen and Lock Screen, including tinted and clear modes
- The Live Activity and Dynamic Island while focus runs
- The Control Center / Lock Screen control and the Action button
- Siri / Shortcuts phrases
- Running on a physical device. The signed device build succeeds, but the phone needs Developer Mode turned on before it can install.
- Screen Time blocking on a device (see [Testing it on the iPhone 17 / iPad mini](#testing-it-on-the-iphone-17--ipad-mini)): the shield, the shield screen, the safety net after a kill, and whether automatic signing adds the Family Controls entitlement to the extensions' development profiles.

## Gotchas learned the hard way

**Accessibility audits** (`performAccessibilityAudit`; see the comments in `SmokeTests.audit`):
- **The page background is a solid color.** Every gradient or texture behind text eventually measured as low contrast, on iPad most of all.
- **Run the suite on an iPad too:** `SIMULATOR="iPad Pro 13-inch (M5)" ./build.sh test …`. iPad sheets float over the dimmed screen, so findings without an element are skipped there.
- **Text must never sit on texture.** Parchment specks and dungeon bricks made text "fail" contrast, so page backgrounds are plain. Put texture only in framed art.
- **Use solid colors for secondary text** (`Theme.inkSoft` / `.readableSecondary`), not opacity.
- **Notes belong inside list rows, not in section footers** over the custom page background.
- **Rows that switch layout** (`ViewThatFits`, `LabeledContent`) are reported as "Dynamic Type partially unsupported". Prefer one wrapping `Text`, or `dynamicTypeSize.isAccessibilitySize` branches.
- **Medium sheet detents clip content at large sizes.** The focus timer is a full sheet for that reason.
- **Filters in the test, each with a reason:**
  - contrast on button labels (glass and pixel button fills are misread)
  - system keyboard elements
  - toolbar buttons and segmented controls under Dynamic Type
  - elements under the tab bar or focus accessory
  - Dynamic Type on the Raid tab (checked by hand at AX5)
- **`kAXErrorServerNotFound`** is a simulator flake, usually right after changing text size or appearance. Rerun.

**Swift and SwiftUI:**
- GameCore's timer state is `FocusTimerState`, because `FocusState` clashes with SwiftUI.
- `Activity` isn't `Sendable`: look it up inside `nonisolated` functions (see `LiveActivityController`).
- `AppGroup.defaults` must be one shared instance, or `@AppStorage(store:)` misses writes.
- Don't pass a `mutating` call result (like `p.eye()`) straight into another mutating painter call on the same value. Store it in a `let` first.

**Performance:**
- Painter shapes loop only over their bounding box: all 12 bosses paint in ~35 ms (debug).
- Each boss is a lazy `static let`, so it's painted on first use.

**Art pipeline:**
- After changing `docs/icon/*.svg`, run `python3 tools/svg2grid.py` and `python3 tools/make_icon.py`. Don't edit `IconArt.generated.swift` by hand.
