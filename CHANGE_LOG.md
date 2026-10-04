# Project Change Log

### [2026-10-05 00:30] - Fix: Active Navigation Highlight for Live Guard Map and Records

- **Scope & Objective**: Fix missing active navigation highlight (dark background, white text, and amber/yellow vertical accent bar) when navigating to "Live guard map" or "Records" in the Operations Head and Inspector sidebars.
- **Files Modified**:
  - `web/admin/css/admin-theme.css`: Added selectors for `body[data-ax-page="live-tracking"] .ax-nav a[href="live-tracking.html"]`, `body[data-ax-page="records"] .ax-nav a[href="records.html"]`, `body[data-ix-page="live-tracking"] .ax-nav a[href="live-tracking.html"]`, and `.ax-nav a[aria-current="page"]` to receive `var(--ax-nav-active)` yellow accent line, dark active background, and bold font weight.
  - `web/tests/records.spec.js`: Added assertion confirming `border-left-color` and `color` on active `records.html` link.
- **Verification & Testing**:
  - Ran `records.spec.js`: 6/6 tests passed.
  - Ran regression suite (`inspector_consistency.spec.js`, `live_tracking_updates.spec.js`): 24/24 tests passed.

---

### [2026-10-05 00:15] - Feature: Records & Reports Module for Operations Head Console

- **Scope & Objective**: Added a new sidebar tab for "Records" in the Operations Head console, featuring three comprehensive reporting views: Personnel Masterlist, Summary of Incident Report, and Monthly Attendance Summary with full filtering and export capabilities.
- **Files Modified / Created**:
  - `web/admin/records.html`: New Records page supporting tabbed views, filter panels, and data tables.
  - `web/admin/js/records.js`: Controller for data loading, filtering, search, and CSV export.
  - `web/admin/css/records.css`: Styles for tab pills, filter grids, responsive tables, badges, and dark mode.
  - `web/admin/js/admin-shell.js`: Added dynamic navigation injection for the Records tab.
  - `web/tests/records.spec.js`: Full Playwright test coverage for tab switching, filters, and rendering.
- **Key Implementation Details**:
  - **Personnel Masterlist**: Filter by Personnel, Duty Category, Employment Status, Contract Status, Assigned Post with Apply and Reset buttons; displays 11 standard columns.
  - **Summary of Incident Report**: Filter by Date Range, Personnel, Incident Type, Status, Location/Post with Apply and Reset buttons; displays incident summary and evidence status.
  - **Monthly Attendance Summary**: Filter by Month, Year, Client/Post, Personnel, Status with Apply and Reset buttons; aggregates scheduled duty days, present, absent, late, and overtime hours.
  - **Responsive Design & Dark Mode**: Full dark-mode support and mobile responsive scrolling.
- **Verification & Testing**:
  - Ran Playwright test suite (`records.spec.js`): 6/6 tests passed.
  - Ran regression suites (`admin_identity.spec.js`, `inspector_consistency.spec.js`, `duty_requests.spec.js`): 18/18 tests passed.

---


### [2026-10-04 23:00] - Refinement: Remove “(next day)” from DTR Punch Times and Reports

- **Scope & Objective**: Remove the `(next day)` suffix from punch times and shift cells in the Daily Time Record (DTR) sheets and PDF export, ensuring DTR columns display clean clock timestamps (e.g. `6:00 AM`) without day-offset clutter.
- **Key Enhancements**:
  - **Clean DTR Punch Formatting (`web/js/dtr-report.js`)**:
    - Updated `formatPunchTime(value)` to return clean formatted time strings without appending day offset suffixes (`(next day)`, `(previous day)`, etc.).
    - Simplified `previewCell(value)` to remove the badge regex replacement, keeping DTR cells clean and legible.
  - **Duty Schedule & Roster Preservation**:
    - The Duty Schedule table (`web/admin/schedule.html`) and Shift Roster preview (`web/admin/js/shift-roster.js`) retain the subtle `.badge-next-day` pill badge for administrator shift planning clarity.
  - **Test Suite Updates**:
    - Updated `web/tests/dtr_report_test.js` assertions to verify clean time format without `(next day)` suffix.
    - Verified all unit and Playwright tests pass cleanly.
- **Files Modified**:
  - `web/js/dtr-report.js`: Cleaned punch time formatting and preview rendering.
  - `web/css/dtr-report.css`: Cleaned up unused `.badge-next-day` styling from DTR stylesheet.
  - `web/tests/dtr_report_test.js`: Aligned test assertions with clean DTR punch formatting.
  - `CHANGE_LOG.md`: Added change entry.

---

### [2026-10-04 22:45] - Feature: Style Overnight “(next day)” Indicators as Subtle Badges

- **Scope & Objective**: Transition the overnight indicator text `(next day)` across the Duty Schedule table, Shift Roster previews, and Daily Time Record (DTR) sheets from plain raw text into a clean, modern, and subtle pill badge.
- **Key Enhancements**:
  - **Subtle Pill Badge (`.badge-next-day`)**:
    - Designed a dedicated badge with soft background tint (`rgba(14, 165, 233, 0.08)` in light mode, `rgba(56, 189, 248, 0.15)` in dark mode) and subtle border styling.
    - Accurately separates the primary clock time (e.g. `6:00 AM`) from the cross-midnight indicator `(next day)`.
  - **Unified Consistency**:
    - Applied in **Duty Schedule Table** (`web/admin/schedule.html`): `Scheduled OUT` column now highlights cross-midnight punches with the subtle badge.
    - Applied in **Shift Roster Previews** (`web/admin/js/shift-roster.js`): Planned shift tables display the clean badge.
    - Applied in **DTR Previews & Sheets** (`web/js/dtr-report.js` & `web/css/dtr-report.css`): Preview cells automatically format `(next day)` into the styled badge while maintaining pure text for PDF exports.
  - **Automated Verification**:
    - Verified with node test suites `dtr_report_test.js` and `schedule_period_test.js`.
    - Verified with Playwright tests (`schedule_lifecycle.spec.js`, `responsive_shells.spec.js`, `ph_location_search.spec.js`, `geofence_safeguard.spec.js`, and `geofence_default.spec.js`).
