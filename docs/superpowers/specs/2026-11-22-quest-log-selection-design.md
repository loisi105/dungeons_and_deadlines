# Quest Log: no checkbox, confirmed completion, Mail/Notes-style selection

Date: 2026-11-22 (revised after "remove the checkbox entirely"). Size: a small change (`TasksView.swift` and its UI tests).

## Intent
The checkbox started a selection mode instead of completing, and "Edit" didn't say what it did. Completing a
task deals damage once and can't be taken back, so it needs a confirmation. The list should feel like Apple's
own (Mail, Notes), with no checkbox.

## Goals
- Completing needs one confirming tap, in places Apple users already know.
- Selecting several tasks works like Mail and Notes: ⋯ menu → "Select Tasks", circles, "n Selected",
  Select All, bottom bar, Done.
- A row says who a task belongs to through the class icon, without clutter.

## Non-goals / anti-goals
- No undo, no new damage rules, no assign-in-selection, no cross-group moves, no custom swipe machinery.

## Design
**Rows.** No leading checkbox: title and the second line ("Large · 400 dmg"), chevron, tap opens the details.
Open rows have no leading icon. Group headers carry the assignee's class icon ("[wand] Ada (3)", teammate
without a class: person icon; "Unassigned": person with dashed circle). Done rows show the class icon of
whoever completed them (`completedBy`), so the Done list says who landed the hit.

**Ways to complete (each confirms):**
1. Swipe right: "Complete" with `allowsFullSwipe: false`; it stays open and a tap commits (Mail's pattern).
2. Task details: the existing "Complete task" button.
3. ⋯ → Select Tasks, choose tasks, Complete in the bottom bar (one confirmation for the batch: a dialog
   "Complete n tasks? / Complete"). Also in the long-press menu (the menu item is the confirmation).
Planning raids still ask to start the fight first.

**Toolbar.** "Edit/Done" goes. Leading ⋯ menu: "Select Tasks" (disabled when nothing is open). In select mode:
leading Select All/Deselect All, trailing Done, title "Select Tasks"/"n Selected", bottom bar Complete and
Delete (disabled while nothing is selected), tab bar hidden. Select All takes every open task across groups.
Done tasks have no circle; reordering stays as the system's drag handles while selecting.

**Groups.** Mail/Notes rules: no special first-row or single-row handling; header and count follow their
tasks, and the header disappears with its last task. Selection is flat across groups; batch order is list order.

**Reopen.** Swipe right on a done task: Reopen (full swipe, undoable). Left on an open task: Delete (full swipe)
and Details, as today.

**Accessibility.** The "Complete task" custom action stays direct. The class icon is decorative in headers
(the name is in the text); in Done rows the label says "done by <name>".

## My calls (not discussed)
- Class icon in group headers and Done rows rather than on every open row: in grouped lists the header already
  names the person, and in lists without assignees every row would show the same "nobody" icon.
- Batch Complete asks once for the whole batch (a dialog); a single swipe/details completion uses its own button.
- Batch Delete keeps its confirmation; single swipe-delete stays immediate.

## Tests
Update the UI tests that complete through the checkbox (use swipe → Complete, or Select Tasks → Complete →
confirm). Add: swipe stays open until Complete is tapped; Select All; Done row shows who completed it.
