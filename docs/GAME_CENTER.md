# Game Center

Game Center is the Apple-native layer on top of the game: sign-in with the player's Apple
Game Center profile, achievements, leaderboards, the Access Point and the Games app.
Raids themselves still sync through Firebase (Game Center's real-time matches only last
while everyone is connected, so they can't carry a raid that runs for days).

## What the app does

| Where | What |
|---|---|
| Launch (after onboarding) | `GKLocalPlayer` sign-in. If iOS needs the player to sign in, it shows its own sheet. |
| Onboarding | The Game Center display name pre-fills the nickname when none is set. |
| Party (Raid) tab | Game Center section: Achievements and Leaderboards buttons, sign-in state. The Access Point floats on the Raid tab and the welcome screen. |
| After every hit, win or loss | Progress is recomputed from the local attack log (`PlayerProgress` in GameCore) and only *changes* are reported. |

Everything is skipped in UI tests (`-uiTesting`). Without the IDs below set up in App Store
Connect, reports fail quietly and the app works normally.

## App Store Connect setup

1. Enable the **Game Center** capability for bundle ID `at.fhooe.sail.dungeonsanddeadlines`
   (the entitlement is already in `Config/DungeonsAndDeadlines.entitlements`).
2. In App Store Connect → the app → **Game Center**, create these.

### Achievements

| ID | Name | How to earn | Points | Progressive |
|---|---|---|---|---|
| `dd.achievement.first_blood` | First Blood | Deal your first damage | 5 | no |
| `dd.achievement.first_victory` | Deadline Slayer | Defeat your first boss | 10 | no |
| `dd.achievement.slayer_5` | Seasoned Slayer | Defeat 5 bosses | 25 | yes |
| `dd.achievement.slayer_25` | Legendary Slayer | Defeat 25 bosses | 50 | yes |
| `dd.achievement.focus_10h` | Deep Focus | Focus for 10 hours in total | 25 | yes |
| `dd.achievement.streak_7` | Unbreakable | Focus 30+ minutes on 7 days in a row | 25 | yes |
| `dd.achievement.flawless` | Flawless | Win with every task done | 15 | no |
| `dd.achievement.full_party` | Full Party | Win a raid with 5 members | 20 | no |
| `dd.achievement.title_mvp` | MVP | Earn the MVP title in a raid | 15 | no |
| `dd.achievement.title_sniper` | Sniper | Earn the Sniper title | 10 | no |
| `dd.achievement.title_grinder` | Grinder | Earn the Grinder title | 10 | no |
| `dd.achievement.title_consistent` | Consistent | Earn the Consistent title | 10 | no |
| `dd.achievement.title_last_minute_hero` | Last-Minute Hero | Earn the Last-Minute Hero title | 10 | no |

Title achievements only count in raids with at least 2 members. AFK Legend is never an achievement.

### Leaderboards (classic, all-time, high score first)

| ID | Name | Score |
|---|---|---|
| `dd.leaderboard.total_damage` | Total Damage | All damage you've dealt |
| `dd.leaderboard.bosses_defeated` | Bosses Defeated | Number of won raids |
| `dd.leaderboard.focus_minutes` | Focus Minutes | Total focused minutes |

The IDs live in `Packages/DDKit/Sources/GameCore/PlayerProgress.swift` (`Achievement`, `Leaderboard`).

## Testing

- Unit tests: `PlayerProgressTests` (GameCore) cover totals, victories, title rules and IDs.
- On a device or simulator: sign in to Game Center in Settings, run the app, finish a raid,
  then open Raid → Game Center → Achievements.
