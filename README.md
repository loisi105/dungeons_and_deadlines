# Dungeons & Deadlines — Project Notes

Working name: **Dungeons & Deadlines** (formerly "Deadline Dojo")
Platform: iOS (SwiftUI), student project
Last updated: 2026-11-19

## Status
Ideation done, concept chosen, core technical decisions made (see "Decisions"). No code written yet. Next step: Xcode project setup and the `GameCore` package (models + `DamageCalculator`) with unit tests.

## Decisions (2026-11-19)
- **Backend:** Firebase (Auth + Firestore)
- **Minimum iOS: 26.0**, the lowest version that supports every planned feature:
  - Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.tabViewBottomAccessory`): iOS 26. This is what sets the minimum.
  - Control Center / Lock Screen controls: iOS 18
  - SwiftData, `@Observable`, interactive widgets, `.sensoryFeedback`, accessibility audits in UI tests: iOS 17
  - iOS 26 runs on iPhone 11 and newer
- **Focus: architecture, accessibility, native touch, widgets, Liquid Glass.** See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Boss HP is locked when the fight starts.** A raid has a planning phase (create tasks, invite members), then the leader starts the fight. At that moment max HP is calculated from the planned tasks (task damage total / 0.65, so ~65% from tasks and ~35% from focus time) and stored once. It never changes after that. Current HP is still derived from the attack log.
  - Tasks added after the start still deal damage but are marked as late additions (shown in the report, for honesty).
- **Team size: 1-5 people.** Solo is a raid with one member. Joining is refused when a raid already has 5 members. The per-person daily cap stays in, so one person can't carry the team.

## Concept
Deadlines and group projects are boss fights. Finishing tasks and spending focused time on a project deal damage to the boss. Works in single player (personal deadlines) and multiplayer raids (group projects, WoW-style).

## Idea history (how we got here)
Favorites from brainstorming: Study Buddy, Sleep Bet, Procrastination Tracker, then Deadline Dojo (chosen).

Other ideas kept as possible features or future projects:
- **Snitch**: missed check-in sends funny "exposed" notifications to friends
- **Stake Pot**: friends stake virtual coins on goals, flakes lose theirs
- **Phone Jail**: leaving the app during a focus session lets a cartoon prisoner escape
- **Group Project Judge**: peer ratings and a funny contribution report (folded into the raid end screen)
- **Spontaneous**: "who's free in the next hour?" status pings
- **Library Radar**, **Exam Panic Meter**, **Wake-up Proof**, **Snooze Shame Wall**, **Lecture Bingo**, **Fake Busy**, **Rate My Chaos**, **Split the Fridge**

## Damage model
Two damage sources:

| Source | Damage | Feel |
|---|---|---|
| Task completed | By size: S=50, M=150, L=400 (example numbers) | Big hit, animation, screen shake |
| Focus time | ~2 damage per focused minute (example) | Continuous chip damage / DPS |

Balancing rules:
- Daily cap on time damage (e.g. 3 hours) to stop timer abuse
- Target split: ~60-70% of boss HP from tasks, ~30-40% from time
- Boss total HP derived from the plan: sum of task damage + expected time damage
- Streak multiplier: consecutive days with >= 30 min of work give 1.1x, 1.2x, capped
- Optional per-person daily cap in raids so one person can't carry everything

Time tracking:
- In-app focus timer (start/pause/stop)
- Pause if app is backgrounded for more than ~2 minutes (`scenePhase`)
- Compute elapsed time from start timestamps, not ticks, so it survives suspension
- Live Activity for lock-screen timer
- Raids: show live "X is attacking" with their DPS

## Raid (multiplayer) design
- One person creates a raid (boss name, deadline, HP), others join via invite code or link
- Tasks have sizes; completing one deals damage; HP bar updates live for everyone
- Optional roles/classes (writer = mage, researcher = tank, designer = rogue, presenter = healer) for flavor and different animations
- Boss enrages as the deadline nears: phase changes at 50%, 25%, 10% time left; skipped tasks shown as damage to the team
- Damage meter like WoW, split into burst (tasks) and sustained (time) columns
- Titles: Sniper (most task damage), Grinder (most time), Consistent (longest streak), MVP, Last-Minute Hero, AFK Legend
- AFK status/nudges for inactive teammates, taunts and cheers between players
- End screen: victory/defeat report (doubles as Group Project Judge)
- Task honesty: optional peer confirmation of completed tasks; show task difficulty to discourage many tiny tasks

## Technical decisions and options
Backend options for multiplayer:

| Approach | Effort | Notes |
|---|---|---|
| CloudKit shared records | Medium | Native, free, no server, Apple-only; sync a bit slower/fiddly |
| Firebase Firestore | Low-medium | Live listeners suit the HP bar; **current recommendation** |
| Supabase | Medium | SQL + realtime |

Data model sketch:
- `Raid`, `Member`, `Task`, `Attack`
- `Attack` has `kind` (`.task` / `.focus`), `damage`, `timestamp`, `memberID`, and either `taskID` or `durationSeconds`
- Boss HP is **derived** (locked max HP minus sum of attacks), not a stored mutable value, so it stays consistent across devices
- Daily caps computed at attack creation time from that member's attacks that day
- Put all damage rules in one pure `DamageCalculator` struct so it's unit-testable and easy to tune

## MVP scope
1. Sign in (Sign in with Apple or anonymous + nickname)
2. Create/join raid by code
3. Task list with sizes; completing a task deals damage
4. Focus timer that deals damage
5. Live boss HP bar and damage meter
6. Boss phases based on the deadline
7. End-of-raid report

Also in scope (moved up from stretch): solo mode, widgets, Live Activity, Control Center control, App Intents, accessibility.

Stretch: push notifications for boss phases/teammate attacks, Live Activity push updates for teammates' attacks, loot/cosmetics from finished raids, streak multipliers.

## Build order
See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the full plan: milestones M0–M8 with tasks, tests, accessibility checks, team split, risks, and the config, package and Firestore rules sketches.

## iOS features this covers
SwiftUI with Liquid Glass, SwiftData (shared App Group store), App Intents (Siri, Shortcuts, Spotlight, Action button), interactive widgets (Home, Lock Screen, StandBy), Control Center controls, Live Activities + Dynamic Island, haptics, accessibility (VoiceOver, Dynamic Type, Reduce Motion, Voice Control, accessibility audits), scenePhase handling, Sign in with Apple, notifications, real-time backend sync.

## Open questions
- Project duration? Any course requirements (SwiftUI, backend, ML)?
- Final boss/class theming and art style
- Exact damage numbers (tune with playtesting)
- How to handle task honesty (peer confirmation or trust)

## Next steps
- Write Swift data model and `DamageCalculator`
- Sketch main screens (boss view, task list, focus timer, raid lobby, damage meter, end report)
- Add a debug "fake teammate" early to test multiplayer