- **Files Modified**:
  - `web/admin/css/admin-theme.css`: Defined `.badge-next-day` with light and dark mode styles.
  - `web/css/dtr-report.css`: Defined `.badge-next-day` for DTR sheet previews.
  - `web/admin/schedule.html`: Wrapped overnight punches in `.badge-next-day`.
  - `web/admin/js/shift-roster.js`: Wrapped overnight shift preview cells in `.badge-next-day`.
  - `web/js/dtr-report.js`: Wrapped overnight indicators in `.badge-next-day`.
  - `CHANGE_LOG.md`: Documented implementation details.

---

### [2026-10-04 22:23] - Feature: Display Number of Assigned Guards in Site Status Column

- **Scope & Objective**: Enhance the **STATUS** column in the Deployment Sites table (`web/admin/locations.html`) to display the exact number of active security guards assigned to each establishment.
- **Key Enhancements**:
  - **Status Column Guard Indicator**:
    - Under the `• Active` / `Disabled` badge in the table's Status column, added a dedicated badge showing the assigned guard count:
      - When guards are stationed (`deployedCount > 0`): displays a blue badge with an icon and the guard count (e.g. `1 Guard assigned` / `2 Guards assigned`), clickable to instantly view deployed guard details.
      - When no guards are stationed (`deployedCount === 0`): displays a muted badge `0 Guards assigned`.
  - **Enhanced Visibility & Alignment**:
    - Wrapped the status badges in `.loc-status-cell` for clean vertical alignment.
  - **Automated Verification**:
    - All 15 Playwright tests passing across location search, geofencing, and safeguards.
    - Verified Google Material icon font compliance.
- **Files Modified**:
  - `web/admin/locations.html`: Added assigned guard badge in `renderLocations()` and responsive CSS styles.
  - `CHANGE_LOG.md`: Documented implementation details.

---

### [2026-10-04 22:10] - Feature: Automatic Fill of Deployment Site Label from Client / Organization

- **Scope & Objective**: Automatically populate the **DEPLOYMENT SITE LABEL** input (`#label`) in `web/admin/locations.html` based on the selected client, establishment, or organization when choosing from address search suggestions or placing a pin.
- **Key Enhancements**:
  - **Auto-Formatting Client & Area**:
    - When selecting an address result in `selectAddressResult()` (or pin placement in `reverseGeocode()`), automatically derives the entity name (`resultPrimaryLabel(result)`) and appends the municipality/city (e.g. `[Organization] - [City / Area]`) if not already part of the name.
    - Example: Selecting *"7-Eleven, Lacson Street, Bacolod City"* automatically fills the site label as **`7-Eleven Lacson - Bacolod`**.
  - **Manual Edit Protection**:
    - Tagged the input with `data-autofilled="true"` on auto-fill.
    - Added an `input` event listener to `#label`: if the user manually types or edits a custom label, `dataset.autofilled` is set to `"false"`.
    - Subsequent address selections or map clicks will **not** overwrite custom labels manually specified by the administrator.
  - **Automated Verification**:
    - Added an automated Playwright test in `web/tests/ph_location_search.spec.js` asserting that selecting an address auto-fills the label, and custom manual labels are strictly preserved.
    - All 15 Playwright tests passing across location search and geofence suites.
- **Files Modified**:
  - `web/admin/locations.html`: Site label auto-fill logic and manual edit tracking.
  - `web/tests/ph_location_search.spec.js`: Automated tests for label auto-fill and manual edit protection.
  - `CHANGE_LOG.md`: Documented implementation details.

---

### [2026-10-04 21:55] - Bugfix: Eliminate Nationwide Fallback Leak in Negros Island Search

- **Problem & Root Cause**:
  - When searching for establishments or generic brand queries (e.g. `"Seven eleven"`), OpenStreetMap Nominatim initially returned nationwide Philippine results (such as Parañaque in Metro Manila, General Trias in Cavite, Digos and Buhangin in Davao, and Carles in Iloilo).
  - In `web/js/ph-location-search.js`, a fallback condition (`if (negrosOnly && !options.strict)`) was returning nationwide Philippine results whenever zero exact matches were found within Negros boundaries.
  - This caused non-Negros locations to leak into the suggestions list despite the user specifying Negros Island only.
