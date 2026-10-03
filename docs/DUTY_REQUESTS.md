# Guard duty requests

## Absence

1. Guard opens **Letter Requests → Absence**, chooses their duty period, enters a reason and attaches a PDF/JPG/PNG letter (up to 5 MB).
2. Admin reviews it under **Duty requests** and approves or rejects it.
3. Approval cancels only the selected period. It disappears from **My Schedule** and cannot accept Time In. The decision and original duty remain in the audit trail; existing attendance is never erased.

A Morning absence does not also cancel Afternoon or Overtime. Submit a separate request for each period that needs approval.

## Reciprocal swap

1. Guard opens **Letter Requests → Swap** and selects their own duty.
2. Select **Swap with another Guard’s duty**. The choice shows the Guard, date, period, times and post.
3. Attach the letter, explain the exchange, then send it to Admin.
4. Admin sees both resulting assignments. Approval exchanges both duties in one transaction; rejection changes neither. Both Guards receive notifications after approval.

Example: Guard A offers Monday morning at Post A and selects Guard B’s Tuesday afternoon at Post B. After approval, A works Tuesday afternoon at Post B; B works Monday morning at Post A. The dates, times, post/geofence and DTR columns stay attached to their original duty periods.

Only active Guards within the same agency appear. Both posts must be active. Ended, cancelled, draft, completed, already-punched or pending-request duties are excluded. The exchange must not overlap either Guard’s other duties. The server checks these rules again at submission and approval; changed duty details require a fresh request. Other Guards’ attendance and private request letters remain inaccessible.

Requests submitted by an older installed app without a selected peer duty are displayed as **Coverage**. Admin can still assign a replacement for that one duty; they are not silently converted to reciprocal exchanges.

## Attendance

There is one action button: **Time In**, switching to **Time Out** when the server confirms an open duty. It is disabled while checking/recording attendance. A fresh GPS reading and the scheduled post’s geofence remain required. After Time Out, it returns to Time In for the next eligible period.

My Schedule refreshes on schedule changes, notifications, app resume, and a 20-second fallback for missed realtime events. Approved absences remain visible in Letter Requests.

## Development release

These Guard changes are source-only until an Android build is explicitly requested. Test using `flutter run` from this project; use a hot restart (`R`) if it is already running. The downloadable Android version is unchanged.

Backend migrations: `20260905000002_reciprocal_duty_swaps.sql` and `20260905000003_bind_exchange_to_current_agency.sql`. Tests: `008_reciprocal_duty_swaps.sql`, `schedule_actions_test.dart`, `letter_request_screen_test.dart`, and `web/tests/duty_requests.spec.js`.

## Pending local attendance update (September 13, 2026)

The attendance page replaces the open-duty description and DTR mapping card
with Actual Time In and Actual Time Out, including dates for overnight duties.
It restores the latest recorded session on reopening; an unrecorded punch stays
"Not recorded" and is never filled from the schedule.

Guard Time Out now uses a fresh, non-mock GPS fix (accuracy no worse than 100 m)
and checks the original attendance session's post. Missing GPS or being outside
that geofence does not close the session. Existing shift-end verification rules
continue to apply. Migration `20260913000002_require_timeout_at_duty_post.sql`
removes the server's missing/outside-coordinate fallback while preserving
historical records and Operations Head verification.

This update is local only: no APK build and no database or web deployment.
Apply the migration when deployment is authorized; the currently published APK
and backend still use the previous behavior until updated.

## Pending local report input update

Accomplishment summary and narrative accept short, non-empty entries without
10/20-character minimums. Existing maximum lengths remain. Emergency incident
remarks are optional and may be blank; photo and timestamp requirements remain.
Staff can resolve a properly filed alert without guard remarks, using the existing
resolution note and authorization checks.

Apply `20260913000003_report_text_requirements.sql` with the app update when
release is authorized. This change is local only and has not been built or deployed.

## Guard Duty Logs DTR — local changes, 2026-09-13

Duty Logs now opens My DTR with month navigation and half-month cutoff selection. The guard sees the agency DTR with six columns: duty date, assigned shift/site, actual Time In, actual Time Out, total overtime hours, and total worked hours. Blank days remain blank; multiple sessions on a duty date are retained. Philippine time and the shift-start date own overnight punches and cutoffs. Missing or unverified late Time Outs do not contribute hours; verification notes remain outside the table. Overtime is included in worked hours, not added twice.

