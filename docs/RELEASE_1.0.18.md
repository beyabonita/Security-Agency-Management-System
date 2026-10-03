# Guard app and web release — v1.0.18, Build 19

Release date: September 14, 2026.
Status: Deployed and verified.

- [Guard Android APK](https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.18)
- [Operations Head / Inspector portal](https://security-agency-management-system-nu.vercel.app/staff/login.html)
- [IT Admin portal](https://security-agency-management-system-admin.vercel.app/system-access-7d92a4/login.html)
- Deployment: `dpl_5aYai7aG6Cbs9KfkmFh7eFUiXCe6`.

## Email accounts and sign-in

- Account creation now accepts real email addresses, including Gmail, for Guards, Inspectors, Operations Heads and IT Admins.
- Email replaces the visible username field on account forms and sign-in pages. Users sign in with their email and the app password assigned to their account.
- Operations Heads can update Guard and Inspector email addresses in Personnel. IT Admins can update Operations Head and IT Admin addresses in account management.
- The current IT Admin has a “Change my email” action that requires their current app password. It does not permit changing their own role or disabling their own account.
- Existing accounts retain their IDs, passwords and associated records when their email is changed. Existing usernames continue working until the individual account is migrated to its real email.
- New accounts cannot use the old synthetic `@asamanion-26858.auth` addresses. Duplicate email addresses are rejected, including differences in capitalization.
- Old incident reports can display the guard’s current real email when the viewer has permission to access that profile. Stored report history is preserved; missing email addresses display “Email not added.”
- This uses an existing email mailbox. It does not create Gmail mailboxes or introduce automatic welcome/reset email delivery.

## Guard emergency and incident reports

- Selecting Emergency now displays Emergency in the report details instead of Other.
- The guard’s incident narrative is required. A short nonblank narrative is accepted; whitespace alone is rejected.
- Guards can submit either a captured photo or a recorded video. A video-only report no longer requires capturing a photo first.
- Added Retake video and Use a photo instead actions. Retaking clears the previous capture, so only the replacement evidence is submitted.
- Camera controls prevent overlapping recording/capture actions. Existing video duration, file format, freshness and ownership checks remain enforced.
- Incident details identify who acknowledged, resolved or noted the report, including their name, role, timestamp and note. Multiple updates remain visible as history.
- Older records show available reviewer details; the app does not invent missing historical reviewers.
- Video-only reports display the video evidence without an empty or misleading photo requirement.

## IT Admin account activity

- Removed the Platform health card.
- Added a table for account connection status across all four roles, including Guards and Inspectors.
- Added session history with account name, role, platform, sign-in time, last contact and session end/status.
- Added search, role and connection filters, refresh controls and pagination.
- Online means recent contact from a valid signed-in session. Clients send a heartbeat about every 30 seconds; contact older than 90 seconds is treated as offline.
- Signing out ends that session. If another session remains connected, the account can still appear online.
- Web tables refresh about every 10 seconds while visible. Network loss, a closed app or phone suspension may take up to the expiry interval to appear offline.
- Enabled/Disabled account access is displayed separately from Online/Offline connection status. A disabled account is not treated as online.
- Only authorized IT Admins can view the account activity data.

## Inspector layout and dashboard clarity

- Inspector pages now use the same sidebar, header and responsive layout pattern as the Operations Head portal.
- Applied the layout to Dashboard, My Guards & DTR, Deployment Sites, Incidents, duty-request history and Live Guard Map.
- Inspector permissions and assigned-guard restrictions remain in place.
- Dashboard schedule cards are now labeled “Assigned guard shifts.” Each assigned guard shift counts once across past, current and future dates; draft and cancelled schedules are excluded.
- Operations Heads see counts for all their guards. Inspectors see counts for their assigned guards.
- Web password visibility controls show only the eye icon, with accessible Show password/Hide password labels.

## Philippine deployment-site search

- Address searches now cover the Philippines nationwide, with an optional city/province field to narrow results.
- Improved matching for common abbreviations and spelling variants, including Town/Towne, and added fallback searches.
- Results are restricted to Philippine locations, with duplicate/invalid results removed and better ordering.
- Added place-type filtering and improved saved-site search and active/disabled filtering.
- Search results are cached and requests are paced. Delayed results cannot overwrite a newer query or reopen a closed form.
- Unmapped locations can still be placed manually on the map; results depend on the map provider’s address coverage.

## Database reset utility — manual only

- Updated `testing/reset_testing_keep_it_admin.sql` to recognize and clear saved shifting setups in the correct dependency order.
- It also handles account-activity history when that feature’s table is installed.
- Preserves IT Admin accounts and their authentication records while clearing test business data. Recreates the required active TwentyTwenty beneficiary configuration.
- Keeps checks for unfamiliar tables, uploaded storage files, missing IT Admin access and rollback on failure.
- The reset script was not executed as part of this release. It remains a separate manual utility.

## Release verification

- 46 web regression checks passed.
- 15 account API checks passed.
- 15 report database checks and 10 account database checks passed in isolated fixtures.
- Live database verification confirmed all four migrations, incident validation, reviewer history, account-session trigger, presence access protection and the case-insensitive email index.
- The one existing IT Admin profile remains present. The database had no schedules or incident reports at preflight.
- 16 Flutter app checks passed; analysis of seven changed app files reported no issues.
- Android release APK verified as v1.0.18, Build 19, with the same signing certificate as the previous version. The background location service and required permissions are present.
- APK size: 66,854,073 bytes. SHA-256: `3612bdd12848441c5a8acbd67b04281118e3624b48427ec6f281af27c4290dde`.
- All 77 published web files checked against the release manifest.
- The full published APK download matched the verified local package byte count and SHA-256 checksum.
- Both live sign-in pages passed browser checks for the Email label, password eye toggle and absence of script errors. No accounts were created or signed in during these checks.
- The public account APIs correctly rejected unauthenticated requests.
- Updated the staff login download links and QR code for v1.0.18. All three public addresses point to this release.

Physical-device testing is still needed to confirm camera behavior, battery restrictions and screen-off GPS on the target phones. The release does not replace the existing GPS or overtime workflow.