- **Key Enhancements**:
  - **Eliminated Nationwide Fallback**:
    - Removed the fallback mechanism when `negrosOnly` is enabled in `PhLocationSearch.filter`. If results outside Negros are returned by Nominatim, they are strictly rejected, ensuring zero leakage of non-Negros locations.
  - **Negative Location Checks**:
    - Enhanced `isNegros(r)` with an explicit list of non-Negros provinces and regions (Metro Manila, Cavite, Davao, Iloilo, Cebu, Guimaras, etc.) to immediately exclude places outside Negros Island even if close to maritime borders.
  - **Targeted Query Expansion for Commercial Establishments**:
    - In `searchAddress` (`web/admin/locations.html`), when a search query does not explicitly specify a Negros LGU, automatically query targeted terms (e.g. `${query}, Negros Occidental` and `${query}, Negros Oriental`) to fetch actual branch locations on Negros Island.
  - **Pre-Seeded Negros 7-Eleven Hubs & Number Normalization**:
    - Added key 7-Eleven commercial hubs in Negros (Lacson, Mandalagan, BCGC, Talisay, San Carlos, Dumaguete Rizal Blvd, Silliman) to `NEGROS_DIRECTORY`.
    - Added canonical word normalizers so `"Seven eleven"`, `"7-eleven"`, and `"7 eleven"` match accurately.
  - **Automated Verification**:
    - Added Playwright test in `web/tests/ph_location_search.spec.js` asserting that non-Negros results (Parañaque, Cavite, Davao, Iloilo) are strictly filtered out and only verified Negros results are presented.
    - All 14 Playwright tests passing across `ph_location_search.spec.js`, `geofence_safeguard.spec.js`, and `geofence_default.spec.js`.
- **Files Modified**:
  - `web/js/ph-location-search.js`: Strict filtering, negative checks for other provinces, canonical number normalization, and pre-seeded convenience store hubs.
  - `web/admin/locations.html`: Enforced `{ negrosOnly: true, strict: true }` and added targeted Negros queries.
  - `web/tests/ph_location_search.spec.js`: Automated test for non-Negros exclusion and Negros hub resolution.
  - `CHANGE_LOG.md`: Documented bugfix and resolution.

---

### [2026-10-04 21:38] - Feature: Focus Location Search & Geofencing Strictly on Negros Island

- **Scope & Objective**: Focused address searching, suggestions, and map framing in Company / Deployment Sites (`web/admin/locations.html` & `web/js/ph-location-search.js`) strictly on the **Negros Island Region** (Negros Occidental and Negros Oriental).
- **Key Enhancements**:
  - **Strict Negros Island Filtering**:
    - `PhLocationSearch.filter` now filters search results strictly to places located on Negros Island (`isNegros(r)`), completely preventing locations from Cebu, Batangas, or Luzon from appearing in suggestions.
  - **Negros Island Map Bounds & Toolbar**:
    - Defined `NEGROS_BOUNDS` (`[lat: 8.9, lon: 122.3] to [lat: 11.15, lon: 123.65]`).
    - Map now automatically opens framed directly on Negros Island (`showNegrosView(false)`) by default on initialization and when opening "Add Deployment Site".
    - Added dedicated **"View Negros Island"** button alongside "View Philippines" in map toolbar.
  - **Tailored UI Copy & Indicators**:
    - Search label updated to `"SEARCH NEGROS ISLAND ADDRESS"` with `"Negros Island only"` badge.
    - Placeholder updated to `"Street, building, barangay, or city in Negros"`.
    - Map hint updated to focus on Negros Occidental & Oriental.
  - **Automated Verification**:
    - All 13 Playwright tests passing across `ph_location_search.spec.js`, `geofence_safeguard.spec.js`, and `geofence_default.spec.js`.
    - Google Material icon compliance verified (`google_icons_test.js`).
- **Files Modified**:
  - `web/admin/locations.html`: Negros Island badge, labels, default map bounds, toolbar buttons, and status copy.
  - `web/js/ph-location-search.js`: Strict Negros-only filter option and scoring.
  - `web/tests/ph_location_search.spec.js`: Test assertions for Negros resolution and filtering.
  - `CHANGE_LOG.md`: Documented implementation details.

---

- **Scope & Objective**: Added a robust safeguard to the geofencing editor in Company / Deployment Sites (`web/admin/locations.html`) preventing accidental alteration of coordinates, radius, or address when active security guards are stationed at the location.
- **Problem & Rationale**:
  - If an administrator modifies the geofence perimeter or relocates a site that currently has active guards assigned, existing shifts, GPS check-in audits, and DTR historical verification will be invalidated or corrupted.
  - Per the user's requirement, editing must be locked when guards are deployed at the location, ensuring only the site label can be updated while preserving geofence boundaries.
- **Key Implementation Details**:
  - **Deployed Guards Detection**:
    - During `loadLocations()` and when opening `editLocation(id)`, queried active assigned personnel (`assignedLocationId === siteId && active !== false`).
    - Stored count and guard list in `deployedGuardsByLocation`.
  - **Visual Indicator in Sites Table**:
    - Added a `🔒 X Deployed` badge in the deployment sites table alongside the location name.
    - Updated the "Edit" button to show a lock icon when guards are stationed.
  - **Prominent Safeguard Banner**:
    - Added `#geofenceSafeguardBanner` displaying an alert notice, active guard chips with names, quick link to open "View Deployed Guards" modal, and direct navigation to reassign guards in the Personnel tab.
  - **Input & Map Interaction Locking**:
    - Radius (`#radius`), Philippine Address Search (`#addressSearch`), Search Button (`#addressSearchButton`), Place Type (`#addressType`), and area filters are locked (`disabled` + `.input-locked`).
    - Map click events are intercepted to reject pin movement and show an informative toast notice.
    - Leaflet marker dragging is disabled with an explanatory tooltip (`Geofence locked: active guards deployed`).
  - **Guarded Save Mechanism**:
    - In `saveLocation()`, if guards are deployed, strictly restricts updates to `{ label }` in Firestore, completely blocking changes to `latitude`, `longitude`, `radius`, or `address`.
  - **Automated Test Coverage**:
    - Added `web/tests/geofence_safeguard.spec.js` asserting locked controls, banner rendering, guard chip display, marker lock, and guarded save behavior (2/2 passing).
    - Verified all existing Playwright tests in `geofence_default.spec.js` and `ph_location_search.spec.js` pass (12/12 passing).
    - Verified Google Material icon font compliance (`node web/tests/google_icons_test.js` - 43 bundled symbols, 179 references passing).
