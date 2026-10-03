# Local GPS tracking evidence

Date: 2026-09-07 (Asia/Shanghai).

- `database.log`: 28 passing checks; real new migration executed on PGlite 0.5.8 PostgreSQL with minimal prerequisite fixtures and a recorded-message Realtime stub.
- `flutter.log`: 21 passing tracking, GPS validation, attendance-model and map-source checks.
- `javascript.log`: five passing map-data classification/search tests.
- `analyzer.log`: Dart analysis of lib and the new test file, no issues.
- `android-build.log`: successful debug APK compilation. `android-build-initial.log` retains the first failed Java loopback attempt, superseded by the successful build.
- `android-apk-sha256.json`: checksum of the locally built APK. It uses a local placeholder key; rebuild with the real local public key before signing in.
- `admin-preview.png`, `inspector-preview.png`: actual renders of the labeled simulated map; the latter is a true 390px mobile viewport. `preview.log` records viewport and document widths and the visible simulation status.
- `inspector-mobile-preview.png`: initial screenshot from Chrome's window-size flag, superseded by the explicit mobile viewport capture above.

54 checks passed. This does not certify real-device background GPS or full Supabase Auth/Realtime integration. No hosted backend was changed. See `docs/LIVE_GPS_TRACKING.md` for setup and remaining device checks.
