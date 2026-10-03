# Security Agency Management System ("Sentinel Link")
## Comprehensive Software & Security Audit Report

**Audit Date:** October 3, 2026  
**Auditor:** Senior Software & Security Auditor  
**Audit Scope:** Full repository static audit (Flutter Mobile, Web Portals, Supabase Backend, Migrations, Edge Functions, CI/CD & Repository Hygiene)  
**Mode:** READ-ONLY Verification (No application code or database state modified)

---

### Executive Summary
The Sentinel Link codebase demonstrates thoughtful security controls in its core Supabase schema—notably robust Row Level Security (RLS) enforcement, schema separation (`private` schema), and strict role checks across database triggers. However, the system is hindered by critical portability and deployment obstacles: hardcoded legacy URLs and CSP configurations across both mobile and web clients will break connectivity upon migrating to a new Supabase project or Vercel domain. A critical bug in `DutyTrackingScope` halts the Flutter application on web platforms with an unhandled `UnsupportedError`. Furthermore, dangerous non-idempotent constraint drops in migrations threaten database migration reliability, and the repository suffers from severe hygiene issues—including over 120 MB of unignored test output artifacts, an active OIDC token on disk, and 342 development logs checked into version control.

---

### Findings Table

| ID | Severity | Area | File:Line | Problem | Recommended Fix |
|:---|:---|:---|:---|:---|:---|
| **SEC-01** | Critical | Security | `.env.local:2` | Active `VERCEL_OIDC_TOKEN` credential resides unencrypted in working directory. While currently ignored by Git, missing `.env.example` leaves variable management undocumented. | Revoke token in Vercel Dashboard, ensure `.env.local` remains strictly ignored, and create `.env.example` with sanitized placeholders. |
| **SEC-02** | High | Security / Portability | `lib/supabase_config.dart:6,10`<br>`web/js/supabase-firebase-bridge.js:16,17`<br>`web/js/incident-report-view.js:4`<br>`web/js/live-tracking.js:222`<br>`web/admin/js/duty-requests.js:78`<br>`lib/widgets/duty_tracking_scope.dart:19` | Hardcoded legacy Supabase project domain (`https://uqtupmpofjqrnefgrexm.supabase.co`) and fallback public key across Dart and JS modules. Hardcoded hostname checks block valid alternate projects. | Extract URL and key exclusively to dynamic runtime configuration or standard environment variables; replace hardcoded origin checks with dynamic origin comparison. |
| **SEC-03** | High | Security | `web/inspector/incidents.html:217`<br>`web/admin/incidents.html:206` | Inline event handler string interpolation (`onclick="openDetail('${inc.id}')"`) in HTML tables creates XSS / script injection vulnerability if record IDs are manipulated. | Attach event listeners via DOM APIs (`addEventListener`) or use `dataset.incidentId` instead of inline string concatenation. |
| **SEC-04** | High | Security / Deployment | `supabase/functions/_shared/api.ts:20-27` | Edge Functions restrict CORS to hardcoded legacy Vercel URLs. Any new deployment URL will fail with HTTP 403 `origin_not_allowed` unless manually added via secrets. | Set `ALLOWED_WEB_ORIGINS` secret in Supabase dashboard to include new deployment domains, and avoid hardcoding ephemeral staging domains. |
| **SEC-05** | Medium | Security | `web/system-access-7d92a4/login.html:86`<br>`web/it-admin/dashboard.html:78-86` | Obfuscated path (`system-access-7d92a4`) provides security through obscurity; IT Admin page authorization relies solely on client-side JS redirects after rendering DOM structure. | Ensure all data endpoints strictly enforce `it_admin` role (already enforced in Edge Functions); consider server-side edge middleware for route protection. |
| **SEC-06** | Medium | Security / DB | `supabase/migrations/20260914000001_incident_photo_or_video.sql:45-47` | Incident photos are stored as raw Base64 strings directly in `public.incidents.photo_data` (up to 750 KB per row), causing database bloat instead of using object storage. | Migrate photo storage to Supabase Storage bucket (`incident-photos`), storing only the storage path in the database table. |
| **SEC-07** | Low | Security | `lib/services/device_service.dart:12-15` | Device ID uses non-cryptographic `Random().nextInt(0xFFFFFF)` stored in SharedPreferences. Reinstallation or cache-clearing causes device lock mismatch. | Use `uuid.v4()` with `crypto` secure random generator, and implement admin-initiated device unlock/reset flow. |
| **DB-01** | High | Database | `supabase/migrations/20260908000000_attendance_shift_rollover.sql:4`<br>`supabase/migrations/20260908000001_live_gps_approximate_accuracy.sql:3`<br>`supabase/migrations/20260913000003_report_text_requirements.sql:4-9` | Non-idempotent migration drops constraint `attendance_sessions_check2` without `IF EXISTS`. Because PostgreSQL generates anonymous check constraint names dynamically, migration crashes on fresh or replayed instances. | Alter migrations to explicitly drop constraints using `DROP CONSTRAINT IF EXISTS` and name all table constraints explicitly upon creation. |
| **DB-02** | Medium | Database | `supabase/migrations/20260907000000_live_guard_locations.sql:5` | Foreign key `guard_live_locations.session_id` references `attendance_sessions(id) ON DELETE CASCADE` without an index, resulting in table scans on session changes. | Add index: `CREATE INDEX guard_live_locations_session_idx ON public.guard_live_locations(session_id);`. |
| **DB-03** | Low | Database | `supabase/tests/database/006_dtr_schedule_periods.sql`<br>`supabase/tests/database/006_platform_configuration.sql` | Duplicate numeric prefix `006_` in test filenames creates ambiguous test execution ordering. | Rename `006_platform_configuration.sql` to `007_...` and increment subsequent test numbers. |
| **DB-04** | Low | Database | `supabase/migrations/20260905000005_correct_time_evaluation.sql:50`<br>`supabase/migrations/20260821000000_initial_schema.sql:222-225` | Hardcoded timezone `'Asia/Manila'` across database triggers, RPCs, and client code prevents multi-time-zone adaptability. | Retain as known agency constraint, or parameterize agency timezone in `platform_settings`. |
| **BUG-01** | Critical | Code Quality | `lib/widgets/duty_tracking_scope.dart:156` | `Geolocator.getServiceStatusStream()` called unconditionally in `initState`. Crashes Flutter web startup with `UnsupportedError: getServiceStatusStream is not supported on the web platform`. | Guard invocation with `if (!kIsWeb) { ... }`. |
| **BUG-02** | High | Deployment / Config | `web/vercel.json:53,59,65,71,119,125` | Vercel route rules use hardcoded host matches (`security-agency-management-system-admin.vercel.app`). Rules will fail completely when hosted under any other domain. | Remove hardcoded host filters or parameterize routing via Vercel environment configurations / Edge middleware. |
| **BUG-03** | High | Deployment / Config | `web/vercel.json:25` | Content Security Policy (`connect-src`, `img-src`, `media-src`) hardcodes legacy Supabase project domain. All API requests and storage downloads to a new project are blocked by CSP. | Update `vercel.json` CSP headers to allow the target Supabase project domain or configure dynamic CSP. |
| **BUG-04** | Medium | Code Quality | `pubspec.yaml:1`<br>`flutter_application_1.iml` | Flutter package name remains default placeholder `flutter_application_1`, creating confusing import statements across all 30+ Dart files. | Refactor package name in `pubspec.yaml` to `sentinel_link` and update project import paths. |
| **BUG-05** | Medium | Code Quality / UX | `supabase/migrations/20260914000001_incident_photo_or_video.sql:54-58` | Strict database check `p_captured_at > v_now + interval '1 minute'` rejects submissions from guard devices whose system clock runs faster by >60 seconds. | Relax capture drift check to `interval '5 minutes'` or synchronize device timestamp with server clock via RPC before filing. |
| **BUG-06** | Low | Deployment / Android | `android/signing.properties:5-8`<br>`android/app/build.gradle.kts:80-81` | Release build configuration signs APKs with Android debug keystore (`debug.keystore`), unsuitable for production release. | Generate dedicated production release keystore and keep credentials in secure CI secrets or private developer environment. |
| **TST-01** | High | Tests / Repo Hygiene | `web/tests/test-results-*/` (60+ directories)<br>`.gitignore:104` | Over 120 MB of generated Playwright screenshots, error logs, and video traces committed to Git because `.gitignore` lacks wildcard `test-results*`. | Update `.gitignore` to `/web/tests/test-results*/`, purge existing test-results folders from Git index (`git rm -r --cached`). |
| **TST-02** | Medium | Tests | `test/android_release_config_test.js` | Node.js test script located inside Flutter/Dart test suite directory (`test/`). | Move to `testing/` or `web/tests/` to keep Dart test directory clean. |
| **TST-03** | Medium | Tests | `test/widget_test.dart:1-8` | Default Flutter placeholder test (`expect(1 + 1, 2)`). Zero automated widget tests for core screens (`HomePage`, `LoginScreen`, `Attendance`). | Replace placeholder with component tests for `LoginScreen` authentication gates and attendance status banners. |
| **DEP-01** | High | Deployment / Config | Project Root | Missing `.env.example`. Required environment variables (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `ALLOWED_WEB_ORIGINS`, `LIVE_TRACKING_ENABLED`) are undocumented. | Create `.env.example` detailing all required variables, default fallbacks, and target environments. |
| **DEP-02** | Medium | Deployment / Config | `.gitignore:150` | `pubspec.lock` is ignored. For application projects, ignoring `pubspec.lock` leads to non-reproducible builds across CI and developer environments. | Remove `pubspec.lock` from `.gitignore` and commit locked package dependencies. |
| **HYG-01** | High | Repo Hygiene | `testing/` (342 files, ~10 MB) | 342 ephemeral files, including test runs, console logs (`*.log`), text dumps (`*.txt`), sample PDFs, and a 1.1 MB ZIP file (`WhiteBox-Evidence-2026-09-05.zip`) committed to source control. | Clean up `testing/` directory; move permanent automated test suites to `test/` or `web/tests/`, and place run artifacts in `.gitignore`. |

