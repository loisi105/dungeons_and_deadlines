# Quest Log selection Implementation Plan

> **For agentic workers:** use superpowers:executing-plans. Steps use checkboxes.

**Goal:** Quest Log without the checkbox: swipe/details/select-mode completion with a confirming tap, a ⋯ → "Select Tasks" menu, class icons in group headers and Done rows.

**Architecture:** All in `TasksView.swift` (list, toolbar, rows) plus UI tests; no model changes.

**Tech Stack:** SwiftUI List(selection:) + EditMode, XCUITest.

**Spec:** `docs/superpowers/specs/2026-11-22-quest-log-selection-design.md`

## Global Constraints
- Type scale from `Theme` comment; ids: `tasksMenuButton`, `selectTasksButton`, `selectAllButton`, `doneSelectingButton`, `completeSelectedButton`, `deleteSelectedButton`; rows keep `task-<title>`.
- Test runs use `-derivedDataPath build/DerivedData` and the iPhone simulator `887F97A2-…`.

## Review Focus
- All open tasks done (no open): "Select Tasks" disabled. Test: menu item disabled with only done tasks.
- Select All then deselect with one tap; count in title. Test: `testSelectAllAndCompleteSeveral`.
- Swipe-complete stays open until the button is tapped. Test: `testSwipeCompleteNeedsConfirmation`.
- Finished raid: Complete disabled, Delete still works.
- Group with a single task / first task: header icon and count update when the task leaves (data-driven, covered by the seeded multi-group test only visually).

---
### Task 1: View and toolbar
**Files:** Modify `DungeonsAndDeadlines/Features/Tasks/TasksView.swift`
**Interfaces:** Produces `TaskGroup.symbol: String?`; removes `CompleteButton`, `beginSelecting`, the Edit/Done button.
- [ ] Remove `CompleteButton` use and struct; rows: `Button { path.append(id) }` with `TaskRow` + chevron; Done rows get a leading `Image(systemName: completerSymbol)` (completer's `role?.symbol ?? "checkmark.circle.fill"`), accessibility "done by <name>".
- [ ] Section headers: `Label(group.title, systemImage: group.symbol)` where symbol = member role symbol / `person.fill` / `person.crop.circle.dashed` (unassigned); none for plain "Open".
- [ ] Leading swipe: `allowsFullSwipe: task.isDone` (Complete stays open, Reopen full-swipes).
- [ ] Toolbar: leading `Menu("More", systemImage: "ellipsis")` with `Button("Select Tasks", systemImage: "checkmark.circle")` (disabled when `open.isEmpty`); in select mode leading Select All/Deselect All, `primaryAction` Done, hide boss switcher and "+"; title "Select Tasks"/"\(n) Selected".
- [ ] Bottom bar Complete shows `confirmBatchComplete` dialog ("Complete \(n) tasks?" / "Complete \(n) Tasks") then `completeSelected()`.
- [ ] Build; run the app and check by screenshot.
- [ ] Commit.

### Task 2: UI tests
**Files:** Modify `DungeonsAndDeadlinesUITests/SmokeTests.swift`
- [ ] Replace the three `complete-<title>` checkbox flows (lines ~159, ~500, ~558) with `swipeRight` on `task-<title>` → tap "Complete".
- [ ] Add `testSwipeCompleteNeedsConfirmation` (swipe, assert row still open, tap Complete, assert row in Done), `testSelectAllAndCompleteSeveral` (menu → Select Tasks → Select All → Complete → confirm; assert "Done (n)" ), keep `tapCompleteSelected` for the bottom bar + dialog confirm.
- [ ] Run the task-related tests; then the full suite; commit.
