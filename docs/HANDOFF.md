# Handoff

Last updated: 2026-11-19 (after M7). Read this first, then [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for milestone details.

## TL;DR

- **Done and committed on `main`:** M0–M7 plus the pixel-art theme and Game Center.
  - Solo and multiplayer raids (multiplayer uses Firebase over REST).
  - Focus timer, Live Activity, Control Center toggle, Siri shortcuts, widgets.
  - Damage meter, end-of-raid report, achievements and leaderboards.
- **Tests:** all 62 package tests and all 6 UI flows (each with accessibility audits) pass.
- **What's left:** setup that needs accounts (Firebase project, App Store Connect, a signing team), checks that need a person or the simulator tool, and the M8 stretch goals. See [What's left](#whats-left).
- **Rule from the user:** commit after each milestone.

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
DungeonsAndDeadlinesUITests/   SmokeTests (flows + accessibility audits), LaunchPerformanceTests
Packages/DDKit/                GameCore, DDPersistence, DDIntents, DDDesign (+ tests)
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
- Package tests (62) run on macOS: GameCore 31, persistence 11, intents 5, design and art 6 (including the paint-speed check), sync 9 (two-player flows against an in-memory fake Firestore).
- UI tests (6): onboarding, solo plan → fight → hit, focus timer with backgrounding, meter with fake teammates, victory report, plus an on-demand launch metric.
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
| `-useFirebaseEmulator` | Use the local Firebase emulator (works without `GoogleService-Info.plist`) |

Example: check a screen at the largest text size:

```bash
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
```

```bash
xcrun simctl launch booted com.dungeonsanddeadlines.app -uiTesting -seedDemo -startTab raid
```

## What's left

### Setup that needs accounts (the user's decision and credentials)

1. **Firebase project.** Create it, enable Anonymous Auth and Firestore, put `GoogleService-Info.plist` into `DungeonsAndDeadlines/Resources/` (git-ignored), and deploy `firebase/firestore.rules`. See [firebase/README.md](../firebase/README.md).
2. **Rules tests and an emulator session.** These have never run, because Node and the Firebase CLI aren't installed on this Mac. Run `cd firebase/rules-tests && npm install && npm test`, then try two simulators with `-useFirebaseEmulator`. The sync logic itself is covered by the fake-Firestore tests.
3. **Game Center.** Create the IDs in App Store Connect ([GAME_CENTER.md](GAME_CENTER.md)).
4. **Signing team.** Set one for the device builds that App Group, Live Activities and Game Center need.

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

## Not verified yet

These need a person (or the simulator tool once `xcode-select` is fixed):
- Widgets on a real Home Screen and Lock Screen, including tinted and clear modes
- The Live Activity and Dynamic Island while focus runs
- The Control Center / Lock Screen control and the Action button
- Siri / Shortcuts phrases
- Anything on a physical device. Signing has no team set; App Group, Live Activities and Game Center need one.

## Gotchas learned the hard way

**Accessibility audits** (`performAccessibilityAudit`; see the comments in `SmokeTests.audit`):
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
