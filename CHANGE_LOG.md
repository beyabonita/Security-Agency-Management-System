# Project Change Log

### [2026-10-04 06:37] - Prevent Double Shifts Across Guard Roster Slots and Sites

- **Scope & Objective**: Prevent double shifts during duty scheduling so a guard assigned to Shift 1 cannot be put into Shift 2, Shift 3, or multiple shifts on the same date.
- **Files Modified / Created**:
  - [`web/admin/js/shift-roster.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/js/shift-roster.js): Enhanced `syncGuardSelections()`, `availability()`, and guard dropdown `change` listeners to detect duplicate guard assignments, update option annotations (`— (Selected in Shift X)` / `— (Already assigned at this site)`), reset duplicate slot selections to empty, and display warning toasts and red inline slot hints (`Double shift prevented`).
  - [`web/tests/schedule_lifecycle.spec.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/schedule_lifecycle.spec.js): Added test `selecting a guard for a second shift is prevented and resets the slot with warning` verifying auto-reset and warning message.
- **Verification & Testing**:
  - `npm --prefix web/tests run test:playwright -- --grep "selecting a guard for a second shift is prevented"` -> Passed (1/1).
  - All 14 roster and scheduling tests -> Passed (14/14).
- **Pending / Next Steps**:
  - Ready for user review.

### [2026-10-04 06:20] - Add Shift Time Editing to Selected Guard Shifts

- **Scope & Objective**: Enable editing existing shift times directly from the "Selected guard shifts" preview card in the Duty Scheduling console (`web/admin/schedule.html`).
- **Files Modified / Created**:
  - [`web/admin/schedule.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/schedule.html): Added `#editRosterTimesModal` with presets and loaded `bootstrap.bundle.min.js`.
  - [`web/admin/js/shift-roster.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/js/shift-roster.js): Added "Edit shift times" button in the preview header, row-level "Edit" buttons in the table, delegated event listeners, smart auto-synchronization for 24h continuous coverage, preset buttons (6–18, 7–19, 8–20), duration badges, and saving logic.
  - [`web/admin/css/dtr-scheduling.css`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/css/dtr-scheduling.css): Added styling for preview header flex layout, preset pill buttons, and modal dialog content.
  - [`web/tests/schedule_lifecycle.spec.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/schedule_lifecycle.spec.js): Added automated test verifying modal opening, preset selection, time saving, and live preview / guard slot updates.
- **Key Implementation Details**:
  - Rendered `editRosterTimesBtn` right next to the `Selected guard shifts` heading and added an `Action` column with `edit-shift-row-btn` on each shift row.
  - In the modal, auto-synchronization maintains continuous 24h coverage between Shift 1 and Shift 2 without gaps when either start or end time is changed.
  - Form submission updates the active roster setup in memory and syncs with Supabase if online, immediately refreshing `rosterPreview` and `#rosterGuards`.
- **Verification & Testing**:
  - `npm --prefix web/tests run test:playwright -- --grep "editing existing shift times"` -> Passed (1/1).
  - `npm --prefix web/tests run test:playwright -- --grep "roster"` -> Passed (12/12).
  - Node tests (`password_policy_test.js`, `official_supabase_client_test.js`, `dtr_report_test.js`, `schedule_period_test.js`) -> All passed.
- **Pending / Next Steps**:
  - Awaiting user review and confirmation before committing/pushing.
