# Dungeons & Deadlines — Implementation Plan

Last updated: 2026-11-19
Related: [README](../README.md) (concept and decisions), [ARCHITECTURE.md](ARCHITECTURE.md) (structure and design rules)

> **Current status and the decisions that changed since this plan was written** (Firebase over REST instead of the SDK, Xcode 27, the pixel-art theme, Game Center) are in [HANDOFF.md](HANDOFF.md). Where they disagree, HANDOFF.md wins.

This plan breaks the architecture into milestones M0–M8. Each milestone has a goal, a task checklist with file paths, tests, accessibility checks, its dependencies and a size. Sizes are relative (**S** ≈ a few days for one person, **M** ≈ 1–2 weeks, **L** ≈ 2–3 weeks), since the project's duration isn't set yet.

---

## 0. Ground rules

### Definition of done (applies to every task)
- [ ] Builds without warnings in Swift 6 language mode (strict concurrency)
- [ ] Unit tests for new logic; all tests green
- [ ] Every new screen has previews: default, dark, `.accessibility3` Dynamic Type, right-to-left
- [ ] The UI smoke test reaches the new screen and `performAccessibilityAudit()` passes
- [ ] Manual check with VoiceOver and the largest Dynamic Type size
- [ ] No hard-coded user-facing strings (use String Catalog `Localizable.xcstrings`)
- [ ] Reviewed by one teammate (pull request into `main`)

### Conventions
- **Branches:** `m<N>/<short-topic>` (e.g. `m1/damage-calculator`); squash-merge into `main`.
- **Commits:** imperative mood, one topic each.
- **Code:** SwiftUI + `@Observable`; no singletons except the dependency container built in `App/`; GameCore types are `Sendable` value types.
- **Secrets:** `GoogleService-Info.plist` is not committed; each developer downloads it from the Firebase console (see M6).

### Toolchain
- Xcode 26, iOS 26.0 deployment target, Swift 6 language mode
- Swift Testing for unit tests, XCTest for UI tests (needed for `performAccessibilityAudit()`)
- Firebase iOS SDK via Swift Package Manager (M6)
- Node + Firebase CLI for the emulator and rules tests (M6)

---

## 1. Milestone overview

```
M0 Setup
 └─► M1 GameCore
      └─► M2 Persistence + Intents + Boss/Tasks UI
           ├─► M3 Focus timer + Live Activity + Control  ─┐
           ├─► M4 Widgets                                  ├─► M7 Report + titles ─► M8 Stretch
           └─► M5 FakeTeammate + Meter + Phases ─► M6 Firebase ┘
```

After M2, three tracks can run in parallel: **M3**, **M4** and **M5 → M6**.

| # | Milestone | Size | Depends on |
|---|---|---|---|
| M0 | Project setup | S | — |
| M1 | GameCore rules | M | M0 |
| M2 | Local store, intents, Boss + Tasks UI | L | M1 |
| M3 | Focus timer, Live Activity, Control | L | M2 |
| M4 | Widgets | M | M2 |
| M5 | FakeTeammate, damage meter, phases | M | M2 |
| M6 | Firebase raids + sync | L | M5 |
| M7 | End-of-raid report + titles | M | M5 (M6 for the multiplayer data) |
| M8 | Stretch | — | M6, M7 |

### Suggested team split (up to 5 people)
| Workstream | Owns | Main milestones |
|---|---|---|
| **A: Game rules** | `GameCore`, balancing, titles | M1, M7 |
| **B: Data** | `DDPersistence`, `DDIntents`, sync | M2 (store/intents), M6 |
| **C: App UI** | `Features/`, `DDDesign`, Liquid Glass, touch | M2 (UI), M5, M7 (UI) |
| **D: System surfaces** | `DDWidgets`, Live Activity, Control, App Shortcuts | M3, M4 |
| **E: Quality and backend** | accessibility audits, UI tests, Firebase rules, emulator, CI | all, M6 rules |

With fewer people, merge A+E and B+D.

---

## M0: Project setup (S)

**Goal:** an empty app that builds, runs one unit test and one accessibility audit, with every target and shared container in place.

