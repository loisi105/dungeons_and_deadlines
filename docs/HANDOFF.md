# Handoff

Last updated: 2026-11-19. Read this first, then [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for milestone details.

## TL;DR

- **Committed on `main`:** M0–M4 plus the art-style "Theme" milestone. The solo game, focus timer, Live Activity, Control Center toggle, Siri shortcuts, widgets and the pixel-art theme all build and pass their tests.
- **Uncommitted in the working tree:** M5 (damage meter and fake teammates). It's nearly done; see [Finish M5](#1-finish-m5-uncommitted).
- **Not started:** Game Center (GameKit), M6 (multiplayer over Firebase REST), M7 (full report). Drafts for all three are in [`docs/handoff/drafts/`](handoff/drafts).
- **Rule from the user:** commit after each milestone.

## Commits so far

| Commit | Milestone |
|---|---|
| `864486d` | M0–M2: Xcode project, DDKit package, GameCore rules, local solo game |
| `1a5c2d1` | (Nico) Layered icon art in `docs/icon/` — the art-style reference |
| `2a6e7e9` | M3: focus timer, tab-bar timer accessory, Live Activity, Control Center toggle, App Shortcuts |
| `c003ebc` | Theme: pixel-fantasy art style from the icon art, 12 bosses, faster launch (Firebase SDK removed) |
| `b502342` | M4: Home Screen, Lock Screen and StandBy widgets |

## Decisions that changed since the plan docs

| Topic | Plan said | Now |
|---|---|---|
| Toolchain | Xcode 26 | Built with **Xcode 27.2**, iOS 27.2 simulator. Deployment target is still **iOS 26.0**. |
| Firebase | iOS SDK | **REST, no SDK.** The SDK added ~1.4 s to every launch (measured: app code starts at 1.75 s with it vs 0.32 s without). Same Firebase project, Auth, Firestore and security rules. Teammates' changes arrive by polling (~5 s) while a raid screen is open. The user chose this. |
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
  App/                         entry, AppEnvironment (+ LaunchOptions), Announcer, AppShortcuts
  Features/                    Root, Boss, Tasks, Focus, Raid, Meter*, Debug*, Report
  Sync/SyncEngine.swift        STUB until M6 (isAvailable = false)
DDWidgets/                     widget extension: BossWidget, FocusLiveActivity, FocusControl
DungeonsAndDeadlinesUITests/   SmokeTests (flows + accessibility audits), LaunchPerformanceTests
Packages/DDKit/                GameCore, DDPersistence, DDIntents, DDDesign (+ tests)
  Sources/DDDesign/Art/        PixelArt, PixelPainter, Bosses, IconArt.generated.swift
  Sources/DDDesign/Theme/      Theme colors, RPGButtonStyle, PixelShapes, BossAvatar, SwordSlash
Config/                        entitlements, Info.plists (not compiled)
tools/                         svg2grid.py (icon SVG → Swift grids), make_icon.py (icon + launch image)
firebase/                      firestore.rules, rules tests, emulator config, setup README
docs/                          README-level docs, GAME_CENTER.md, handoff/drafts/
(* = uncommitted)
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
- Package tests (49) run on macOS: GameCore 27, persistence 11, intents 5, design and art 6 (including the paint-speed check).
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
| `-meterAsList` | Damage meter opens in list mode |
| `-useFirebaseEmulator` | (M6) Use the local emulator |

Example: check a screen at the largest text size:

```bash
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
```

```bash
xcrun simctl launch booted com.dungeonsanddeadlines.app -uiTesting -seedDemo -startTab raid
```

## Next steps, in order

### 1. Finish M5 (uncommitted)

Done in the working tree:
- Meter tab (`Features/Meter/MeterView.swift`): Swift Charts with a custom legend and `accessibilityChartDescriptor`, a list mode (forced at accessibility sizes, where the Chart/List switch is hidden), and an "Attacking now" section.
- `Features/Debug/FakeTeammates.swift` and `DebugSection.swift` (Raid tab, debug builds, solo raids only).
- All `Section("…")` titles became explicit `header: { Text(…).font(.headline) }`.
- Page background is now plain (vignette only; see gotchas). Boss name uses `.title` and wraps.
- New UI test `testDamageMeterWithFakeTeammates` stops the fakes before auditing.

Left to do:
1. Run the UI tests. The last change (the audit skips elements overlapping the tab bar or the focus accessory) **was not verified**, because the run was stopped. The previous run's only failure was "Attacking now" sitting under the accessory.
2. Commit as `M5: damage meter and fake teammates`.

### 2. Game Center (GameKit)

Drafts are in `docs/handoff/drafts/GameKit/`, with the design in [GAME_CENTER.md](GAME_CENTER.md).
1. Move `PlayerProgress.swift` into `Packages/DDKit/Sources/GameCore/` and the tests into `Tests/GameCoreTests/`.
2. The draft reads `report.attacks`, so add `public var attacks: [Attack]` to `RaidReport` (raid attacks only) and fill it in `Titles.report`.
3. Add `GameCenterService.swift` to `DungeonsAndDeadlines/App/`, create it in `AppEnvironment`, and inject it into the environment.
4. Add the `com.apple.developer.game-center` entitlement (`true`) to `Config/DungeonsAndDeadlines.entitlements`.
5. Call `authenticate()` once onboarding is done (RootView, when the nickname is set). Call `syncProgress()` from `didBecomeActive` and, debounced, from `GameActions.onChange`.
6. Show the Access Point on WelcomeView and the Raid tab (`onAppear`/`onDisappear` → `showAccessPoint`). Add a "Game Center" section to RaidView with Achievements and Leaderboards buttons.
7. Keep it off in `-uiTesting`; the service already checks `isEnabled`. Audit the new section.
8. `GKAccessPoint.trigger(state:)` may be deprecated on iOS 26+. If the build warns, switch to the newer API.

### 3. M6: multiplayer over Firebase REST

- **Drafts:**
  - `docs/handoff/drafts/M6/FirebaseREST.swift`: config from `GoogleService-Info.plist`, anonymous Auth via `accounts:signUp` and token refresh, refresh token in the Keychain, and a Firestore client with typed values, `commit` (preconditions, server timestamps, array append) and `runQuery`.
  - `SyncEngine.SDK-reference.swift` is the **old SDK-based** engine. Reuse its structure and field mappings, not its Firebase calls.
- **Firestore schema:** README "Decisions" and IMPLEMENTATION_PLAN Appendix C.
- **Rules:** `firebase/firestore.rules`; tests in `firebase/rules-tests/`. Node and the Firebase CLI aren't installed on this Mac, so the rules tests have never run.
- **Mapping each operation to REST:**

| Operation | REST call | Notes |
|---|---|---|
| Publish raid | One `commit` writing `raids/{id}` and `inviteCodes/{code}` with `mustNotExist` | `FAILED_PRECONDITION` means the code is taken; retry up to 5 times with a new code |
| Join | `get inviteCodes/{code}` → `commit` with `appendToArray("memberIDs", [uid])` → `get raids/{id}` | `PERMISSION_DENIED` means the raid is full or closed |
| Upload an attack | `commit`, `mustNotExist`, `serverTimeFields: ["serverCreatedAt"]` | `FAILED_PRECONDITION`/`ALREADY_EXISTS` means it already landed: mark synced |
| Upload tasks/members | `commit` with a `mask` | Add `updatedAt` with `serverTimeFields` |
| Poll (foreground, ~5 s, current raid only) | `get raids/{id}`; `runQuery` for `attacks` by `serverCreatedAt > cursor`, `tasks` and `members` by `updatedAt > cursor` | Store the cursors per raid |
| Merge | `RaidStore.mergeRemote(...)` (already written and tested) | Then `settleOutcome`, reload widgets, sync the Live Activity |

- **Error handling:** `PERMISSION_DENIED` → drop the item (it will never succeed). Anything else → keep it pending and retry with backoff.
- **UI to enable:** in `CreateRaidView` and `JoinRaidView`, `sync.isAvailable` gates multiplayer and `publish`/`join` are already called. `WelcomeView` shows Join only when sync is available.
- **Tests:** a sync integration test against the emulator (two stores converge), as the plan describes.
- **Launch:** don't do network work before the first frame. Start sign-in in a `Task` after launch.

### 4. M7: end-of-raid report

The draft is `docs/handoff/drafts/M7/ReportView.swift`, a full themed report (HP chart with audio-graph descriptor, member cards with titles, late and open tasks, share as image plus text). Replace the simple `Features/Report/ReportView.swift` with it, apply `.dungeonScreen()`/`.dungeonRow()`, and add a UI test that finishes a raid and audits the report. The win/lose transition (`settleOutcome`) and `Titles` are already done and tested in GameCore.

### 5. Docs

Update `docs/ARCHITECTURE.md` and `docs/IMPLEMENTATION_PLAN.md` with the table in [Decisions that changed](#decisions-that-changed-since-the-plan-docs), or link to this file.

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
