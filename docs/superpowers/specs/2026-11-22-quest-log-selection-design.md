# Quest Log: checkbox confirmation and Mail/Notes-style selection

Date: 2026-11-22. Size: a small change (one screen, `TasksView.swift` plus its UI tests).

## Intent
The Quest Log's Edit button and checkbox were confusing: the checkbox started a selection mode instead of
completing, and "Edit" didn't say what it did. Completing a task deals damage once and can't be taken back, so
it needs a confirmation, but it should feel like Apple's own lists (Mail, Notes, Reminders).

## Goals
- The checkbox completes the task after one confirming tap, in the row (the pattern of Mail's edit-mode Delete:
  tap the circle, a button slides in, tap it to confirm).
- Swiping right to complete also needs a second tap (native: `allowsFullSwipe: false`).
- Selecting several tasks works like Mail and Notes: ⋯ menu → "Select Tasks", circles, "n Selected",
  Select All, a bottom bar, and Done.

## Non-goals / anti-goals
- No undo, no new damage rules, no assign-in-selection, no cross-group moves.
- Nothing that fights the system list: no custom swipe machinery.

## Approaches considered (user picked 1)
1. Checkbox opens an in-row confirm button ("Complete"). Custom view state, native look. Chosen.
2. Instant completion with a 3 s Undo banner. Fast, but doesn't ask first.
3. Confirmation dialog on every tap. Fully native, but heavy.

## Design
**Toolbar.** The "Edit/Done" button goes. Leading: a ⋯ menu with "Select Tasks" (disabled when no task is
open). Trailing: boss switcher and "+" as today. In select mode: leading "Select All"/"Deselect All", trailing
"Done", title "Select Tasks" / "n Selected", bottom bar Complete and Delete (both disabled with nothing
selected), tab bar hidden. Select All takes every open task across all groups; done tasks have no circle.

**Checkbox.** `confirmingID: UUID?`. Tapping the checkbox of an open task sets it (the circle shows as pending
and the chevron is replaced by a "Complete" button with a spring transition). Tapping "Complete" completes via
the existing path (`attemptComplete`: planning still asks to start the fight first). Tapping the same checkbox,
another row, a swipe, "Select Tasks", or the task being completed/deleted elsewhere clears it. Only one row at a
time. Finished bosses: checkbox disabled as today.

**Swipe.** Right: Complete with `allowsFullSwipe: false` (stays open, tap to confirm). Done tasks: Reopen keeps
full swipe (undoable). Left: Delete (full swipe) and Details, as today.

**Groups.** Group rules follow Mail/Notes: no special first-row or single-row handling; a group's header and
count follow its tasks and the header disappears with its last task; selection is flat across groups; batch
actions run in list order.

**Reordering.** Stays as the system's drag handles while selecting (no separate mode). Order only changes
within a group, as today.

**Accessibility.** Checkbox label "Complete <title>", hint "Shows a Complete button". The "Complete task"
custom action stays direct (choosing it is already deliberate). Row tap still opens the details.

## My calls (not discussed)
- Button text is "Complete" (not "Hit for 400"), since planning raids don't fight yet; the damage is already in
  the row's second line.
- Batch Delete keeps its confirmation dialog (tasks can't be restored).
- Single-row swipe-delete stays immediate, as today.

## Tests
Update the UI tests that start a batch by tapping a checkbox: they use ⋯ → Select Tasks. Add tests for
checkbox → confirm → completed, cancel by tapping elsewhere, and Select All.
