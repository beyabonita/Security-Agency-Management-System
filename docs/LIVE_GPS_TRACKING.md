# Local live GPS tracking

Implemented locally on 2026-09-07. No hosted migration, deployment, real guard tracking or cloud data writes were performed.

## Preview now

```powershell
node scripts/serve-live-tracking.cjs --demo
```

Open `http://127.0.0.1:4175/admin/live-tracking.html` or `/inspector/live-tracking.html`. The yellow banner identifies simulated guards. Both pages use the actual map renderer, but demo positions are synthetic and do not contact Supabase. Map tiles and browser libraries still require internet access.

## Behavior

- Guards explicitly enable **Share on-duty location** on the Flutter home screen. Sharing is off on each new app session.
- GPS starts only with an open attendance session and stops at Time Out or the scheduled end. Duty is rechecked every 15 seconds; the server rejects writes immediately after closure/expiry. Leaving the home page for another app screen keeps its controller alive; signing out stops sharing first.
- At most one client publication every 30 seconds, using a fresh non-mock fix with accuracy of 100 m or better. No offline movement backlog is collected. Network failures pause delivery; loss of duty verification cancels GPS until verification succeeds.
- The database stores only the latest fix per guard. Clock-out or explicit stopping removes it. If the app is killed/offline, removal may not reach the server: the map labels a fix stale after 90 seconds and hides ended duties. Abandoned latest rows can remain stored until clock-out or replacement; no scheduled purge is installed.
- An active agency Admin can see its guards. Inspectors can see only their currently assigned guards. Guards, unrelated inspectors, foreign agencies and IT Admins cannot read the tracking table/list. Writes derive user identity from the authenticated session and accept only that user's duty session.
- Green means a fix is at most 90 seconds old; amber means stale. A stale marker does not establish the guard's current position. Search, fit-all, coordinates, accuracy and last-update age are available.
- Private Realtime Broadcast channels send empty invalidation signals to each authorized supervisor's topic; the browser re-queries authorized rows. The location table is deliberately absent from the Postgres Changes publication, avoiding its DELETE-event RLS limitation. A 30-second refresh also handles assignment/access changes and reconnects. Failed refreshes clear the visible locations. Row-level security remains authoritative.

## Connect actual local services

Docker and a running local Supabase stack were not available on this machine during implementation. The migration was executed in isolated PGlite PostgreSQL tests against a minimal prerequisite schema. This is not a complete Supabase Auth/Realtime integration run.

1. Install/start Docker and the Supabase CLI, then start a **fresh local test stack** from this repository (`supabase start`). Apply the repository migrations to that local database, including `supabase/migrations/20260907000000_live_guard_locations.sql`. Do not use `db push` against the linked hosted project. If you already have a populated local database, back it up and apply only missing migrations rather than resetting it.
2. Use local Studio to create local Auth accounts and matching profiles for one Admin, one Inspector and a regular Guard in the same agency. Assign the Inspector to that Guard. Create a current approved duty and use the normal Time In flow. Existing production logins/data are not copied into the preview.
3. Read the local API URL and **anon/publishable** key from `supabase status`. Never use a service-role key in the app or browser.
4. Stop the demo server, then run:

```powershell
$env:SUPABASE_URL='http://127.0.0.1:54321'
$env:SUPABASE_PUBLISHABLE_KEY='YOUR_LOCAL_ANON_OR_PUBLISHABLE_KEY'
node scripts/serve-live-tracking.cjs
```

Sign in through `http://127.0.0.1:4175/staff/login.html` with a local Admin or Inspector. The local server injects local-only configuration into every portal page and uses a separate session-storage key. It refuses hosted API URLs.

5. For a USB-connected Android test phone, forward its loopback port to the PC and build/run with the actual local key:

```powershell
adb reverse tcp:54321 tcp:54321
flutter run --debug --dart-define=LIVE_TRACKING_ENABLED=true --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_LOCAL_ANON_OR_PUBLISHABLE_KEY
```

For an Android emulator, use `http://10.0.2.2:54321`. Location sharing refuses hosted endpoints even when its flag is enabled. Use a real GPS device for tracking validation: mock emulator fixes are rejected intentionally. The debug Android manifest permits local HTTP; release behavior remains unchanged. A debug APK compiled with `local-preview-no-key` is compile evidence only and cannot sign in until rebuilt with the actual local public key.

## Device verification before deployment

Android uses Geolocator's foreground location service with an ongoing notification; iOS requests background location mode with a visible indicator. These native paths are configured but have not been validated on physical devices. Mobile OS permission settings, battery restrictions, force-stop, reboot and connectivity can interrupt updates; there is no guarantee of uninterrupted tracking. Web GPS is foreground-only and needs a secure context such as localhost/HTTPS.

Verify: opt-in and permission denial; movement on the map; stationary updates; lock/unlock; reconnect; Time Out and scheduled expiry; Stop sharing; sign-out; disabled guard; reassigned Inspector; cross-agency access. Confirm device notifications/indicators and actual update cadence. No deployment is authorized by these local changes. The local-only flags and endpoint restrictions must be deliberately reviewed in a later deployment phase.

## Local verification

```powershell
flutter test --no-pub test/live_location_controller_test.dart test/location_integrity_service_test.dart test/attendance_session_test.dart test/attendance_map_test.dart
dart analyze lib test/live_location_controller_test.dart
node --test web/tests/live_tracking_test.cjs
node scripts/test-live-tracking-db.cjs
```

The database harness uses `@electric-sql/pglite` 0.5.8 installed outside the repository at `C:/Temp/sams-live-tracking-tools`. To reproduce elsewhere, install that package in an isolated tools directory and set `PGLITE_MODULE` to its module path. The harness executes the actual new migration and PostgreSQL role/permission checks, using synthetic prerequisite tables and users. Its `realtime.send` stub records recipient topics and payloads locally; actual WebSocket delivery is not tested. It does not simulate GPS or prove all existing policies integrate correctly.

Completed: 28 PostgreSQL checks, 21 Flutter checks (10 new tracking lifecycle tests plus 11 related regressions), five JavaScript model tests, and Dart analysis with no issues. The Android debug APK built successfully with local placeholder connection settings. The initial Windows Java loopback error was resolved with process-local `JAVA_TOOL_OPTIONS` and `GRADLE_OPTS` set to `-Djdk.net.unixdomain.tmpdir=C:/Temp/sams-live-tracking-sockets` after creating that directory. Existing Gradle/Kotlin compatibility warnings remain in the build log.

Evidence is in `testing/live-tracking/`. Screenshots show a clearly labeled simulation rendered by headless Chrome, not a real guard GPS test. This work adds no paid map API. OpenStreetMap public tiles remain subject to the [tile usage policy](https://operations.osmfoundation.org/policies/tiles/); realtime traffic consumes the project's existing Supabase quotas.

Implementation references: [Geolocator platform configuration](https://pub.dev/packages/geolocator), [Supabase private Broadcast](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes).
