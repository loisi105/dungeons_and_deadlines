# Dungeons & Deadlines — Architecture

> Some details changed during implementation: Firebase is called over REST instead of the SDK, `RaidStore` runs on the main actor, write intents run in the app process, in-content buttons use the pixel theme instead of glass, and Game Center was added. See [HANDOFF.md](HANDOFF.md#decisions-that-changed-since-the-plan-docs).

Last updated: 2026-11-19. Decisions behind this document are in the README ("Decisions").

## 1. Principles

1. **Local-first.** Every action is written to a local SwiftData store first. The UI, widgets, Live Activity and Control Center control all read from that store. Firestore sync runs in the background. The app works offline, and every surface shows the same numbers.
2. **The attack log is the source of truth.** Attacks are only ever added. Current HP, phases, the damage meter, streaks and titles are calculated from them. Max HP is calculated once when the fight starts and then locked.
3. **One action layer.** Every user action (complete task, start/stop focus, etc.) is an App Intent. In-app buttons, interactive widgets, Live Activity buttons, the Control Center control, Siri, Shortcuts, Spotlight and the Action button all call the same code.
4. **System components first.** Standard SwiftUI controls give you Liquid Glass, native touch behaviour and most accessibility for free. Custom views are only for what the system doesn't have (the boss, the HP bar).
5. **Accessibility is part of "done" for every milestone,** not a separate milestone (see section 7).

## 2. Targets and modules

```
DungeonsAndDeadlines (app)              DDWidgets (widget extension)
  Features/ Boss, Tasks, Focus,           Home + Lock Screen widgets
            Raid, Meter, Report           Live Activity + Dynamic Island
  Sync/     FirebaseSyncEngine            Control Center control
  App/      entry point, dependency setup
        \                                   /
         \                                 /
          v                               v
   Packages/DDKit (local Swift package, several library targets)
     DDIntents      App Intents + App Entities (RaidEntity, TaskEntity)
     DDPersistence  SwiftData models, RaidStore, Outbox, App Group container
     DDDesign       glass styles, typography, shared a11y helpers, haptics
     GameCore       pure Swift: models, DamageCalculator, BossEngine,
                    phases, streaks, titles  (no UI, no storage, no Firebase)
```

Dependency direction: `app / widgets → DDIntents → DDPersistence → GameCore`. `DDDesign` only depends on SwiftUI. Firebase is linked **only** by the app target, in `Sync/`.

- **App Group** (`group.<bundle-id>`): holds the SwiftData store so the app and widget extension share it.
- **Swift 6 language mode** with strict concurrency. Views and view models are `@MainActor` and `@Observable`. Background writes go through a `@ModelActor` (`RaidStore`).
- **Deployment target: iOS 26.0** (Liquid Glass APIs; see README).

## 3. Data flow

```
 tap / widget / control / Siri
            │
            ▼
      App Intent (DDIntents)
            │  GameCore.DamageCalculator computes damage
            ▼
  RaidStore (SwiftData, App Group) ──► Outbox (unsent attacks)
            │                                  │
            │ reload widgets / update          │ FirebaseSyncEngine (app only)
            │ Live Activity                    ▼
            ▼                             Firestore  ◄──► teammates
   SwiftUI views (@Query)                      │
            ▲                                  │ snapshot listener
            └──────── remote attacks merged ◄──┘
```

- **Writes:** an intent calculates damage, saves the `Attack` locally and adds it to the outbox, then calls `WidgetCenter.shared.reloadAllTimelines()` and updates the Live Activity.
- **Sync (app only):** `FirebaseSyncEngine` uploads outbox items. The attack's UUID is the Firestore document ID, so a retry can't count an attack twice. The engine also listens to the raid's `attacks`, `tasks` and `members` collections and merges them into the local store.
- **Intents that run outside the app** (widget buttons, Control Center): they write locally, and the app syncs on its next activation. Making those writes reach teammates sooner, through Firebase in the extension (sharing auth through the keychain) or a background refresh, is a detail to settle in M6.
- **Firestore schema and security rules:** see the README. Joining runs in a transaction that refuses a 6th member, and the rules make `attacks` add-only.
- **Teammates' attacks on the Lock Screen while the app is closed** need APNs Live Activity push updates sent from a Cloud Function. That's a stretch goal; the MVP updates the Live Activity from the device itself.

## 4. App Intents (the action layer)

| Intent | Used from |
|---|---|
| `CompleteTaskIntent(task: TaskEntity)` | task row, interactive widget, Siri/Shortcuts |
| `StartFocusIntent(raid: RaidEntity)` | focus screen, Control Center / Lock Screen control, Action button, widget |
| `PauseFocusIntent`, `StopFocusIntent` | timer accessory, Live Activity buttons |
| `OpenRaidIntent(raid:)` | widget tap, Spotlight |

- `RaidEntity` and `TaskEntity` conform to `AppEntity` so Siri, Shortcuts and Spotlight can find raids and tasks by name.
- An `AppShortcutsProvider` adds phrases such as "Start focus in Dungeons and Deadlines".
- Each intent is a thin wrapper that calls `RaidStore` + `GameCore`. Tests cover the store and core, so the intents need no logic of their own.

## 5. Surfaces: Liquid Glass and native touch

### Liquid Glass rules
- **The content layer is not glass:** boss art, HP bar, task rows, damage meter.
- **The control layer floats over content and is glass:** tab bar, toolbars, the focus button cluster, the timer accessory and sheets. Standard `TabView`, `NavigationStack`, `.toolbar` and `.sheet` get glass automatically when built with the iOS 26 SDK.
- **Custom glass, used sparingly:**
  - `.buttonStyle(.glassProminent)` for the main action ("Start focus"), `.buttonStyle(.glass)` for secondary actions.
  - The focus controls sit in a `GlassEffectContainer`. `glassEffectID(_:in:)` morphs the single "Start" capsule into "Pause | Stop" when a session starts.
  - The boss phase can tint one element: `.glassEffect(.regular.tint(phase.tint).interactive())`. Never tint everything.
- **Never put glass on top of glass.** Don't put custom backgrounds behind system bars; let `.backgroundExtensionEffect()` extend boss art under the bars instead.

### Dismissing overlays
Every sheet and full-screen cover dismisses the same way, through the helpers in `DDDesign/SheetToolbar.swift`. Don't write dismiss buttons by hand.
- **Sheets that only show things** (report, focus timer, paywall, boss picker, the phase-details sheet): `.sheetCloseButton()`, an X (`Button(role: .close)`) on the leading side.
- **Sheets that edit or create something** (new boss, task editor, join raid, resume fight): `.sheetCancelConfirm("Save") { … }`, a cancel X (`Button(role: .cancel)`) on the leading side and a labelled confirm action (`role: .confirm`) on the trailing side. Other trailing items such as Share go in `.primaryAction`.
- **Popovers** dismiss by tapping outside and get no X. When one adapts to a sheet (accessibility text sizes), that sheet gets the close X.
- **Alerts and confirmation dialogs** keep the system's text buttons ("Cancel", "Not yet").

### App structure
- A `TabView` with **Boss**, **Tasks**, **Meter** and **Raid** tabs, plus `.tabBarMinimizeBehavior(.onScrollDown)`.
- `.tabViewBottomAccessory { FocusTimerAccessory() }` shows a running timer on every tab, like a music mini-player. Tapping it opens the full timer sheet.
- `.navigationTransition(.zoom(sourceID:in:))` from a task row to its detail view, and from the boss card to the boss detail.

### Native touch
- Swipe right on a task to complete it: `.swipeActions(edge: .leading)` with `.tint(.green)`. A context menu offers complete, edit, assign and delete. Drag to reorder.
- Use system controls (`Button`, `Picker` for task size, `Stepper`, `DatePicker` for the deadline). Don't build custom gesture recognizers where a system control exists.
- Tap targets are at least 44×44 pt. Every gesture also exists as a button or a named accessibility action.
- Haptics through `.sensoryFeedback`: `.impact(weight: .heavy)` on a task hit, `.impact(weight: .light)` on a focus tick (at most once a minute), `.warning` on a phase change, `.success` on a win, `.selection` in pickers. Never use haptics as the **only** feedback.

### Widgets and system surfaces (DDWidgets)
| Surface | Content | Interaction |
|---|---|---|
| Home widget, small | Boss name, HP ring, phase icon | Tap → opens the raid |
| Home widget, medium | HP bar + the next 2–3 tasks | `Button(intent: CompleteTaskIntent)` per task |
| Lock Screen (circular / rectangular) | HP gauge / boss + deadline countdown | Tap |
| StandBy | Same as the small widget, full color | — |
| Live Activity + Dynamic Island | Running focus timer (`Text(timerInterval:)`), boss HP, "X is attacking" | Pause / Stop buttons (intents) |
| Control Center / Lock Screen / Action button control | `ControlWidgetToggle` for start/stop focus | Runs `StartFocusIntent` / `StopFocusIntent` |

- Test widgets in every rendering mode: full color, dark, **tinted and clear** (`widgetRenderingMode == .accented`). Mark the boss art with `.widgetAccentedRenderingMode(.desaturated)` or similar so it stays legible.
- Timelines come from the shared store. The app reloads them after every local or remote change.

## 6. Feature to file mapping (examples)

- `Features/Boss/BossView.swift`: boss art, `HPBar`, phase banner, hit animation
- `Features/Focus/FocusTimerModel.swift`: `startedAt` and `accumulated`, and the timer keeps running while the app is in the background (iOS can't tell a locked phone from another app, so time away counts; the daily focus cap still applies)
- `DDKit/GameCore/BossEngine.swift`: `lockHP(tasks:)` and `state(raid:attacks:now:)`
- `DDKit/DDDesign/HPBar.swift`: the custom view, with its accessibility representation (section 7)

## 7. Accessibility

### Requirements by feature
| Area | Requirement | How |
|---|---|---|
| HP bar | VoiceOver reads "Exam Dragon health, 1 240 of 3 000, 41 percent, phase 2 enraged" | `.accessibilityRepresentation { ProgressView(value:) }` or `.accessibilityElement()` + label/value |
| Hits | Damage is announced without flooding | `AccessibilityNotification.Announcement` for your own hits; teammates' hits summarized at most every 30 s |
| Phases | Never conveyed by color only | Phase icon + text label; honour `accessibilityDifferentiateWithoutColor` |
| Animations | Screen shake / boss knockback | If `accessibilityReduceMotion`: crossfade + haptic instead of shake; no auto-playing loops |
| Glass and contrast | Legible on any background | System glass handles Reduce Transparency and Increase Contrast. Custom materials check `accessibilityReduceTransparency` and `colorSchemeContrast`. |
| Text | Dynamic Type up to AX5 | No fixed font sizes; at `dynamicTypeSize.isAccessibilitySize`, horizontal layouts stack vertically (`ViewThatFits` / `AnyLayout`) |
| Damage meter | Readable without the chart | Swift Charts + `accessibilityChartDescriptor`, and a plain list fallback |
| Gestures | Swipe and drag have alternatives | `.accessibilityAction(named: "Complete task")`, context menu, edit mode for reordering |
| Voice Control | Short spoken names | `.accessibilityInputLabels(["Start", "Focus"])` on icon buttons |
| Timer | Readable remaining time | `Text(timerInterval:)` is VoiceOver-friendly; plus an announcement on start and stop |
| Widgets / Live Activity | Same labels as in the app | Shared label helpers in `DDDesign`; widgets grouped with `.accessibilityElement(children: .combine)` |
| Sound and haptics | Optional, never the only signal | Settings toggles; every event also shown visually |

### Process
- **Previews:** every screen has previews at default size, `.accessibility3`, dark mode and right-to-left.
- **UI tests:** a smoke test opens each screen and runs `XCUIApplication().performAccessibilityAudit()`. CI fails on audit issues.
- **Manual pass per milestone:** VoiceOver, Voice Control, largest Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast, Switch Control on the main flow.
- **App Store:** fill in the Accessibility Nutrition Label from that checklist.

## 8. Testing

| Layer | Tests |
|---|---|
| GameCore | Swift Testing unit tests: damage, caps, streaks, locked HP, phase boundaries, titles |
| DDPersistence | In-memory `ModelContainer`: store, outbox, merging remote attacks |
| Intents | Call `perform()` against an in-memory store |
| Sync | Firebase Emulator Suite + security rules tests |
| UI | Smoke test + accessibility audit per screen; `FakeTeammate` debug mode for multiplayer |

## 9. Milestones (revised)

Summary only. Tasks, tests and done criteria for each milestone are in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

Every milestone's "done" includes: tests green, accessibility audit passing, VoiceOver + largest Dynamic Type checked.

| # | Milestone | Done when |
|---|---|---|
| M0 | Xcode 26 project, iOS 26 target, app + widget extension, App Group, `DDKit` package with 4 targets, test targets, UI test with accessibility audit | Builds, audit test runs |
| M1 | `GameCore`: models, `DamageCalculator`, `BossEngine` (locked HP), phases | Unit tests cover all rules |
| M2 | `DDPersistence` + `DDIntents` (complete task, start/stop focus) + Boss and Tasks tabs with Liquid Glass, swipe actions, haptics | Solo boss can be beaten; every action works through an intent |
| M3 | Focus timer, tab bottom accessory, Live Activity + Dynamic Island, Control Center control | Timer survives being backgrounded or killed; controls work from the Lock Screen |
| M4 | Home, Lock Screen and StandBy widgets with interactive task buttons | Widgets correct in all rendering modes |
| M5 | `FakeTeammate`, damage meter (chart + list), phase visuals | Multiplayer UI testable offline |
| M6 | Firebase: anonymous auth + nickname, create/join (max 5), `FirebaseSyncEngine`, rules + emulator tests | Two simulators share one boss live |
| M7 | End-of-raid report + titles | Report generated from the attack log |
| M8 | Stretch: APNs Live Activity pushes (Cloud Function), notifications, Sign in with Apple, cosmetics | — |