---

### Top 10 Priority Fixes (Ranked by Impact)

1. **Fix Flutter Web Startup Crash (`BUG-01`):** Wrap `Geolocator.getServiceStatusStream()` in `lib/widgets/duty_tracking_scope.dart:156` with `if (!kIsWeb)`. This instantly resolves the blocking error on Chrome/Edge.
2. **Remove Hardcoded Supabase Domain from CSP & Bridge (`BUG-03`, `SEC-02`):** Update `web/vercel.json` CSP connect/image sources and `web/js/supabase-firebase-bridge.js` to reference the active Supabase project URL so requests aren't blocked.
3. **Make Migrations Idempotent with Safe Constraint Checks (`DB-01`):** Add `IF EXISTS` to constraint drops in `20260908000000_attendance_shift_rollover.sql` to avoid broken database migrations on fresh environments.
4. **Fix Edge Function CORS Domain Allowlist (`SEC-04`):** Update `ALLOWED_WEB_ORIGINS` secret in Supabase dashboard to include current and planned Vercel deployment URLs.
5. **Sanitize Inline HTML Event Handlers (`SEC-03`):** Replace inline `onclick="openDetail('${inc.id}')"` in `web/admin/incidents.html` and `web/inspector/incidents.html` with data-attributes and `addEventListener` to eliminate XSS risk.
6. **Exclude Generated Test Artifacts in `.gitignore` (`TST-01`):** Add `/web/tests/test-results*/` and `**/test-results-*/` to `.gitignore` and remove tracked result folders from Git to halt repo bloat.
7. **Track `pubspec.lock` for Deterministic Builds (`DEP-02`):** Remove `pubspec.lock` from `.gitignore` line 150 to guarantee identical Flutter package versions across builds.
8. **Provide `.env.example` Documentation (`DEP-01`):** Add a template `.env.example` file documenting all environment variables and secrets required by Flutter, Web, and Edge Functions.
9. **Index `guard_live_locations.session_id` (`DB-02`):** Add a database index on `guard_live_locations(session_id)` to optimize cascade operations and session lookups.
10. **Clean Up Ephemeral Artifacts in `testing/` (`HYG-01`):** Archive or remove outdated log dumps, temporary txt logs, and sample PDFs from the repository root.