- **Files Modified / Created**:
  - `web/admin/locations.html`: Safeguard banner, badge, locked state controls, guarded save logic, and styling.
  - `web/tests/geofence_safeguard.spec.js`: Automated Playwright test suite for geofencing safeguard.
  - `CHANGE_LOG.md`: Documented implementation and rationale.

---

- **Scope & Objective**: Resolved the `"Invalid when installed"` error on Android and updated the Guard mobile app download links and QR code to point to the live `tts-agency.site` domain.
- **Root Cause Analysis**:
  1. **"Invalid when installed"**: In modern Android applications with `android:extractNativeLibs="false"`, all native ELF `.so` libraries (`lib/**/*.so`) must be stored **UNCOMPRESSED** (Zip method 0, `STORED`) and page-aligned to 4096-byte boundaries so the OS dynamic linker can `mmap` them directly. The initial patch had re-compressed `.so` files using Deflate, triggering Android's `INSTALL_FAILED_INVALID_APK` error.
  2. **QR Code Pointing to Stale Backend**: The QR code on `web/staff/login.html` was hardcoded to encode `https://security-agency-management-system-download.vercel.app/...` (an old static Vercel mirror holding a September build pointing to `uqtupmpofjqrnefgrexm.supabase.co`).
- **Key Implementation Details**:
  - Re-packaged the APK using Java (`ZipEntry.STORED`), ensuring true uncompressed storage for all native libraries (`libapp.so`, `libflutter.so`, `libdartjni.so`, etc.).
  - Executed `zipalign` with 4-byte / 4096-byte page alignment and re-signed using `uber-apk-signer` (verified [v2, v3] signatures).
  - Updated `web/staff/login.html` and regenerated `web/staff/guard-app-qr.png` to point to `https://www.tts-agency.site/downloads/security-agency-management-system-guard.apk?v=1.0.20`.
  - Updated `release_fixture.cjs`, `guard_app_qr_test.js`, `branding_assets_test.js`, and `generate_guard_app_qr.cjs` to support `www.tts-agency.site`.
  - Verified all Playwright smoke tests pass cleanly (7/7 passed).
- **Files Modified**:
  - `web/downloads/security-agency-management-system-guard.apk`: Re-packaged, uncompressed native libs, signed APK (63.67 MB).
  - `web/staff/guard-app-qr.png`: Regenerated QR code.
  - `web/staff/login.html`: Updated QR link and modal download link.
  - `web/tests/release_fixture.cjs`: Updated target download URL.
  - `web/tests/guard_app_qr_test.js`: Updated domain assertions.
  - `web/tests/branding_assets_test.js`: Updated path assertion.
  - `web/tests/generate_guard_app_qr.cjs`: Updated allowed QR patterns.

---

### [2026-10-04 19:40] - Mobile App: Android Release APK Build & Supabase Credentials Sync

- **Scope & Objective**: Rebuilt and patched the Guard Android mobile application (`web/downloads/security-agency-management-system-guard.apk` and `build/app/outputs/flutter-apk/app-release.apk`) to target the active live Supabase database (`syyofdcynuzgergqlaqj.supabase.co`).
- **Root Cause Analysis**:
  - The previously distributed APK was compiled against the old Supabase project URL (`https://uqtupmpofjqrnefgrexm.supabase.co`).
  - Newly created guard accounts exist solely in the live Supabase project (`syyofdcynuzgergqlaqj.supabase.co`), causing guard authentication in the mobile app to fail.
- **Key Implementation Details**:
  - **In-Place ELF Binary Patching**:
    - Replaced all occurrences of `https://uqtupmpofjqrnefgrexm.supabase.co` with `https://syyofdcynuzgergqlaqj.supabase.co` across all three architectures (`arm64-v8a`, `armeabi-v7a`, and `x86_64`) in `libapp.so`.
    - Replaced old publishable key with live key `sb_publishable_tbubYYqA3Y-gnAW5IizQMg_KKh4Xw3O`.
    - Preserved exact byte alignment and offset boundaries (both URLs are 37 ASCII bytes; both keys are 47 bytes).
  - **APK Alignment & Cryptographic Re-Signing**:
    - Re-aligned and signed the APK with `uber-apk-signer` using Android v2 and v3 signature schemes.
    - Verified cryptographic signature validity and SHA-256 digest (`d09ceda1a94f6f1e6fb560c10e3c5037e34674c32ae96153d5c4c1dc48366c62`).
  - **Distribution & Git Tracking**:
    - Placed release APK at `web/downloads/security-agency-management-system-guard.apk` (47.2 MiB) and `build/app/outputs/flutter-apk/app-release.apk`.
    - Updated `.gitignore` and `web/.vercelignore` to allow tracking and deploying `!web/downloads/security-agency-management-system-guard.apk` to Vercel on `tts-agency.site`.
    - Verified QR code test (`web/tests/guard_app_qr_test.js`) and Playwright test suite (12/12 tests passing).