### Tasks
- [ ] Create Xcode project `DungeonsAndDeadlines` (iOS App, SwiftUI, Swift Testing), deployment target iOS 26.0, Swift 6 language mode.
- [ ] Add a Widget Extension target `DDWidgets` with "Include Live Activity" and "Include Control" checked.
- [ ] Add a UI test target `DungeonsAndDeadlinesUITests`.
- [ ] Turn on capability **App Groups** `group.<bundle-id>` for the app and `DDWidgets`.
- [ ] Info.plist (app): `NSSupportsLiveActivities = YES`.
- [ ] Create local package `Packages/DDKit` (see Appendix A) with targets `GameCore`, `DDPersistence`, `DDIntents`, `DDDesign` and matching test targets; add it to the app and the widget extension.
- [ ] `App/AppEnvironment.swift`: the dependency container (`ModelContainer`, store, later the sync engine), injected via `.environment`.
- [ ] `App/DungeonsAndDeadlinesApp.swift`: an empty `TabView` with the 4 tabs (Boss, Tasks, Meter, Raid) and placeholder views.
- [ ] `Localizable.xcstrings` String Catalog.
- [ ] `.gitignore` for Xcode (`DerivedData`, `xcuserdata`, `GoogleService-Info.plist`).
- [ ] UI test `SmokeTests.testAllTabsPassAccessibilityAudit()`: launches the app, visits each tab, calls `app.performAccessibilityAudit()`.
- [ ] Optional: GitHub Actions workflow running `xcodebuild test` on a macOS runner with Xcode 26.

### Done when
- App launches on an iOS 26 simulator showing 4 tabs with system Liquid Glass tab bar.
- `swift test` in `Packages/DDKit` and `xcodebuild test` both pass.

---

## M1: GameCore (M)

**Goal:** every game rule as pure, tested Swift. No UI, no storage.

