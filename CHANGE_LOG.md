# Project Change Log

### [2026-10-04 07:02] - Update Page Header: Rename "Deployment Sites" Header to "Company"

- **Scope & Objective**: Update the page header (`<h1 class="ax-page-title">`) and document `<title>` on the Company management pages (`web/admin/locations.html` and `web/inspector/locations.html`) from "Deployment Sites" / "Duty sites" to "Company" to match the active sidebar navigation tab.
- **Files Modified / Created**:
  - [`web/admin/locations.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/locations.html): Updated `<h1 class="ax-page-title">Company</h1>` and `<title>Company — Operations Head</title>`.
  - [`web/inspector/locations.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/locations.html): Updated `<h1 class="ax-page-title">Company</h1>` and `<title>Company — Security Agency Management System</title>`.
- **Verification & Testing**:
  - `node web/tests/google_icons_test.js` -> Passed (43 bundled symbols, 145 markup references).
  - `npm --prefix web/tests run test:playwright -- --grep "ph_location_search"` -> Passed (4/4).
- **Pending / Next Steps**:
  - Ready for user commit.


### [2026-10-04 06:58] - Update Navigation Tab: Rename "Deployment Sites" to "Company"

- **Scope & Objective**: Rename the sidebar navigation tab from "Deployment Sites" to "Company" across all Admin and Inspector portal pages, matching the business entity terminology and pairing with the bundled `business` Google Material symbol.
- **Files Modified / Created**:
  - [`web/admin/dashboard.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/dashboard.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/admin/users.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/users.html): Renamed nav tab to `Company` with `business` icon, plus resolved unbundled icon `restart_alt` -> `refresh`.
  - [`web/admin/locations.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/locations.html): Renamed nav tab to `Company` with `business` icon, plus resolved unbundled icons (`badge` -> `groups`, `person_off` -> `person`, `mail` -> `person`, `call` -> `smartphone`).
  - [`web/admin/schedule.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/schedule.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/admin/incidents.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/incidents.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/admin/swaps.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/swaps.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/admin/live-tracking.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/live-tracking.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/inspector/dashboard.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/dashboard.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/inspector/users.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/users.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/inspector/locations.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/locations.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/inspector/incidents.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/incidents.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/inspector/swaps.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/swaps.html): Renamed nav tab to `Company` with `business` icon.
  - [`web/inspector/live-tracking.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/inspector/live-tracking.html): Renamed nav tab to `Company` with `business` icon.
- **Verification & Testing**:
  - `node web/tests/google_icons_test.js` -> Passed (43 bundled symbols, 145 markup references).
- **Pending / Next Steps**:
  - Ready for user commit.


### [2026-10-04 06:45] - Clean Shift Roster Preview: Remove Redundant Row Buttons and Button Icon

- **Scope & Objective**: Remove the redundant `Action` column and per-row `[Edit]` buttons from the Selected Guard Shifts preview table, and remove the icon from the top `[Edit shift times]` button for a clean, streamlined design.
- **Files Modified / Created**:
  - [`web/admin/js/shift-roster.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/js/shift-roster.js): Removed `<th scope="col">Action</th>` and row `<button>Edit</button>` from `preview.innerHTML`, removed the icon element from `#editRosterTimesBtn`, and updated click delegation.
  - [`web/tests/schedule_lifecycle.spec.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/schedule_lifecycle.spec.js): Updated test to assert absence of `.edit-shift-row-btn` and verify top button operation.
- **Verification & Testing**:
  - All 14 roster and scheduling Playwright tests -> Passed (14/14).
- **Pending / Next Steps**:
  - Ready for user commit.

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