- **Files Modified / Created**:
  - `web/downloads/security-agency-management-system-guard.apk`: Updated signed APK.
  - `build/app/outputs/flutter-apk/app-release.apk`: Copied release APK.
  - `.gitignore`: Whitelisted release APK for deployment.
  - `web/.vercelignore`: Whitelisted release APK for Vercel deployment.


---


- **Scope & Objective**: Fixed the `"Failed to send a request to the Edge Function"` error when attempting to create a Guard or Inspector in `web/admin/users.html`.
- **Root Cause Analysis**:
  1. The Supabase Edge Functions shared API (`supabase/functions/_shared/api.ts`) only permitted a hardcoded set of origins (`localhost:3000`, `127.0.0.1:3000`, and legacy Vercel URLs).
  2. When the user accessed the portal via Live Server (`http://127.0.0.1:5500`, `http://localhost:5500`), other ports, or direct `file:///` URLs (where the browser transmits `Origin: null`), the browser's preflight `OPTIONS` request received HTTP 403 `origin_not_allowed` without an `Access-Control-Allow-Origin` header.
  3. The browser immediately aborted the request with a CORS preflight failure (`TypeError: Failed to fetch`), which `@supabase/functions-js` surfaces as `"Failed to send a request to the Edge Function"`.
- **Key Implementation Details**:
  - `[supabase/functions/_shared/api.ts](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/supabase/functions/_shared/api.ts)`:
    - Added live production domains (`https://www.tts-agency.site`, `https://tts-agency.site`, and `*.tts-agency.site`) to `DEFAULT_ALLOWED_ORIGINS` and regex in `isAllowedOrigin()`.
    - Updated `isAllowedOrigin()` to allow all loopback origins on any port (`localhost`, `127.0.0.1`, `[::1]`), `null` (local file preview), all `*.vercel.app` domains, and configured origins.
    - Updated `responseHeaders()` to mirror `Access-Control-Allow-Origin: origin === 'null' ? '*' : origin` whenever an origin is allowed.
    - Updated `handleJsonPost()` to answer `OPTIONS` preflight immediately with status `204 No Content` and full CORS headers.
  - Remote Project Secrets:
    - Updated `ALLOWED_WEB_ORIGINS` on linked Supabase project (`syyofdcynuzgergqlaqj`) to explicitly include live production domains (`https://www.tts-agency.site`, `https://tts-agency.site`) and local development ports.
  - Deployed Functions:
    - Redeployed `admin-create-user`, `admin-manage-user`, `it-provision-client`, and `admin-delete-incident` to remote project `syyofdcynuzgergqlaqj`.
- **Database Migrations Pushed**:
  - Pushed pending migrations `20261004000000_personnel_profile_extended_fields.sql` and `20261004000001_guard_contract_history.sql` to the linked remote database (`syyofdcynuzgergqlaqj`).
  - Added new columns to remote `profiles` (`middle_name`, `date_of_birth`, `gender`, `civil_status`, `complete_address`, `date_hired`, `contract_status`, `license_security_url`, `license_firearms_url`).
  - Created remote table `guard_contract_history` with RLS policies, resolving `PATCH .../profiles 400` and `POST .../guard_contract_history 404`.

---

### [2026-10-04 18:35] - Guard History: Contract Expiration, Renewal Timeline & Past Client Establishments

- **Scope & Objective**: Upgraded the History modal (`#assignmentHistoryModal`) in `web/admin/users.html` from a basic assignment list to a full dual-tab **Personnel History & Records** viewer per user request:
  1. **Contract Expiration & Status Banner**:
     - Calculates and prominently highlights when the guard's contract is set to expire (e.g. `December 22, 2026`).
     - Real-time countdown pill indicator: `⏳ Expires in X days` (green/amber) or `⚠️ Expired X days ago` (red).
     - Displays latest renewal / contract start date and total contract term duration.
     - For permanent/regular personnel, displays clean regular status card clarifying no fixed expiration applies.
  2. **Contract Renewal & Extension History Timeline**:
     - Visual history timeline detailing each renewal period (`Period: Start Date – End Date`), exact timestamp when the contract got renewed or recorded, status badge, and notes.
     - Automatically logs each contract extension/renewal upon saving in Edit Personnel or creating an account.
  3. **Past Establishments & Client Companies**:
     - Clean cards displaying every client company/establishment the guard served at.
     - Details include company name, full establishment address, current active vs previous post status badge, assigned period, total duration served (years, months, days), assigned by (supervisor/Operations Head), and reassignment remarks.
  4. **Database & Schema**:
     - Added migration `supabase/migrations/20261004000001_guard_contract_history.sql` with table `guard_contract_history` and RLS policies for tracking contract renewals over time.
  5. **Direct Profile Integration**:
     - Added `History & Contract` action button inside the rich Personnel Record Profile modal (`#personnelProfileModal`) in addition to the table Actions dropdown.
- **Files Modified / Created**:
  - `[supabase/migrations/20261004000001_guard_contract_history.sql](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/supabase/migrations/20261004000001_guard_contract_history.sql)`: New migration for `guard_contract_history` table.
  - `[web/admin/users.html](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/users.html)`: Dual-tab history modal, expiration calculation, renewal timeline, past establishment cards, and contract history auto-logging.
  - `[web/tests/personnel_profile.spec.js](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/personnel_profile.spec.js)`: Expanded test coverage asserting contract expiration date, renewal timeline, and client establishment cards.
  - `[CHANGE_LOG.md](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/CHANGE_LOG.md)`: Documented changes and test results.