### Tasks: models (`GameCore/Models/`)
- [ ] `Raid`: `id`, `name`, `bossName`, `ownerID`, `createdAt`, `deadline`, `startedAt?`, `lockedMaxHP?`, `status` (`.planning`, `.active`, `.won`, `.lost`)
- [ ] `Member`: `id`, `raidID`, `nickname`, `role?`, `joinedAt`
- [ ] `Role`: `.mage` (writer), `.tank` (researcher), `.rogue` (designer), `.healer` (presenter) — flavor only
- [ ] `RaidTask`: `id`, `raidID`, `title`, `size` (`.s/.m/.l`), `assigneeID?`, `createdAt`, `completedAt?`, `completedBy?`; computed `isLate(startedAt:)`
- [ ] `Attack`: `id: UUID`, `raidID`, `memberID`, `kind` (`.task(taskID)` / `.focus(seconds)`), `damage`, `createdAt`, `localDay` (`"yyyy-MM-dd"` in the creating device's time zone, so daily caps come out the same on every device)
- [ ] `FocusSession`: `id`, `raidID`, `memberID`, `state` (`.running/.paused/.stopped`), `startedAt?`, `accumulatedSeconds`, `backgroundedAt?`

### Tasks: rules
- [ ] `DamageConfig` with the defaults in Appendix B
- [ ] `DamageCalculator.damage(for:member:attacksSoFar:config:now:)`
  - task damage = size value × streak multiplier
  - focus damage = minutes (limited by the remaining daily focus cap) × rate × streak multiplier
  - per-member daily cap (raids with ≥2 members only), as a fraction of locked max HP
- [ ] `FocusClock.elapsed(session:now:)` and `FocusClock.handleBackground(session:backgroundedAt:resumedAt:graceSeconds:)`: timestamp-based, with the 120-second grace period
- [ ] `BossEngine.lockHP(tasks:config:) -> Int`: `ceil(sum(task damage) / config.taskShare)`
- [ ] `BossEngine.state(raid:tasks:attacks:now:) -> BossState`: current HP (floored at 0), percent, phase, outcome, per-member `burst`/`sustained` totals
- [ ] `Phase.for(start:deadline:now:)`: thresholds 50% / 25% / 10% time left (Appendix B)
- [ ] `Streaks.current(memberID:attacks:calendar:)`: consecutive `localDay`s with ≥30 focus minutes
- [ ] `Titles.award(state:attacks:tasks:)` (stub returning `[]`; filled in M7)

### Tests (`GameCoreTests`)
- [ ] Task damage per size; streak multipliers 1.0 → 1.1 → 1.2 and capped
- [ ] Focus cap: 200 min in one day yields only 180 min of damage; the next day resets
- [ ] Per-member cap only applies with ≥2 members
- [ ] `lockHP` for 0 tasks (rule: you can't start a fight without at least one task), 1 task, mixed sizes
- [ ] HP never below 0; outcome `.won` at 0 HP, `.lost` after the deadline with HP > 0
- [ ] Phase boundaries exactly at 50 / 25 / 10 %
- [ ] Focus clock: backgrounded 90 s → counts; 300 s → stops counting at `backgroundedAt`
- [ ] Late task detection

### Done when
- `swift test --package-path Packages/DDKit` is green with ≥90% line coverage of `GameCore`.

---

## M2: Local store, intents, Boss + Tasks UI (L)

**Goal:** a complete solo game on one device: create a boss, plan tasks, start the fight, complete tasks, beat the boss. Every action goes through an App Intent.

### Tasks: persistence (`DDPersistence`)
- [ ] SwiftData `@Model` records: `RaidRecord`, `MemberRecord`, `TaskRecord`, `AttackRecord`, `FocusSessionRecord`; each converts to and from its GameCore struct.
- [ ] `syncState` on `AttackRecord` / `TaskRecord` (`.pending`, `.synced`): this is the upload queue (outbox) for M6.
- [ ] `SharedContainer.make(inMemory:)`: `ModelConfiguration(groupContainer: .identifier("group.<bundle-id>"))`.
- [ ] `RaidStore` (`@ModelActor`): `createRaid`, `addTask`, `startFight` (locks HP), `completeTask`, `recordFocus`, `currentRaid`, `bossState(now:)`.
- [ ] Changes made by another process: when the app becomes active, refetch and process SwiftData history so changes made by widget or Control intents appear (see Risks).
- [ ] `LocalIdentity`: generates and stores a local member ID + nickname until Firebase auth exists.

### Tasks: intents (`DDIntents`)
- [ ] `RaidEntity`, `TaskEntity` (`AppEntity` + `EntityQuery` reading from `RaidStore`)
- [ ] `CompleteTaskIntent`, `StartFightIntent`, `OpenRaidIntent`
- [ ] Each intent: calls `RaidStore`, then `WidgetCenter.shared.reloadAllTimelines()`
- [ ] `AppIntentsPackage` conformance in `DDIntents`; the app and the widget extension list it in `includedPackages`

### Tasks: design system (`DDDesign`)
- [ ] `HPBar` (custom drawing + `.accessibilityRepresentation { ProgressView(value:total:) }` with label and value)
- [ ] `PhaseBadge` (SF Symbol + text; never color only)
- [ ] `Haptics` helpers wrapping `.sensoryFeedback`
- [ ] `A11y` helpers: `hpDescription(state:)`, `damageAnnouncement(attack:)`; widgets reuse them
- [ ] Glass usage guide in code comments: content is not glass; controls are glass

### Tasks: UI (`Features/`)
- [ ] **Create raid flow** (sheet with detents): boss name, deadline `DatePicker`, solo or raid toggle (raid disabled until M6)
- [ ] **Tasks tab:** `List` of tasks grouped open/done; `Picker` for size; add with a toolbar `+`; swipe right to complete (`.swipeActions(edge: .leading)`), context menu (complete/edit/assign/delete), drag to reorder; `.accessibilityAction(named: "Complete task")`
- [ ] **Planning state:** shows the predicted HP from current tasks and a **Start fight** button (`.buttonStyle(.glassProminent)`), disabled with an explanation if there are no tasks
- [ ] **Boss tab:** boss art (placeholder SF Symbol / shape), `HPBar`, `PhaseBadge`, deadline countdown, last hits; `.backgroundExtensionEffect()` on the art
- [ ] **Hit feedback:** a damage number floats up and the boss shakes; with Reduce Motion, a crossfade + haptic instead; one VoiceOver announcement per own hit
- [ ] **Win/lose screen:** simple placeholder (full report in M7)
- [ ] `.navigationTransition(.zoom)` from a task row to the task detail

### Tests
- [ ] `DDPersistenceTests` (in-memory container): create → add tasks → start fight locks HP → complete task adds an attack with `syncState = .pending`
- [ ] `DDIntentsTests`: `CompleteTaskIntent.perform()` against an in-memory store; completing twice is a no-op
- [ ] UI test: create raid → add 2 tasks → start → complete both → victory; audit on each screen

### Done when
- One person can beat a boss using only the app, data survives a restart, and "Complete task" also works from Shortcuts.

---

## M3: Focus timer, Live Activity, Control (L)

**Goal:** focus time deals damage, and the running timer is visible and controllable from the Lock Screen, Dynamic Island and Control Center.

### Tasks
- [ ] `DDIntents`: `StartFocusIntent`, `PauseFocusIntent`, `StopFocusIntent` (`LiveActivityIntent` so they work from Live Activity buttons); `ToggleFocusIntent: SetValueIntent` for the control
- [ ] `RaidStore`: focus session start/pause/resume/stop; stopping creates a `.focus` attack via `DamageCalculator` (cap applied)
- [ ] `Features/Focus/FocusTimerModel` (`@Observable`): reads the session from the store; `scenePhase` handling via `FocusClock` (120 s grace period)
- [ ] `Features/Focus/FocusView`: large timer `Text(timerInterval:)`, today's remaining focus cap, controls in a `GlassEffectContainer`; `glassEffectID` morph "Start" → "Pause | Stop"
- [ ] `FocusTimerAccessory` via `.tabViewBottomAccessory`; tapping it opens `FocusView` as a sheet
- [ ] `DDWidgets/FocusLiveActivity`: `ActivityAttributes` (raid, boss name, locked max HP) + `ContentState` (HP, phase, session start or paused-at); Lock Screen view, Dynamic Island compact / minimal / expanded; Pause / Stop buttons
- [ ] `LiveActivityService` (app): start, update and end the activity; also called from intents
- [ ] `DDWidgets/FocusControl`: `StaticControlConfiguration` + `ControlWidgetToggle` bound to `ToggleFocusIntent`
- [ ] App Shortcuts: `AppShortcutsProvider` with phrases for start/stop focus and complete task
- [ ] Accessibility: timer start/stop announcements; Live Activity and control labels via `A11y` helpers; Voice Control `accessibilityInputLabels` on icon buttons

### Tests
- [ ] Store: start → 30 min → stop gives 60 damage; a cap-exceeding session is clipped
- [ ] Focus clock background cases (from M1) through `FocusTimerModel`
- [ ] UI test: start focus, background the app with `XCUIDevice.shared.press(.home)` and reactivate after < 120 s → still running
- [ ] Manual: control in Control Center and on the Lock Screen; Action button; Live Activity buttons; VoiceOver on the Lock Screen

### Done when
- Focus can be started, paused and stopped from the app, the Live Activity, the Control Center control and Siri. Killing the app mid-session loses no time.

---

## M4: Widgets (M)

**Goal:** the boss is visible and tasks can be completed from the Home Screen, Lock Screen and StandBy.

### Tasks (`DDWidgets/`)
- [ ] `BossTimelineProvider`: reads `RaidStore` (App Group); entries for now + phase change times + the deadline
- [ ] `BossWidget` small: boss name, HP ring (`Gauge`), `PhaseBadge`; tap → `OpenRaidIntent`
- [ ] `BossWidget` medium: HP bar + next 3 open tasks, each with `Button(intent: CompleteTaskIntent(task:))`
- [ ] Lock Screen: `.accessoryCircular` (HP gauge), `.accessoryRectangular` (boss + countdown), `.accessoryInline` (`"Dragon 41% · 2d left"`)
- [ ] StandBy: the small widget in full color
- [ ] `.containerBackground(for: .widget)`; `widgetRenderingMode` handling; `.widgetAccentedRenderingMode(.desaturated)` on art
- [ ] `WidgetConfigurationIntent` to pick which raid to show (once several raids exist)
- [ ] App: reload timelines after every local change (already in intents) and every remote merge (M6)
- [ ] Accessibility: `.accessibilityElement(children: .combine)` + labels from `A11y`

### Tests
- [ ] Timeline provider unit test with an in-memory store
- [ ] Widget previews in every family × rendering mode (full color, dark, tinted, clear)
- [ ] Manual: tap "complete" in the widget → app shows the attack after it's opened; VoiceOver on the Home and Lock Screen

### Done when
- All widget families render correctly in every rendering mode, and completing a task from a widget updates the boss.

---

## M5: FakeTeammate, damage meter, phases (M)

**Goal:** the multiplayer UI fully works offline against simulated teammates.

### Tasks
- [ ] `Features/Debug/FakeTeammate`: adds 1–4 fake members with roles and writes attacks into the local store on a timer (configurable DPS and task rate); behind `#if DEBUG` and a hidden Settings menu
- [ ] **Meter tab:** Swift Charts horizontal bar chart with burst (tasks) and sustained (focus) per member; `accessibilityChartDescriptor`; a `List` fallback toggle; sorted by total
- [ ] "X is attacking" row: members with an active focus session (from `activeFocusSince`, faked locally for now)
- [ ] **Phase visuals:** phase banner, boss tint via `.glassEffect(.regular.tint(...))` on one element, `.warning` haptic + VoiceOver announcement on a phase change; Reduce Motion respected
- [ ] Teammate hit feed on the Boss tab; VoiceOver announcements summarized at most every 30 s
- [ ] Role picker in the member's profile (flavor icons)

### Tests
- [ ] `BossEngine` per-member totals with 5 members
- [ ] UI test with FakeTeammate on: meter shows 5 rows; audit passes
- [ ] Manual: VoiceOver chart navigation (audio graph), Differentiate Without Color on phases

### Done when
- With 4 fake teammates the boss loses HP live, the meter updates, and phases change as time passes.

---

## M6: Firebase raids and sync (L)

**Goal:** real multiplayer for up to 5 people, built on the local-first store.

### Tasks: setup
- [ ] Firebase project (dev); add iOS app; each developer downloads `GoogleService-Info.plist` (git-ignored)
- [ ] SPM: `FirebaseAuth`, `FirebaseFirestore`, linked only by the app target
- [ ] `firebase/` folder: `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `rules-tests/` (Node, `@firebase/rules-unit-testing`)
- [ ] Debug builds connect to the Firebase Emulator Suite when a launch argument is set

### Tasks: auth and identity
- [ ] `AuthService`: anonymous sign-in on first launch; nickname onboarding screen; replaces `LocalIdentity` (keeps the existing local member ID by migrating it)

### Tasks: raids
- [ ] Create raid: writes `raids/{id}` (with `memberIDs: [uid]`) and `inviteCodes/{code}` in one transaction; 6-character code from an unambiguous alphabet (no 0/O/1/I), retry on collision
- [ ] Join by code: transaction reads the code → raid, refuses if `memberIDs.count >= 5` or status ≠ planning/active, then adds the member
- [ ] Share link: `ShareLink` with the code; universal link / deep link is stretch
- [ ] Leader-only actions: start fight (locks HP), delete/rename raid

### Tasks: sync (`App/Sync/FirebaseSyncEngine`)
- [ ] Upload: watch the outbox (`syncState == .pending`), `setData` with document ID = local UUID, mark `.synced` on success, retry with backoff
- [ ] Download: snapshot listeners on `members`, `tasks`, `attacks` for the current raid; upsert into the local store by ID; reload widgets; update the Live Activity
- [ ] `createdAt` uses `FieldValue.serverTimestamp()`; `localDay` stays the client's value
- [ ] Presence: set `activeFocusSince` on the member doc at focus start, clear it on stop
- [ ] Offline: the app keeps working; the outbox flushes when back online
- [ ] Widget/Control writes while the app is closed: flushed on the next activation (decide here whether the extension should also upload directly; see Risks)

### Tasks: security rules (Appendix C)
- [ ] Only members read a raid and its subcollections
- [ ] `attacks`: create only; `memberId == request.auth.uid`; raid status `active`; no update/delete
- [ ] `tasks`: members create/update; completing sets `completedBy == request.auth.uid`
- [ ] `members`: join only through the size check on `memberIDs`
- [ ] Rules tests for each allow/deny case

### Tests
- [ ] Rules tests (emulator): non-member read denied; 6th join denied; attack update denied; attack for another member denied
- [ ] Sync integration test against the emulator: two `RaidStore`s + two engines converge to the same `BossState`
- [ ] Retry: the same attack uploaded twice → one document
- [ ] Manual: two simulators (or simulator + device) in one raid; airplane mode then reconnect

### Done when
- Two to five devices share one boss live, offline actions sync on reconnect, and the rules tests pass.

---

## M7: End-of-raid report and titles (M)

**Goal:** a satisfying victory/defeat screen that also works as the group project report.

### Tasks
- [ ] `Titles.award`: Sniper (most task damage), Grinder (most focus time), Consistent (longest streak), MVP (most total), Last-Minute Hero (most damage in the final phase), AFK Legend (least activity), plus a tie-break rule
- [ ] `RaidReport` builder in GameCore: per-member totals, titles, timeline of HP over time, late tasks list, phases reached
- [ ] `Features/Report/ReportView`: victory/defeat header, HP-over-time chart (`accessibilityChartDescriptor`), member cards with titles, late tasks section, `ShareLink` exporting a rendered image (`ImageRenderer`) with an alt-text description
- [ ] Raid status transitions: `.won` when HP hits 0 (first device to notice writes it; the rule only allows active → won/lost), `.lost` after the deadline
- [ ] Raid history list in the Raid tab

### Tests
- [ ] `Titles` unit tests for every title and ties
- [ ] `RaidReport` snapshot of a known attack log
- [ ] UI test: finish a raid with FakeTeammate → report → audit

### Done when
- Every finished raid shows a report with titles, and it can be shared as an image with a text description.

---

## M8: Stretch (pick by time left)

| Item | Notes |
|---|---|
| Teammates' attacks on Lock Screen while the app is closed | Cloud Function on attack create → APNs Live Activity update (needs a push token per member and an APNs key) |
| Notifications | Local: deadline and phase changes; remote: "X hit the boss" via FCM |
| Sign in with Apple | Link to the anonymous account (`link(with:)`) |
| Peer confirmation of tasks | "Confirm" button for teammates; unconfirmed tasks marked in the report |
| Cosmetics / loot | Boss skins and class icons unlocked by titles |
| Taunts and cheers | Quick reactions on the hit feed |
| On-device boss taunts | Foundation Models framework, with a fallback list of lines |

---

## 2. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| App Intents metadata not found when intents live in a Swift package | Intents missing from Shortcuts/widgets | Check in M0 with one dummy intent; fall back to a framework target in the Xcode project |
| Several processes write to the SwiftData store (app + widget + control) | App shows stale data | Refetch and read SwiftData history when the app becomes active; keep extension writes small; test in M3/M4 |
| Widget/Control actions don't reach teammates until the app opens | Raid feels laggy | Accept for MVP; M6 decides on uploading directly from the extension (Firebase Auth keychain sharing) or a background refresh |
| Firebase SDK size / cold start | Slower launch | Initialize lazily after first frame; app target only |
| Client-calculated damage can be faked | Cheating | Trust model is fine for a student project; rules limit damage to the max per kind; Cloud Function validation is stretch |
| Time zones and daily caps | Inconsistent caps across devices | `localDay` stored on each attack at creation |
| Liquid Glass legibility over boss art | Hard to read | Content not glass; test with Reduce Transparency and Increase Contrast; avoid tinting more than one element |
| Scope creep from the idea list | Missed deadline | M0–M5 is the solo + simulated MVP and already a complete demo; M6–M7 next; M8 only with time left |

---

## 3. Decisions still open (and when they're needed)

| Question | Needed by |
|---|---|
| Project duration and course requirements | Now (to scope M8) |
| Exact damage numbers | Playtesting after M3; `DamageConfig` keeps them in one place |
| Boss / class art style | M2 uses placeholders; final art by M7 |
| Task honesty (trust vs peer confirmation) | M6 (affects rules) |
| Extension uploads directly vs on next app open | M6 |

---

## Appendix A: `Packages/DDKit/Package.swift` (sketch)

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DDKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "DDPersistence", targets: ["DDPersistence"]),
        .library(name: "DDIntents", targets: ["DDIntents"]),
        .library(name: "DDDesign", targets: ["DDDesign"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .target(name: "DDPersistence", dependencies: ["GameCore"]),
        .target(name: "DDIntents", dependencies: ["DDPersistence", "GameCore"]),
        .target(name: "DDDesign", dependencies: ["GameCore"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
        .testTarget(name: "DDPersistenceTests", dependencies: ["DDPersistence"]),
        .testTarget(name: "DDIntentsTests", dependencies: ["DDIntents"]),
    ]
)
```

## Appendix B: `DamageConfig` defaults (tune in playtesting)

| Setting | Default |
|---|---|
| Task damage S / M / L | 50 / 150 / 400 |
| Focus damage | 2 per minute |
| Daily focus cap per member | 180 minutes |
| Task share of max HP | 0.65 (max HP = task total / 0.65) |
| Streak | ≥30 focus minutes per day; ×1.1 after 2 days, ×1.2 after 4 days, capped at ×1.2 |
| Per-member daily damage cap (raids ≥2 members) | 25% of locked max HP |
| Background grace period | none (removed: time away counts as focus) |
| Phases (share of time left) | > 50% Calm · ≤ 50% Angry · ≤ 25% Enraged · ≤ 10% Berserk; the leader can shift the whole timeline ±1–3 steps (`Raid.phaseShift`), clamped to Calm…Berserk |
| Max members | 5 |

## Appendix C: Firestore schema and rules (sketch)

```
raids/{raidId}                     name, bossName, ownerId, inviteCode, deadline, createdAt,
                                   startedAt?, lockedMaxHP?, status, memberIDs[],
                                   phaseShift? (int -3...3, leader only; missing = 0)
raids/{raidId}/members/{uid}       nickname, role?, joinedAt, activeFocusSince?
raids/{raidId}/tasks/{taskId}      title, size, assigneeId?, createdAt, completedAt?, completedBy?
raids/{raidId}/attacks/{attackId}  memberId, kind, taskId?, durationSeconds?, damage, createdAt, localDay
inviteCodes/{code}                 raidId
```

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function raid(raidId) { return get(/databases/$(db)/documents/raids/$(raidId)).data; }
    function isMember(raidId) { return request.auth.uid in raid(raidId).memberIDs; }

    match /raids/{raidId} {
      allow read: if isMember(raidId);
      allow create: if request.auth != null
                    && request.resource.data.ownerId == request.auth.uid
                    && request.resource.data.memberIDs == [request.auth.uid];
      // Join: add only yourself, max 5. Leader: start fight / finish.
      allow update: if request.auth != null && (
          (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['memberIDs'])
            && request.resource.data.memberIDs.size() <= 5
            && request.resource.data.memberIDs.removeAll(resource.data.memberIDs) == [request.auth.uid])
          || (isMember(raidId) && resource.data.ownerId == request.auth.uid)
          || (isMember(raidId) && resource.data.status == 'active'
              && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status'])
              && request.resource.data.status in ['won', 'lost']));

      match /members/{uid} {
        allow read: if isMember(raidId);
        allow write: if uid == request.auth.uid && isMember(raidId);
      }
      match /tasks/{taskId} {
        allow read, create, update: if isMember(raidId);
      }
      match /attacks/{attackId} {
        allow read: if isMember(raidId);
        allow create: if isMember(raidId)
                      && request.resource.data.memberId == request.auth.uid
                      && raid(raidId).status == 'active'
                      && request.resource.data.damage is int
                      && request.resource.data.damage > 0
                      && request.resource.data.damage <= 480; // max single hit (L task × 1.2)
        allow update, delete: if false;
      }
    }
    match /inviteCodes/{code} {
      allow get: if request.auth != null;
      allow create: if request.auth != null;
    }
  }
}
```

Note on the attack damage limit: with the defaults, the largest possible single attack is an L task with the top streak (400 × 1.2 = 480). The largest focus attack is a full day's cap (180 min × 2 × 1.2 = 432). Update the limit whenever `DamageConfig` changes.
