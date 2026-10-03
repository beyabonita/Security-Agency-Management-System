# Sentinel Link rollout test plan

Run this plan against a **staging** Supabase project and a dedicated test
TwentyTwenty Security Agency workspace. Do not use production personnel,
incident media, or credentials.
Record the application version, database migration version, device model, OS
version, network type, tester, and result for every run.

## Automated gate

Before a manual session, the following must pass:

~~~powershell
flutter analyze --no-fatal-infos
flutter test
node test/android_release_config_test.js
node web/tests/security_rendering_test.js
node web/tests/official_supabase_client_test.js
node web/tests/session_refresh_test.js
node supabase/tests/admin_create_user_security_test.js
node supabase/tests/edge_function_authorization_test.js
npm run --prefix web/tests test:playwright
~~~

In CI, start the local Supabase stack and run:

~~~powershell
supabase test db supabase/tests/database
~~~

## Functional acceptance

Create one IT Admin, one Admin, one Inspector, and two Guards
inside the staging TwentyTwenty workspace. Verify:

- IT Admin can create and secure only IT Admin and Admin accounts;
  Admin can manage Guards and Inspectors, deployment sites, and schedules.
- A deployment customer such as Jollibee is created as a TwentyTwenty duty site,
  not as a separate Sentinel Link organization.
- Assigning a home post and a dated schedule produces the expected assignment
  history. An Inspector cannot be disabled, moved, or re-roled until assigned
  Guards are reassigned or cleared.
- Regular and Contract labels are visible for the Guard account and on mobile
  login.
- A Guard can only Time In / Time Out near the scheduled post with a fresh,
  accurate, non-mocked location. Test an overnight shift and confirm one
  attendance session is created.
- DTR evaluation reflects completed days, total time, late time, and
  undertime from the schedule-linked session.
- A shift-change request shows the current and requested duty to the assigned
  Inspector and needs an approval before any schedule update.
- An accomplishment report requires a completed duty session and can be
  reviewed by Admin.
- An incident needs a photo, capture time, valid remarks, and a resolution
  note before it can be resolved. Confirm failed upload submission removes the
  orphaned video object.

## Performance benchmark

Seed only the staging organization with at least 500 Guards, 50 posts, 2,000
schedules, and 10,000 attendance sessions. Use a normal office connection and
an Android test phone on Wi-Fi and mobile data. Repeat each measurement five
times; record the median and the slowest result.

| Journey | Target |
| --- | --- |
| Staff login to role dashboard | median ≤ 3 seconds |
| Open DTR for 30-day range | median ≤ 3 seconds |
| Time In / Time Out RPC after a location fix | median ≤ 2 seconds |
| Load 100-row personnel list | median ≤ 2 seconds |
| Open incident detail with a photo | median ≤ 3 seconds |

Investigate any median above the target, any failed request, unhandled console
error, unexpected cross-organization record, or incorrect calculation before
rollout.

## Device and recovery checks

- Test the current Android version plus one older supported Android version.
- Deny then grant camera and location permission; verify the user receives a
  clear recovery message.
- Kill and reopen the app during an active session; verify session restoration
  and Time Out still work.
- Interrupt network access during attendance, incident filing, and
  accomplishment submission; confirm errors are visible and no duplicate
  record is created when retrying.

## Release decision

The release owner signs the result only after every automated and functional
check passes, the performance targets are met, and the Android app bundle is
signed with the private release keystore. Keep screenshots and exported test
results with the release notes.

Server-side, byte-level trimming/transcoding of incident video is a separate
deployment requirement: the app currently caps capture at 15 seconds and the
database enforces a claimed duration of at most 15 seconds. Use a trusted media
processing service before claiming server-side video trimming.