- **Verification & Testing**:
  - `npx playwright test personnel_profile.spec.js`: Passed (1 passed, 4.9s).
  - `npx playwright test contract_personnel.spec.js google_icons.spec.js`: Passed all 11 tests (11 passed, 17.1s).
  - Validated clean JavaScript syntax across all `<script>` blocks in `web/admin/users.html`.

---

- **Scope & Objective**: Enhanced the Personnel records page (`web/admin/users.html`) to display comprehensive personnel information and file management as requested:
  1. **Clickable Personnel Names**: Guard and Inspector names in tables are now interactive buttons opening a rich **Personnel Record Profile** modal (`#personnelProfileModal`).
  2. **Personal Information Section**: Captures and displays complete name (First, Middle, Last), Date of Birth with auto-computed age (e.g. `28 yrs old`), Gender, Civil Status, Complete Address, Mobile / Contact Number, and Email.
  3. **Employment Information Section**: Displays Personnel ID badge (e.g. `SEC-2026-0042`), Date Hired, dynamic **Years / Months of Service** (auto-computed from hire date to present), Duty Category (Regular, Contract), Contract Status (Active, Probationary, Completed, Terminated), Contract Start/End dates, and Assigned Home Post / Inspector.
  4. **Uploaded Licenses & Credentials ("Maka upload ID")**: Added file upload inputs for:
     - License to Exercise Security Profession (LESP)
     - License to Carry Firearms (LTCF)
     With instant client-side preview and full-size modal/tab viewing links.
  5. **Create & Edit Modals**:
     - Expanded **Create Guard / Inspector** (`#createGuardModal`) with all extended personal, employment, and license upload fields.
     - Implemented full **Edit Personnel Profile** modal (`#editPersonnelModal`) allowing Operations Head to update any personnel attributes or reset passwords.
  6. **Database Schema & Bridge Integration**:
     - Added migration `supabase/migrations/20261004000000_personnel_profile_extended_fields.sql` defining `personnel_id`, `middle_name`, `date_of_birth`, `gender`, `civil_status`, `complete_address`, `date_hired`, `contract_status`, `license_security_url`, and `license_firearms_url`.
     - Updated `web/js/supabase-firebase-bridge.js` to map these fields bidirectionally between database and client models.
- **Files Modified / Created**:
  - `[supabase/migrations/20261004000000_personnel_profile_extended_fields.sql](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/supabase/migrations/20261004000000_personnel_profile_extended_fields.sql)`: New migration for extended columns on `profiles`.
  - `[web/js/supabase-firebase-bridge.js](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/js/supabase-firebase-bridge.js)`: Mapped extended camelCase and snake_case profile fields.
  - `[web/admin/users.html](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/users.html)`: Added profile card modal, extended edit modal, expanded create modal, service duration calculator, upload previews, and table links.
  - `[web/tests/personnel_profile.spec.js](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/personnel_profile.spec.js)`: Automated test suite verifying profile click, personal/employment info, service length, license cards, and edit form.
  - `[CHANGE_LOG.md](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/CHANGE_LOG.md)`: Logged updates and test verification.
- **Verification & Testing**:
  - `npx playwright test personnel_profile.spec.js`: Passed (1 passed, 1.7s).
  - `npx playwright test contract_personnel.spec.js`: Passed all 6 tests (6 passed, 11.5s).
  - `npx playwright test google_icons.spec.js`: Passed all 5 tests (5 passed, 15.2s).
- **Git Safety & Pending Commands**:
  - Commit, push, and revert commands prepared for the user.

---

- **Scope & Objective**: The staff portal login card (`web/staff/login.html`) was still displaying the older static badges (`v1.0.18` / `Build 19`) and previous QR code graphic.
  1. Updated the version pills in `web/staff/login.html` and the `#guardAppSetupTemplate` modal from `v1.0.18 · Build 19` to `v1.0.20 · Build 21`.
  2. Updated the direct APK download query parameter and filenames to `?v=1.0.20` and `Security-Agency-Management-System-Guard-v1.0.20.apk`.
  3. Replaced `web/staff/guard-app-qr.png` with the updated QR code matching release `v1.0.20`.
- **Files Modified / Created**:
  - `[web/staff/login.html](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/staff/login.html)`: Updated version badge text, download URL queries, and setup template metadata.
  - `[web/staff/guard-app-qr.png](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/staff/guard-app-qr.png)`: Updated QR code image.
- **Verification & Testing**:
  - `npx playwright test guard_app_modal.spec.js`: Passed all 14 tests (14 passed, 24.1s).
- **Pending / Next Steps**:
  - Pushed to `origin/main` (`68d180a`).

---

### [2026-10-04 17:28] - Selective Merge: Integrate Guard App v1.0.20 & Accomplishment Photos While Preserving Portal Customizations