The report service uses the signed-in guard's ID and existing Supabase row-level security, fetches the selected cutoff with pagination, and refreshes after attendance changes or returning to the app. Period request sequencing prevents old responses replacing a newer selection. Download DTR generates an A4 PDF locally and uses the existing file picker to save it; cancelling does not report success. Noto Sans fonts and their OFL license are bundled for offline PDF text rendering.

Validation: five fixture comparisons against web/js/dtr-report.js; cutoff/overnight, phone layout, request-race, retry, own-account pagination, and PDF save/cancel checks; report-text regression checks after dependency resolution. 17 tests passed and targeted analysis is clean. Generated sample PDFs, including a two-page report, were rendered and visually reviewed. Native phone save dialogs still need device testing. No app build, migration application, or deployment was performed.

## Explicit overtime Time Out — local changes, 2026-09-13

An open duty can now be timed out after its scheduled end. The app asks “Did you work overtime?” with Yes (request approval), No (use scheduled end), and Cancel. Original-post geofence and fresh accurate GPS checks remain required. A newer eligible duty can still take precedence; a rolled-over missing session remains an Operations Head correction.

Pending migration `20260913000004_guard_overtime_timeout_choice.sql` adds `record_guard_timeout`, scoped to the authenticated guard and the explicit session ID. Server time determines lateness; the server requires a choice for late submission. Yes saves the real Time Out, notifies the agency's active Operations Heads, and leaves Time Out and totals blank in the guard/Operations Head/Inspector DTR until verification. The existing Personnel > View DTR review accepts or corrects the submitted end time with a reason. Approval notifies the guard. No saves scheduled end as the DTR end without overtime/review and retains actual submission time separately in `timeout_submitted_at`; the guard attendance card distinguishes the two. Repeating a request returns the original result, while changing its choice is rejected.

Example: 6 AM–6 PM, overtime Time Out at 8 PM: after approval the DTR has 2:00 overtime and 14:00 worked. A 6:03 PM submission with No has a 6 PM DTR end, 0:00 overtime, and 12:00 worked. No overtime pay calculation is introduced.

Validation: 30 Flutter checks, 11 isolated PostgreSQL checks, 9 browser review checks, existing web DTR model checks, and targeted analysis passed. Notifications were exercised only in the isolated test database. No app build, remote migration, or deployment performed. This supersedes the previous blanket rejection of every late Time Out.

## Release 1.0.16 / Build 17 — deployed 2026-09-13

Published the guard DTR preview/PDF download, accomplishment text changes, optional incident remarks, actual attendance card, strict original-post Time Out, and explicit overtime approval choice. Applied database migrations 20260913000002 through 20260913000004. The Operations Head overtime review changes are published on all portal aliases.

Android APK verified in release mode with application ID com.sentinellink.app and the same certificate as the previous version. SHA-256: 08cf3dc67c014bbe58930f126c2acf39389070b2fa80495498a378cda560ff18 (66,854,085 bytes). Deployment: https://security-agency-management-system-fdcdrdjwo-codex-a9d1.vercel.app. Public portal, admin, and download aliases point to this release. Verified 71 hosted web files against staged hashes and confirmed the new Time Out RPC denies anonymous access. No test attendance or notifications were created in the live database.

Live APK verification completed: downloaded all 66,854,085 bytes from the public download alias; SHA-256 exactly matches the verified Build 17 APK. The initial download check timed out and the retry with a longer allowance succeeded.

## Release 1.0.17 / Build 18 — deployed 2026-09-13

Removed the Actual Time In/Out card from the guard attendance screen. Removed flutter_map and Leaflet branding from the attendance and Live Guard maps, keeping the visible OpenStreetMap attribution link. No database changes.

Release APK version, package ID, background location service, and matching signing certificate verified. Targeted map preservation and movement tests passed after correcting an outdated assertion for previously removed coordinates. Verified 71 live web files and downloaded all APK segments: 66,854,085 bytes, SHA-256 5453bdf522400f00899ea2db1c3a02eb94cfe58f5eed216ed2e00b3726e80882. Deployment https://security-agency-management-system-nxsa1l6zu-codex-a9d1.vercel.app; public, admin, and download aliases updated.