---

### Quick Wins (< 30 Minutes Execution)

1. **Flutter Web Null/Web Check:**
   In [lib/widgets/duty_tracking_scope.dart](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/lib/widgets/duty_tracking_scope.dart#L156):
   ```dart
   if (!kIsWeb) {
     _locationServices = Geolocator.getServiceStatusStream().listen(...);
   }
   ```
2. **Wildcard Test Results in `.gitignore`:**
   In [.gitignore](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/.gitignore#L104):
   Change `/web/tests/test-results/` to `/web/tests/test-results*/`.
3. **Enable Deterministic Dependency Locking:**
   In [.gitignore](file:///c:/Users/USER/Documents/Security%20Agency%20Management%20System/.gitignore#L150):
   Delete line 150 (`pubspec.lock`).
4. **Relocate Misplaced Node Script:**
   Move `test/android_release_config_test.js` into `web/tests/` and update `.github/workflows/validate.yml:44` accordingly.
5. **Create `.env.example`:**
   Add root `.env.example` with placeholders for `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `ALLOWED_WEB_ORIGINS`.

---

### Items Requiring Live Verification (UNVERIFIED)

Because this audit is strictly read-only and performed offline without direct connection to live cloud environments, the following items could not be verified directly against production infrastructure:

1. **Live Database Applied Migration State:**
   - *Status:* UNVERIFIED
   - *Check Command:* Run in terminal:
     ```powershell
     npx supabase migration list --linked
     ```
   - *Dashboard:* Navigate to **Supabase Dashboard > Database > Migrations**. Verify all 65 migrations have been executed without drift.
2. **Edge Function Active Environment Secrets:**
   - *Status:* UNVERIFIED
   - *Check Command:* Run in terminal:
     ```powershell
     npx supabase secrets list --linked
     ```
   - *Dashboard:* Navigate to **Supabase Dashboard > Edge Functions > Manage Secrets**. Confirm `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `ALLOWED_WEB_ORIGINS` are set.
3. **Storage Bucket Configuration & Privacy:**
   - *Status:* UNVERIFIED
   - *Dashboard:* Navigate to **Supabase Dashboard > Storage**. Confirm buckets `incident-videos` and `request-letters` exist, are flagged as **Private**, and RLS is enabled.
4. **Vercel Production Domain & Environment Binding:**
   - *Status:* UNVERIFIED
   - *Dashboard:* Navigate to **Vercel Dashboard > Project Settings > Environment Variables** and **Domains**. Confirm whether the live domain matches the hardcoded rules in `web/vercel.json` or requires update.