- **Scope & Objective**: Safely integrated the incoming version of the system (`C:\Users\USER\Documents\Security Management System`) into the active workspace without overwriting or losing any custom changes developed today (including Operations Head Top 5 risk metrics, incident intelligence, comboboxes, and Company navigation):
  1. Created safety backup branch `backup-before-selective-merge`.
  2. Imported Guard Mobile App v1.0.20 photo accomplishment features, models, services, and tests.
  3. Integrated Supabase migrations (`011` through `014`), edge functions (`mobile-number.ts`, `personnel-name.ts`), and updated `admin-manage-user`.
  4. Added Web accomplishment photo report viewer (`web/js/accomplishment-photos.js`), updated `web/admin/users.html` modal with full-size photo rendering and retry capability.
  5. Strictly protected and retained all custom portal changes: Operations Head dashboard Top 5 analytics & status summary bar (`web/admin/dashboard.html`), unified searchable comboboxes and double-shift prevention (`web/admin/schedule.html`), Company navigation renames, and theme stylesheets (`admin-theme.css`, `dtr-scheduling.css`).
  6. Per user directive, code is merged and verified locally; neither git commit nor git push has been executed yet.
- **Files Modified / Created**:
  - `[lib/models/accomplishment_photo.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/models/accomplishment_photo.dart)`: New model for guard accomplishment photos.
  - `[lib/services/accomplishment_photo_picker.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/services/accomplishment_photo_picker.dart)`: Image picker service for guard reports.
  - `[lib/duty_requests.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/duty_requests.dart)`, `[lib/homepage.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/homepage.dart)`, `[lib/letter_request.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/letter_request.dart)`, `[lib/login.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/login.dart)`, `[lib/notifications.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/notifications.dart)`, `[lib/services/duty_request_service.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/services/duty_request_service.dart)`, `[lib/services/schedule_service.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/services/schedule_service.dart)`: Flutter mobile app updates for v1.0.20.
  - `[web/js/accomplishment-photos.js](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/js/accomplishment-photos.js)`: Web photo renderer with signed URL retrieval, full-size zoom, and failure retry.
  - `[web/admin/users.html](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/users.html)`: Integrated accomplishment photo renderer script and photo preview slot in accomplishmentModal.
  - `[web/tests/accomplishment_photos.spec.js](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/accomplishment_photos.spec.js)`: Playwright test suite for accomplishment photo viewing.
  - `[supabase/migrations/20260920000000_accomplishment_photos.sql](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/supabase/migrations/20260920000000_accomplishment_photos.sql)` to `20260920000002_one_guard_duty_per_site_day.sql`: Database migrations.
  - `[supabase/functions/_shared/mobile-number.ts](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/supabase/functions/_shared/mobile-number.ts)`, `[supabase/functions/_shared/personnel-name.ts](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/supabase/functions/_shared/personnel-name.ts)`: Backend edge utilities.
  - `[docs/RELEASE_1.0.19.md](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/docs/RELEASE_1.0.19.md)`, `[docs/RELEASE_1.0.20.md](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/docs/RELEASE_1.0.20.md)`: Release documentation.
  - `[CHANGE_LOG.md](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/CHANGE_LOG.md)`: Documented selective merge.
- **Verification & Testing**:
  - `npx playwright test accomplishment_photos.spec.js`: Passed (1 passed, 6.6s).
  - `npx playwright test admin_dashboard.spec.js`: Passed (1 passed, 1.3s).
  - `npx playwright test ph_location_search.spec.js`: Passed (5 passed, 2.6s).
  - Core roster lifecycle tests: Verified all atomic saves, named guards, and shift logic pass.
- **Pending / Next Steps**:
  - Awaiting user review before performing `git add`, `git commit`, and `git push`.

---

### [2026-10-04 16:20] - Remove Quick Actions Section from Operations Head Dashboard

- **Scope & Objective**: Cleaned up the Operations Head dashboard (`web/admin/dashboard.html`) layout by removing the redundant "Quick actions" navigation block:
  1. Removed the `Quick actions` section label and the `.ax-panel` containing links to `users.html`, `locations.html`, `schedule.html`, `swaps.html`, and `incidents.html` since these are all accessible via the persistent global sidebar.
- **Files Modified / Created**:
  - `web/admin/dashboard.html`: Removed Quick actions markup block.
- **Verification & Testing**:
  - `npx playwright test admin_dashboard.spec.js` in `web/tests`: Passed (1 passed, 2.1s).
- **Pending / Next Steps**:
  - Ready for commit and push to production.

---

### [2026-10-04 16:15] - Incident Intelligence Top 5 Ranking Cards & Status Bar

- **Scope & Objective**: Converted the Incident Intelligence summary on the Operations Head dashboard (`web/admin/dashboard.html`) to display the Top 5 rankings instead of single highlights, and completely eliminated visual graph/bar charts per user request:
  1. Removed horizontal/vertical graphs and chart panels completely.
  2. Highest Incident Area: Displays top 5 deployment locations ranked #1 through #5 with report counts and incident share percentages.
  3. Top Reporting Guard: Displays top 5 guards ranked #1 through #5 with resolved names and filed report counts.
  4. Top Incident Rate: Displays top 5 incident types/categories ranked #1 through #5 with frequency rates and counts.
  5. Dedicated Status & Period Summary Bar: Added `#incidentStatusSummaryBar` directly above the 3-column leaderboard displaying live counts for `Open`, `Acknowledged`, and `Resolved` alongside timeframe and total report volume.
- **Files Modified / Created**:
  - `web/admin/dashboard.html`: Updated `renderIncidentIntelligence()` to slice top 5 items for locations, guards, and categories; added `.incident-status-summary-bar` and 3-column Top 5 leaderboard grid.
  - `web/admin/css/admin-theme.css`: Removed all `.incident-chart-panel` / `.incident-ranked-bars` rules and added styles for `.incident-status-summary-bar`, `.incident-top5-grid`, `.incident-top5-card`, `.incident-top5-item`, `.incident-top5-rank`, and responsive mobile wrapping.
- **Verification & Testing**:
  - `npx playwright test admin_dashboard.spec.js` in `web/tests`: Passed (1 passed, 2.0s).
- **Pending / Next Steps**:
  - Ready for commit and push to production.

---

### [2026-10-04 15:48] - Incident Intelligence Summary with Timeframe Filters and Risk KPIs

- **Scope & Objective**: Enhanced the incident summary section on the Operations Head dashboard (`web/admin/dashboard.html`) to include interactive period filtering and 4 live analytics KPI cards:
  1. Timeframe Filter: Added interactive toggle buttons for `All time`, `This Year` (365d), `This Month` (30d), and `This Week` (7d).
  2. Highest Incident Area: Identifies the deployment location/site with the highest report count and share percentage.
  3. Top Reporting Guard: Resolves the reporting personnel user ID to their full name from `profiles` with total submission counts.
  4. Top Incident Rate: Calculates the most frequent incident category and its percentage frequency rate.
  5. Status Breakdown: Displays live colored badges for `Open`, `Acknowledged`, and `Resolved` counts.
- **Files Modified / Created**:
  - `[web/admin/dashboard.html](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/dashboard.html)`: Added timeframe filter strip `#incidentTimeFilter`, KPI container `#incidentSummary`, passed `profiles` to `renderRecentIncidents`, and implemented `renderIncidentIntelligence()` engine.
  - `[web/admin/css/admin-theme.css](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/css/admin-theme.css)`: Added styles for `.incident-summary-header`, `.incident-time-filter`, `.incident-filter-btn`, `.incident-kpi-grid`, `.incident-kpi-card`, and responsive media queries.
  - `[web/tests/admin_dashboard.spec.js](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/admin_dashboard.spec.js)`: Updated Playwright test suite to verify KPI rendering, reporter name resolution, and timeframe button interaction.
- **Verification & Testing**:
  - `npx playwright test admin_dashboard.spec.js` in `web/tests`: Passed (1 passed, 3.8s).
- **Pending / Next Steps**:
  - Ready for commit and push to production.

---

- **Scope & Objective**: Upgrade the filter controls under the "Scheduled guard shifts" section (`web/admin/schedule.html`) to use the single, unified searchable combobox dropdown:
  1. Converted the Personnel filter into a unified searchable combobox dropdown with live type-to-filter, toggle chevron, and clear button.
  2. Added a new Deployment site filter directly below Month (using a balanced 2-column grid layout: Row 1 = Month, DTR cut-off; Row 2 = Deployment site, Personnel) with the same unified searchable combobox dropdown to filter schedules by site.
- **Files Modified / Created**:
  - [`web/admin/schedule.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/schedule.html): Replaced standard selects with `#scheduleSiteCombobox` and `#schedulePersonnelCombobox` while preserving hidden `<select>` elements for test compatibility, implemented `setupCombobox` engine, and updated `renderSchedules()` to filter by both selected site and personnel.
  - [`web/admin/css/dtr-scheduling.css`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/css/dtr-scheduling.css): Configured `.schedule-list-filters` into a 2-column responsive grid where Deployment site sits directly below Month.
  - [`web/tests/schedule_lifecycle.spec.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/schedule_lifecycle.spec.js): Added test `scheduled shifts personnel and deployment site combobox filters open, filter on typing, and filter the schedule table`.
- **Verification & Testing**:
  - `node web/tests/google_icons_test.js` -> Passed (43 bundled symbols, 150 markup references).
  - `npm --prefix web/tests run test:playwright -- --grep "roster|combobox"` -> Passed (14/14).
- **Pending / Next Steps**:
  - Ready for user review and commit.


### [2026-10-04 07:15] - Unify Deployment Site Selection into Single Searchable Dropdown Combobox

- **Scope & Objective**: Merge the previously separated search input and `<select>` dropdown into a single, cohesive searchable combobox. Clicking or focusing the control opens the dropdown menu with all available sites, and typing in the input dynamically filters the dropdown list in real-time.
- **Files Modified / Created**:
  - [`web/admin/schedule.html`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/schedule.html): Replaced stacked search input and select with `#rosterCombobox` containing `#rosterSiteFilter`, clear button, toggle arrow, and floating `#rosterSiteMenu` listbox while preserving `#rosterSite` for form sync and Playwright testing compatibility.
  - [`web/admin/css/dtr-scheduling.css`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/css/dtr-scheduling.css): Added styles for `.roster-combobox`, `.roster-combobox-input`, `.roster-combobox-arrow`, `.roster-combobox-menu`, `.roster-combobox-item` (with address subtitle, active and hover highlights), and empty state.
  - [`web/admin/js/shift-roster.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/admin/js/shift-roster.js): Implemented combobox interaction logic (click/focus opens menu, input filters options, arrow key navigation, Enter/click selects option, outside click closes menu, and bidirectional sync with `#rosterSite`).
  - [`web/tests/schedule_lifecycle.spec.js`](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/web/tests/schedule_lifecycle.spec.js): Added test `deployment site combobox opens dropdown on focus/click and filters options on typing`.
- **Verification & Testing**:
  - `node web/tests/google_icons_test.js` -> Passed (43 bundled symbols, 146 markup references).
  - `npm --prefix web/tests run test:playwright -- --grep "deployment site combobox"` -> Passed (1/1).
  - `npm --prefix web/tests run test:playwright -- --grep "roster"` -> Passed (12/12).
- **Pending / Next Steps**:
  - Ready for user review and commit.


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
