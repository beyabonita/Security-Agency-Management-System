# White-Box Testing Report

**System:** Sentinel Link — Security Agency Management System, TwentyTwenty Security Agency

**Version:** 1.0.10+11 (working tree as supplied, including pre-existing changes)

**Testing started:** 2026-09-05T16:45:42.9109587+08:00

**Report generated:** 2026-09-05T12:38:17.581Z (UTC; local timezone Asia/Shanghai, UTC+08:00)

## Executive result

**Overall result: FAIL.** 329 automated unit cases executed: 326 PASS, 3 FAIL. 10 planned database cases NOT EXECUTED. Pass percentage = (326 ÷ 329) × 100 = **99.09%**. This is a bounded white-box assessment, not a claim that every function or branch was tested. Production source was not fixed.

## Stack, tools and environment

Windows; Flutter 3.47.1, Dart 3.13.1, flutter_test from the installed Flutter SDK; Node.js 24.13.0 with node:test; Deno 2.9.6 / TypeScript 6.0.3 with Deno.test; Supabase Flutter 2.17.2 resolved from pubspec.lock; Supabase Edge TypeScript functions and PostgreSQL migrations. Primary tool: flutter_test. Supporting tools: language-native backend/web unit runners and SonarQube Community Build 26.9.0.129388 / scanner 5.0.0.

Framework selection follows the actual stack: PHPUnit, pytest, and JUnit do not fit this application. No Selenium, Playwright, browser smoke, or other black-box tests were executed.

## Modules and methods tested

65 distinct module/method labels were exercised. Getters and private helper branches reached by these methods contribute coverage. Handler callbacks are identified by their production module because they are anonymous registered functions.

- AttendanceService.blockReasonForAction
- AttendanceService.formatDuration
- AttendanceService.loadOpenSession
- AttendanceService.recordEvent
- AttendanceSession.fromRow
- AttendanceSession.lateDuration
- AttendanceSession.undertimeDuration
- AttendanceSession.workedDuration
- ContractPeriod.configured
- ContractPeriod.timeInBlockReason
- ContractPeriodJS.dutyError
- ContractPeriodJS.validate
- DtrAlignment.cellLabel
- DtrAlignment.cutoffForDutyDate
- DtrAlignment.normalizePeriod
- DtrReport.buildReport
- DtrReport.filterSessions
- DtrReport.periodFromSelection
- DtrReport.sessionMinutes
- DutyRequestService.prepareRequestLetterUpload
- DutyRequestService.scheduleHasAttendance
- GeofenceService.isWithinAnySite
- GeofenceService.loadSitesForUser
- GeofenceService.nearestSite
- LocationIntegrityService.validationError
- NotificationService.acknowledge
- NotificationService.markAllRead
- NotificationService.markRead
- RequestLetter.constructor
- RequestLetter.reservePath
- SchedulePeriod.buildDutyPlan
- SchedulePeriod.calculate
- SchedulePeriod.dtrColumnForTime
- SchedulePeriod.dtrPeriodForDate
- ScheduleService.isScheduleEnded
- ScheduleService.locationIdsFromSchedules
- ScheduleService.scheduleDutyDate
- ScheduleService.visibleSchedules
- UserProfileService.displayName
- UserProfileService.getProfile
- UserProfileService.registerDeviceIfNeeded
- UserProfileService.validateGuardLogin
- UserRoleService.currentUserRole
- UserRoleService.getRole
- UserRoleService.isAdmin
- accounts.authProviderMessage
- accounts.databaseBusinessMessage
- accounts.isAppRole
- accounts.isEmploymentCategory
- accounts.optionalBoolean
- accounts.optionalString
- accounts.usernameValid
- accounts.uuidValid
- admin-create-user.registered handler
- admin-manage-user.registered handler
- api.authenticatedUserId
- api.handleJsonPost
- auth_username.displayLoginId
- auth_username.normalizeUsername
- auth_username.resolveAuthEmail
- auth_username.usernameToAuthEmail
- auth_username.validateUsername
- contract-period.contractPeriod
- deleteIncidentHandler.deleteIncidentHandler
- it-provision-client.registered handler

## Execution approach and evidence

Tests call production functions directly. Backend tests import unchanged handlers and substitute the external Supabase SDK boundary using a test-only Deno import map. Account creation, updates, rollbacks, deletion ordering and denied-write behavior are checked with in-memory spies. Dart services use the actual Supabase client with an injected MockClient. Synthetic fixtures never access the live database. These tests verify application logic; they do not prove PostgreSQL RLS or Auth service correctness.

Every executed case has input, expected and actual values, a WB identifier, runner evidence and an extracted per-case log under logs/. Original reporter outputs are preserved. Screenshots are captures of saved evidence or the actual Sonar dashboard, not substitutes for machine-readable logs. Initial Flutter service-fixture failures were corrected in test code (SharedPreferences mock and HTTP response.request); superseded logs are retained, and final counts use flutter-verified.jsonl, deno-final.log and node.tap only. Earlier reruns are not counted twice.

## Unit-test results

- flutter_test: 146 executed; 144 passed; 2 failed.
- Deno.test: 131 executed; 131 passed; 0 failed.
- node:test: 52 executed; 51 passed; 1 failed.

Total planned cases: 339. Executed: 329. Not executed: 10.

## Code coverage

| Scope (instrumented files only) | Lines covered / measured | Line coverage | Function coverage | Branch coverage |
|---|---:|---:|---:|---:|
| Dart (15 files) | 275 / 556 | 49.46% | Not emitted by tool | 51.44% |
| TypeScript (7 files) | 960 / 1065 | 90.14% | 86.84% | 90.20% |
| JavaScript (3 files) | 367 / 713 | 51.47% | 52.54% | 78.71% |

These percentages apply only to the files listed in the actual LCOV reports. They are **not whole-system coverage**. Test doubles are excluded from the TypeScript summary. No mixed-language overall percentage is asserted because coverage tools use different executable-line and branch definitions. Flutter was invoked with --branch-coverage, but if its LCOV emits no branch or function records those metrics are unavailable, not zero. All measured uncovered lines are listed below and in coverage/summary.json. Deno's generated HTML is available at coverage/deno-final/html/index.html.

| Source | Lines covered / measured | Uncovered lines |
|---|---:|---|
| lib/utils/auth_username.dart | 18 / 18 | None |
| lib/services/user_profile_service.dart | 20 / 26 | 7, 8, 22, 23, 24, 25 |
| lib/services/attendance_service.dart | 32 / 50 | 10, 36, 39, 40, 44, 45, 46, 47, 48, 49, 52, 55, 56, 57, 58, 95, 96, 97 |
| lib/services/schedule_service.dart | 25 / 97 | 7, 12, 13, 14, 21, 44, 45, 51, 59, 60, 61, 64, 65, 66, 68, 72, 76, 77, 78, 80, 84, 88, 89, 90, 91, 94, 98, 99, 100, 101, 102, 103, 104, 105, 106, 122, 125, 126, 127, 128, 129, 130, 131, 132, 133, 135, 136, 137, 140, 141, 142, 143, 144, 145, 146, 148, 149, 152, 156, 157, 158, 159, 161, 163, 164, 166, 169, 170, 172, 174, 176, 177 |
| lib/services/geofence_service.dart | 12 / 25 | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22 |
| lib/services/location_integrity_service.dart | 11 / 11 | None |
| lib/services/duty_request_service.dart | 14 / 115 | 6, 25, 27, 29, 30, 31, 33, 34, 37, 39, 40, 41, 42, 43, 45, 48, 55, 63, 65, 68, 69, 70, 71, 72, 73, 74, 77, 80, 85, 91, 92, 93, 94, 97, 132, 133, 140, 142, 145, 146, 147, 148, 149, 150, 151, 153, 154, 155, 156, 157, 159, 162, 169, 170, 171, 174, 175, 180, 185, 186, 188, 189, 190, 191, 193, 195, 196, 197, 201, 204, 206, 207, 208, 211, 212, 213, 214, 215, 216, 217, 218, 221, 222, 224, 229, 230, 231, 232, 233, 234, 235, 237, 238, 239, 241, 244, 249, 251, 253, 254, 255 |
| lib/models/geofence_site.dart | 2 / 2 | None |
| lib/models/attendance_session.dart | 30 / 43 | 28, 29, 31, 33, 34, 36, 37, 40, 41, 43, 44, 47, 55 |
| lib/models/contract_period.dart | 16 / 22 | 41, 42, 43, 44, 47, 50 |
| lib/models/dtr_alignment.dart | 46 / 53 | 21, 76, 77, 118, 123, 124, 125 |
| lib/models/request_letter.dart | 34 / 41 | 7, 12, 15, 16, 17, 20, 22 |
| lib/services/user_role_service.dart | 5 / 6 | 10 |
| lib/services/notification_service.dart | 10 / 22 | 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 |
| lib/models/app_notification.dart | 0 / 25 | 2, 32, 33, 34, 35, 36, 38, 39, 41, 44, 45, 46, 47, 48, 49, 50, 51, 52, 54, 55, 56, 57, 58, 59, 60 |
| supabase/functions/_shared/accounts.ts | 115 / 132 | 102, 103, 104, 105, 107, 109, 110, 123, 124, 125, 126, 128, 130, 131, 132, 133, 135 |
| supabase/functions/_shared/api.ts | 242 / 250 | 63, 140, 157, 274, 275, 276, 277, 279 |
| supabase/functions/_shared/contract-period.ts | 32 / 32 | None |
| supabase/functions/admin-create-user/index.ts | 188 / 205 | 48, 95, 96, 106, 107, 108, 109, 111, 120, 129, 130, 137, 152, 153, 154, 155, 157 |
| supabase/functions/admin-delete-incident/handler.ts | 90 / 90 | None |
| supabase/functions/admin-manage-user/index.ts | 283 / 346 | 49, 50, 68, 69, 79, 80, 81, 82, 84, 86, 87, 123, 124, 136, 137, 138, 139, 141, 149, 150, 151, 152, 154, 164, 165, 166, 167, 169, 182, 185, 186, 187, 188, 190, 198, 199, 200, 201, 203, 210, 211, 212, 213, 214, 215, 216, 217, 218, 220, 221, 231, 236, 243, 244, 315, 316, 317, 318, 319, 321, 338, 354, 376 |
| supabase/functions/it-provision-client/index.ts | 10 / 10 | None |
| web/js/contract-period.js | 28 / 35 | 25, 26, 27, 28, 29, 30, 31 |
| web/js/dtr-report.js | 173 / 470 | 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 48, 49, 50, 51, 52, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 78, 79, 80, 81, 82, 83, 84, 87, 88, 89, 113, 114, 115, 116, 117, 118, 119, 120, 121, 124, 125, 126, 127, 128, 129, 130, 141, 142, 143, 144, 145, 148, 149, 150, 151, 152, 153, 154, 155, 156, 163, 164, 165, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 218, 219, 220, 221, 241, 242, 243, 244, 245, 246, 249, 250, 251, 252, 253, 254, 255, 258, 259, 260, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452 |
| web/js/schedule-period.js | 166 / 208 | 31, 32, 33, 34, 35, 38, 39, 40, 41, 42, 78, 79, 80, 81, 82, 83, 84, 85, 86, 125, 126, 127, 128, 129, 130, 133, 134, 135, 136, 137, 138, 139, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 |

## SonarQube supporting analysis

### Actual analysis results

Actual local analysis: Community Build 26.9.0.129388, scanner 5.0.0.

| Metric | Result |
|---|---:|
| Overall coverage | 55.4% |
| Line coverage | 47.9% |
| Covered / measurable lines | 1327 / 2769 |
| Uncovered lines | 1442 |
| Branch coverage | 87.4% |
| Bugs (legacy API) | 18 |
| Code smells (legacy API) | 210 |
| Vulnerabilities (legacy API) | 35 |
| Security hotspots | 0 |
| Duplicated lines | 556 |
| Duplication density | 3.9% |
| Reliability / security / maintainability ratings | E / B / A |
| Quality gate | OK |

Scope: application sources in lib, web and supabase/functions, subject to installed language analyzers. Generated deployment copies (.vercel), build output, downloads, dependencies, assets and test code are excluded. The initial scan included deployment copies and is retained under sonarqube/initial-scan for audit only; its metrics are superseded. JavaScript bundle detection also automatically excludes generated-looking files, as recorded in scanner.log.

JavaScript and TypeScript LCOV imports are confirmed in scanner.log. No Dart analyzer is installed (languages.json), so Dart coverage is standalone and is not part of these Sonar coverage metrics. Sonar uses its own executable-line denominator; these results are separate from native runner percentages and are not coverage of every system language.

The quality gate returned OK with 1 evaluated conditions. The evaluated condition concerns new violations only (zero since the prior analysis); this is not an overall-code clearance and does not override the three failed unit tests.

Static findings are analyzer reports requiring review, not reproduced exploits. The legacy bug/smell/vulnerability categories above differ from the dashboard's MQR security/reliability/maintainability impacts, which can overlap. Zero hotspots does not certify security; this Community Build does not provide all commercial security analysis capabilities.

There are 263 unresolved exported findings (504 total exported, including historical statuses). The complete issue records are in sonarqube/issues-*.json and the reviewable CSV is sonarqube/issues.csv.

Evidence: scanner.log, scanner.exitcode, measures.json, quality-gate.json, languages.json, server-status.json, hotspots.json and screenshots/SonarQube_*.png.


## Failed tests and discovered issues

### WB-084 — AttendanceSession.fromRow

- File: lib/models/attendance_session.dart
- Severity: Medium
- Scenario/input: malformed supplied clock-out must not disappear; "clock_out_at=garbage"
- Expected: "FormatException"
- Actual: "no exception"
- Error: Expected: 'FormatException'
  Actual: 'no exception'
   Which: is different.
          Expected: FormatExce ...
            Actual: no excepti ...
                    ^
           Differ at offset 0

- Cause: parseOptional uses DateTime.tryParse(...), returning null for malformed supplied values.
- Impact: A corrupt closed-session timestamp can disappear; worked time becomes zero and status can become inconsistent.
- Recommendation: Reject non-null invalid clock_out_at values with FormatException; distinguish absent from malformed data.
- Evidence: [WB-084 log](../logs/WB-084.txt), logs/flutter-verified.jsonl:333

### WB-423 — SchedulePeriod.buildDutyPlan

- File: web/js/schedule-period.js
- Severity: Medium
- Scenario/input: null entry should return validation error; [null]
- Expected: true
- Actual: "Exception: TypeError: Cannot read properties of null (reading 'period')"
- Error: TypeError: Cannot read properties of null (reading 'period')
- Cause: buildDutyPlan dereferences entry.period before validating the entry object.
- Impact: Malformed/null entries cause an uncaught TypeError rather than a user-facing validation result.
- Recommendation: Validate each entry is a non-null object and validate field types before reading period.
- Evidence: [WB-423 log](../logs/WB-423.txt), logs/node.tap:24

### WB-510 — UserProfileService.validateGuardLogin

- File: lib/services/user_profile_service.dart
- Severity: Medium; defense in depth
- Scenario/input: unknown active role must be denied; {"role":"owner","active":true}
- Expected: true
- Actual: false
- Error: Expected: <true>
  Actual: <false>

- Cause: validateGuardLogin rejects three named web roles, then allows every other active role.
- Impact: The helper accepts unknown active roles. A server authorization bypass was not established; RLS and database role constraints were not executed.
- Recommendation: Explicitly allow only the guard role user; deny missing/unknown roles by default.
- Evidence: [WB-510 log](../logs/WB-510.txt), logs/flutter-verified.jsonl:253


These 3 reproduced unit failures are distinct from static-analysis findings. The unknown-role finding is a local validation defect; no exploit or database access bypass was executed.

## Static analyzer

Dart analyzer output is saved separately at logs/dart-analyze.log. It reported no issues in lib at this run. This is Dart analyzer evidence, not a SonarQube result and not proof of security.

## Limitations and remaining test scope

- PostgreSQL pgTAP/RLS/trigger/transaction behavior was not executed because an isolated database runtime and Docker were unavailable. Existing SQL suites are linked in the blocked cases.
- UI state, widget lifecycle, camera/GPS native integration, realtime subscriptions, full login UI flow, live storage/Auth/network behavior and report PDF rendering are outside this unit run.
- DeviceService, IncidentService, image codec, request picker, and some schedule/duty-request service paths remain untested; see per-file coverage for gaps in measured modules.
- Dart typing excludes some wrong-type calls at compile time; one dynamic wrong-type call was explicitly tested. Not every function accepts every input category.
- Database role constraints could prevent unknown-role profiles from occurring normally; the direct helper still fails closed-role validation expectations.
- This run does not certify production readiness or complete branch coverage.

## Recommendations

1. Review the three reproduced defects; approve production fixes in a separate phase, then rerun the corresponding WB cases.
2. Run the existing pgTAP suites against an isolated Supabase instance, prioritizing tenant isolation, attendance transactions, upload idempotency and reciprocal swaps.
3. Expand unit coverage for realtime transformations, device registration, incident processing and remaining failure/rollback branches.
4. Import the retained native coverage into a SonarQube edition that supports each source language; review security hotspots manually.

## Complete test cases

The same table is available as test-cases.csv and structured results.json.

| Test ID | Module/Class | Function/Method Tested | Test Scenario | Test Input | Expected Result | Actual Result | Status | Evidence | Remarks |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WB-001 | auth_username | validateUsername | length and character validation | "ab" | false | false | PASS | logs/flutter-verified.jsonl:13 | Direct production function execution. |
| WB-002 | auth_username | validateUsername | length and character validation | "abc" | true | true | PASS | logs/flutter-verified.jsonl:16 | Direct production function execution. |
| WB-003 | auth_username | validateUsername | length and character validation | "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" | true | true | PASS | logs/flutter-verified.jsonl:19 | Direct production function execution. |
| WB-004 | auth_username | validateUsername | length and character validation | "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" | false | false | PASS | logs/flutter-verified.jsonl:22 | Direct production function execution. |
| WB-005 | auth_username | validateUsername | length and character validation | "" | false | false | PASS | logs/flutter-verified.jsonl:25 | Direct production function execution. |
| WB-006 | auth_username | validateUsername | length and character validation | "  GUARD_01  " | true | true | PASS | logs/flutter-verified.jsonl:28 | Direct production function execution. |
| WB-007 | auth_username | validateUsername | length and character validation | "a-b" | false | false | PASS | logs/flutter-verified.jsonl:31 | Direct production function execution. |
| WB-008 | auth_username | validateUsername | length and character validation | "a b" | false | false | PASS | logs/flutter-verified.jsonl:34 | Direct production function execution. |
| WB-009 | auth_username | validateUsername | length and character validation | "éab" | false | false | PASS | logs/flutter-verified.jsonl:37 | Direct production function execution. |
| WB-010 | auth_username | validateUsername | length and character validation | "a.b" | true | true | PASS | logs/flutter-verified.jsonl:40 | Direct production function execution. |
| WB-011 | auth_username | normalizeUsername | trim and lower case | " Guard_1 " | "guard_1" | "guard_1" | PASS | logs/flutter-verified.jsonl:43 | Direct production function execution. |
| WB-012 | auth_username | resolveAuthEmail | legacy email | " USER@Example.com " | "user@example.com" | "user@example.com" | PASS | logs/flutter-verified.jsonl:46 | Direct production function execution. |
| WB-013 | auth_username | usernameToAuthEmail | synthetic email | " Guard " | "guard@asamanion-26858.auth" | "guard@asamanion-26858.auth" | PASS | logs/flutter-verified.jsonl:49 | Direct production function execution. |
| WB-014 | auth_username | resolveAuthEmail | username route | "Guard" | "guard@asamanion-26858.auth" | "guard@asamanion-26858.auth" | PASS | logs/flutter-verified.jsonl:52 | Direct production function execution. |
| WB-015 | auth_username | displayLoginId | profile fallback | null | "" | "" | PASS | logs/flutter-verified.jsonl:55 | Direct production function execution. |
| WB-016 | auth_username | displayLoginId | profile fallback | {} | "" | "" | PASS | logs/flutter-verified.jsonl:58 | Direct production function execution. |
| WB-017 | auth_username | displayLoginId | profile fallback | {"username":"g","email":"old@x"} | "g" | "g" | PASS | logs/flutter-verified.jsonl:61 | Direct production function execution. |
| WB-018 | auth_username | displayLoginId | profile fallback | {"email":"guard@asamanion-26858.auth"} | "guard" | "guard" | PASS | logs/flutter-verified.jsonl:64 | Direct production function execution. |
| WB-019 | auth_username | displayLoginId | profile fallback | {"email":"legacy@x"} | "legacy@x" | "legacy@x" | PASS | logs/flutter-verified.jsonl:67 | Direct production function execution. |
| WB-020 | auth_username | displayLoginId | profile fallback | {"username":12} | "12" | "12" | PASS | logs/flutter-verified.jsonl:70 | Direct production function execution. |
| WB-021 | auth_username | validateUsername | incorrect runtime type | 123 | "_TypeError" | "_TypeError" | PASS | logs/flutter-verified.jsonl:73 | Direct production function execution. |
| WB-022 | UserProfileService | displayName | missing names | {} | "Security Guard" | "Security Guard" | PASS | logs/flutter-verified.jsonl:76 | Direct production function execution. |
| WB-023 | UserProfileService | displayName | middle initial | {"first_name":"Ana","middle_initial":"B","last_name":"Cruz"} | "Ana B. Cruz" | "Ana B. Cruz" | PASS | logs/flutter-verified.jsonl:79 | Direct production function execution. |
| WB-024 | LocationIntegrityService | validationError | 45-second absolute age boundary | {"ageSeconds":-46} | false | false | PASS | logs/flutter-verified.jsonl:82 | Direct production function execution. |
| WB-025 | LocationIntegrityService | validationError | 45-second absolute age boundary | {"ageSeconds":-45} | true | true | PASS | logs/flutter-verified.jsonl:85 | Direct production function execution. |
| WB-026 | LocationIntegrityService | validationError | 45-second absolute age boundary | {"ageSeconds":0} | true | true | PASS | logs/flutter-verified.jsonl:88 | Direct production function execution. |
| WB-027 | LocationIntegrityService | validationError | 45-second absolute age boundary | {"ageSeconds":45} | true | true | PASS | logs/flutter-verified.jsonl:91 | Direct production function execution. |
| WB-028 | LocationIntegrityService | validationError | 45-second absolute age boundary | {"ageSeconds":46} | false | false | PASS | logs/flutter-verified.jsonl:94 | Direct production function execution. |
| WB-029 | LocationIntegrityService | validationError | coordinate bounds | "90.0,180.0" | true | true | PASS | logs/flutter-verified.jsonl:97 | Direct production function execution. |
| WB-030 | LocationIntegrityService | validationError | coordinate bounds | "-90.0,-180.0" | true | true | PASS | logs/flutter-verified.jsonl:100 | Direct production function execution. |
| WB-031 | LocationIntegrityService | validationError | coordinate bounds | "90.01,0.0" | false | false | PASS | logs/flutter-verified.jsonl:103 | Direct production function execution. |
| WB-032 | LocationIntegrityService | validationError | coordinate bounds | "0.0,180.01" | false | false | PASS | logs/flutter-verified.jsonl:106 | Direct production function execution. |
| WB-033 | LocationIntegrityService | validationError | coordinate bounds | "NaN,0.0" | false | false | PASS | logs/flutter-verified.jsonl:109 | Direct production function execution. |
| WB-034 | LocationIntegrityService | validationError | coordinate bounds | "0.0,Infinity" | false | false | PASS | logs/flutter-verified.jsonl:112 | Direct production function execution. |
| WB-035 | LocationIntegrityService | validationError | GPS accuracy | "0.0" | false | false | PASS | logs/flutter-verified.jsonl:115 | Direct production function execution. |
| WB-036 | LocationIntegrityService | validationError | GPS accuracy | "-1.0" | false | false | PASS | logs/flutter-verified.jsonl:118 | Direct production function execution. |
| WB-037 | LocationIntegrityService | validationError | GPS accuracy | "NaN" | false | false | PASS | logs/flutter-verified.jsonl:121 | Direct production function execution. |
| WB-038 | LocationIntegrityService | validationError | GPS accuracy | "Infinity" | false | false | PASS | logs/flutter-verified.jsonl:124 | Direct production function execution. |
| WB-039 | LocationIntegrityService | validationError | GPS accuracy | "0.1" | true | true | PASS | logs/flutter-verified.jsonl:127 | Direct production function execution. |
| WB-040 | LocationIntegrityService | validationError | mock location rejected | true | false | false | PASS | logs/flutter-verified.jsonl:130 | Direct production function execution. |
| WB-041 | GeofenceService | isWithinAnySite | no sites | [] | false | false | PASS | logs/flutter-verified.jsonl:133 | Direct production function execution. |
| WB-042 | GeofenceService | isWithinAnySite | center included | "0,0; radius100" | true | true | PASS | logs/flutter-verified.jsonl:136 | Direct production function execution. |
| WB-043 | GeofenceService | isWithinAnySite | outside radius | "1,1; radius100" | false | false | PASS | logs/flutter-verified.jsonl:141 | Direct production function execution. |
| WB-044 | GeofenceService | isWithinAnySite | zero-radius equality | "0,0; radius0" | true | true | PASS | logs/flutter-verified.jsonl:144 | Direct production function execution. |
| WB-045 | GeofenceService | nearestSite | empty sites | [] | null | null | PASS | logs/flutter-verified.jsonl:147 | Direct production function execution. |
| WB-046 | GeofenceService | nearestSite | stable equal-distance tie | ["a","z"] | "a" | "a" | PASS | logs/flutter-verified.jsonl:150 | Direct production function execution. |
| WB-047 | GeofenceService | loadSitesForUser | empty ids avoid database | [] | 0 | 0 | PASS | logs/flutter-verified.jsonl:153 | Direct production function execution. |
| WB-048 | ContractPeriod | configured | real dates and ordered range | ["2026-09-05","2026-09-05"] | true | true | PASS | logs/flutter-verified.jsonl:156 | Direct production function execution. |
| WB-049 | ContractPeriod | configured | real dates and ordered range | ["2026-09-06","2026-09-05"] | false | false | PASS | logs/flutter-verified.jsonl:159 | Direct production function execution. |
| WB-050 | ContractPeriod | configured | real dates and ordered range | ["2026-02-30","2026-09-05"] | false | false | PASS | logs/flutter-verified.jsonl:162 | Direct production function execution. |
| WB-051 | ContractPeriod | configured | real dates and ordered range | ["",""] | false | false | PASS | logs/flutter-verified.jsonl:165 | Direct production function execution. |
| WB-052 | ContractPeriod | configured | real dates and ordered range | ["2028-02-29","2028-02-29"] | true | true | PASS | logs/flutter-verified.jsonl:168 | Direct production function execution. |
| WB-053 | ContractPeriod | timeInBlockReason | inclusive Manila date boundaries | "2026-09-04T15:59:59Z" | false | false | PASS | logs/flutter-verified.jsonl:174 | Direct production function execution. |
| WB-054 | ContractPeriod | timeInBlockReason | inclusive Manila date boundaries | "2026-09-04T16:00:00Z" | true | true | PASS | logs/flutter-verified.jsonl:177 | Direct production function execution. |
| WB-055 | ContractPeriod | timeInBlockReason | inclusive Manila date boundaries | "2026-09-05T15:59:59Z" | true | true | PASS | logs/flutter-verified.jsonl:183 | Direct production function execution. |
| WB-056 | ContractPeriod | timeInBlockReason | inclusive Manila date boundaries | "2026-09-05T16:00:00Z" | false | false | PASS | logs/flutter-verified.jsonl:186 | Direct production function execution. |
| WB-057 | ContractPeriod | timeInBlockReason | regular staff unrestricted | {} | null | null | PASS | logs/flutter-verified.jsonl:192 | Direct production function execution. |
| WB-058 | DtrAlignment | cutoffForDutyDate | invalid calendar date | "2026-02-29" | null | null | PASS | logs/flutter-verified.jsonl:198 | Direct production function execution. |
| WB-059 | DtrAlignment | cutoffForDutyDate | invalid calendar date | "2026-13-01" | null | null | PASS | logs/flutter-verified.jsonl:204 | Direct production function execution. |
| WB-060 | DtrAlignment | cutoffForDutyDate | invalid calendar date | "2026-00-01" | null | null | PASS | logs/flutter-verified.jsonl:210 | Direct production function execution. |
| WB-061 | DtrAlignment | cutoffForDutyDate | invalid calendar date | "2026-01-00" | null | null | PASS | logs/flutter-verified.jsonl:213 | Direct production function execution. |
| WB-062 | DtrAlignment | cutoffForDutyDate | invalid calendar date | "bad" | null | null | PASS | logs/flutter-verified.jsonl:219 | Direct production function execution. |
| WB-063 | DtrAlignment | cutoffForDutyDate | invalid calendar date | "" | null | null | PASS | logs/flutter-verified.jsonl:225 | Direct production function execution. |
| WB-064 | DtrAlignment | cutoffForDutyDate | cutoff boundary | "2028-02-29" | "2028-02-29" | "2028-02-29" | PASS | logs/flutter-verified.jsonl:228 | Direct production function execution. |
| WB-065 | DtrAlignment | cutoffForDutyDate | cutoff boundary | "2026-09-15" | "2026-09-15" | "2026-09-15" | PASS | logs/flutter-verified.jsonl:234 | Direct production function execution. |
| WB-066 | DtrAlignment | cutoffForDutyDate | cutoff boundary | "2026-09-16" | "2026-09-30" | "2026-09-30" | PASS | logs/flutter-verified.jsonl:237 | Direct production function execution. |
| WB-067 | DtrAlignment | cutoffForDutyDate | cutoff boundary | "2026-12-31" | "2026-12-31" | "2026-12-31" | PASS | logs/flutter-verified.jsonl:240 | Direct production function execution. |
| WB-068 | DtrAlignment | normalizePeriod | normalize explicit period | null | "auto" | "auto" | PASS | logs/flutter-verified.jsonl:243 | Direct production function execution. |
| WB-069 | DtrAlignment | normalizePeriod | normalize explicit period | " MORNING " | "morning" | "morning" | PASS | logs/flutter-verified.jsonl:246 | Direct production function execution. |
| WB-070 | DtrAlignment | normalizePeriod | normalize explicit period | "afternoon" | "afternoon" | "afternoon" | PASS | logs/flutter-verified.jsonl:249 | Direct production function execution. |
| WB-071 | DtrAlignment | normalizePeriod | normalize explicit period | "overtime" | "overtime" | "overtime" | PASS | logs/flutter-verified.jsonl:257 | Direct production function execution. |
| WB-072 | DtrAlignment | normalizePeriod | normalize explicit period | "invalid" | "auto" | "auto" | PASS | logs/flutter-verified.jsonl:260 | Direct production function execution. |
| WB-073 | DtrAlignment | cellLabel | noon and day-offset decisions | ["2026-09-05T04:00:00Z",true] | "Afternoon IN" | "Afternoon IN" | PASS | logs/flutter-verified.jsonl:266 | Direct production function execution. |
| WB-074 | DtrAlignment | cellLabel | noon and day-offset decisions | ["2026-09-05T04:00:00Z",false] | "Morning OUT" | "Morning OUT" | PASS | logs/flutter-verified.jsonl:271 | Direct production function execution. |
| WB-075 | DtrAlignment | cellLabel | noon and day-offset decisions | ["2026-09-06T00:00:00Z",true] | "Morning IN (+1)" | "Morning IN (+1)" | PASS | logs/flutter-verified.jsonl:278 | Direct production function execution. |
| WB-076 | DtrAlignment | cellLabel | noon and day-offset decisions | ["2026-09-04T00:00:00Z",false] | "Morning OUT (-1)" | "Morning OUT (-1)" | PASS | logs/flutter-verified.jsonl:284 | Direct production function execution. |
| WB-077 | AttendanceSession | fromRow | required timestamp rejected | {"missing":"scheduled_start_at"} | "FormatException" | "FormatException" | PASS | logs/flutter-verified.jsonl:287 | Direct production function execution. |
| WB-078 | AttendanceSession | fromRow | required timestamp rejected | {"missing":"scheduled_end_at"} | "FormatException" | "FormatException" | PASS | logs/flutter-verified.jsonl:293 | Direct production function execution. |
| WB-079 | AttendanceSession | fromRow | required timestamp rejected | {"missing":"clock_in_at"} | "FormatException" | "FormatException" | PASS | logs/flutter-verified.jsonl:296 | Direct production function execution. |
| WB-080 | AttendanceSession | workedDuration | eight-hour calculation | {"id":"s1","schedule_id":"d1","duty_date":"2026-09-05","scheduled_start_at":"2026-09-05T00:00:00Z","scheduled_end_at":"2026-09-05T08:00:00Z","clock_in_at":"2026-09-05T00:00:00Z","clock_out_at":"2026-09-05T08:00:00Z","status":"closed"} | 480 | 480 | PASS | logs/flutter-verified.jsonl:302 | Direct production function execution. |
| WB-081 | AttendanceSession | workedDuration | reversed punches clamp to zero | "out before in" | 0 | 0 | PASS | logs/flutter-verified.jsonl:305 | Direct production function execution. |
| WB-082 | AttendanceSession | lateDuration | late punch | "00:15" | 15 | 15 | PASS | logs/flutter-verified.jsonl:311 | Direct production function execution. |
| WB-083 | AttendanceSession | undertimeDuration | early departure | "07:30" | 30 | 30 | PASS | logs/flutter-verified.jsonl:314 | Direct production function execution. |
| WB-084 | AttendanceSession | fromRow | malformed supplied clock-out must not disappear | "clock_out_at=garbage" | "FormatException" | "no exception" | FAIL | logs/flutter-verified.jsonl:333 | Direct production function execution. |
| WB-085 | AttendanceService | formatDuration | duration display boundaries | -1 | "0 min" | "0 min" | PASS | logs/flutter-verified.jsonl:340 | Direct production function execution. |
| WB-086 | AttendanceService | formatDuration | duration display boundaries | 0 | "0 min" | "0 min" | PASS | logs/flutter-verified.jsonl:345 | Direct production function execution. |
| WB-087 | AttendanceService | formatDuration | duration display boundaries | 1 | "1 min" | "1 min" | PASS | logs/flutter-verified.jsonl:349 | Direct production function execution. |
| WB-088 | AttendanceService | formatDuration | duration display boundaries | 60 | "1 hr" | "1 hr" | PASS | logs/flutter-verified.jsonl:355 | Direct production function execution. |
| WB-089 | AttendanceService | formatDuration | duration display boundaries | 120 | "2 hrs" | "2 hrs" | PASS | logs/flutter-verified.jsonl:358 | Direct production function execution. |
| WB-090 | AttendanceService | formatDuration | duration display boundaries | 61 | "1h 1m" | "1h 1m" | PASS | logs/flutter-verified.jsonl:361 | Direct production function execution. |
| WB-091 | AttendanceService | blockReasonForAction | duplicate and missing punch | ["clock_in",true] | true | true | PASS | logs/flutter-verified.jsonl:365 | Direct production function execution. |
| WB-092 | AttendanceService | blockReasonForAction | duplicate and missing punch | ["clock_in",false] | false | false | PASS | logs/flutter-verified.jsonl:368 | Direct production function execution. |
| WB-093 | AttendanceService | blockReasonForAction | duplicate and missing punch | ["clock_out",false] | true | true | PASS | logs/flutter-verified.jsonl:371 | Direct production function execution. |
| WB-094 | AttendanceService | blockReasonForAction | duplicate and missing punch | ["clock_out",true] | false | false | PASS | logs/flutter-verified.jsonl:374 | Direct production function execution. |
| WB-095 | ScheduleService | visibleSchedules | owner and status restrictions | "own approved/changed/draft/cancelled; foreign approved" | ["a","b"] | ["a","b"] | PASS | logs/flutter-verified.jsonl:377 | Direct production function execution. |
| WB-096 | ScheduleService | locationIdsFromSchedules | deduplicate and omit missing | ["a","a","",null] | ["a"] | ["a"] | PASS | logs/flutter-verified.jsonl:380 | Direct production function execution. |
| WB-097 | ScheduleService | isScheduleEnded | end equality | "end=now" | true | true | PASS | logs/flutter-verified.jsonl:383 | Direct production function execution. |
| WB-098 | ScheduleService | isScheduleEnded | invalid end | {"end_at":45} | false | false | PASS | logs/flutter-verified.jsonl:386 | Direct production function execution. |
| WB-099 | ScheduleService | scheduleDutyDate | fallback to Manila start | {"start_at":"2026-09-04T16:00:00Z"} | "2026-09-05" | "2026-09-05" | PASS | logs/flutter-verified.jsonl:389 | Direct production function execution. |
| WB-100 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"ok.pdf","bytes":[37,80,68,70,45,120]} | true | true | PASS | logs/flutter-verified.jsonl:392 | Direct production function execution. |
| WB-101 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"ok.JPG","bytes":[255,216,255]} | true | true | PASS | logs/flutter-verified.jsonl:395 | Direct production function execution. |
| WB-102 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"ok.png","bytes":[137,80,78,71,13,10,26,10]} | true | true | PASS | logs/flutter-verified.jsonl:398 | Direct production function execution. |
| WB-103 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"../ok.pdf","bytes":[37,80,68,70,45,120]} | false | false | PASS | logs/flutter-verified.jsonl:401 | Direct production function execution. |
| WB-104 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"ok.exe","bytes":[37,80,68,70,45,120]} | false | false | PASS | logs/flutter-verified.jsonl:404 | Direct production function execution. |
| WB-105 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"ok.pdf","bytes":[]} | false | false | PASS | logs/flutter-verified.jsonl:407 | Direct production function execution. |
| WB-106 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"ok.pdf","bytes":[1,2,3]} | false | false | PASS | logs/flutter-verified.jsonl:410 | Direct production function execution. |
| WB-107 | RequestLetter | constructor | filename, content signature and empty bytes | {"name":"","bytes":[37,80,68,70,45,120]} | false | false | PASS | logs/flutter-verified.jsonl:413 | Direct production function execution. |
| WB-108 | RequestLetter | constructor | 5MB boundary | 5242880 | true | true | PASS | logs/flutter-verified.jsonl:416 | Direct production function execution. |
| WB-109 | RequestLetter | constructor | 5MB boundary | 5242881 | false | false | PASS | logs/flutter-verified.jsonl:419 | Direct production function execution. |
| WB-110 | RequestLetter | reservePath | stable retry key | "same user twice" | true | true | PASS | logs/flutter-verified.jsonl:422 | Direct production function execution. |
| WB-111 | RequestLetter | reservePath | cross-account retry forbidden | ["g","other"] | "StateError" | "StateError" | PASS | logs/flutter-verified.jsonl:425 | Direct production function execution. |
| WB-112 | DutyRequestService | prepareRequestLetterUpload | successful retry does not upload twice | "two attempts" | 1 | 1 | PASS | logs/flutter-verified.jsonl:428 | Direct production function execution. |
| WB-113 | DutyRequestService | prepareRequestLetterUpload | lost response recovered using stable object | "first upload throws TimeoutException" | [1,true] | [1,true] | PASS | logs/flutter-verified.jsonl:431 | Direct production function execution. |
| WB-114 | DutyRequestService | prepareRequestLetterUpload | duplicate requires confirmed object | {"duplicate409":true,"exists":false} | false | false | PASS | logs/flutter-verified.jsonl:434 | Direct production function execution. |
| WB-115 | DutyRequestService | prepareRequestLetterUpload | duplicate requires confirmed object | {"duplicate409":true,"exists":true} | true | true | PASS | logs/flutter-verified.jsonl:437 | Direct production function execution. |
| WB-116 | DutyRequestService | scheduleHasAttendance | database relation shapes | null | false | false | PASS | logs/flutter-verified.jsonl:440 | Direct production function execution. |
| WB-117 | DutyRequestService | scheduleHasAttendance | database relation shapes | {} | false | false | PASS | logs/flutter-verified.jsonl:443 | Direct production function execution. |
| WB-118 | DutyRequestService | scheduleHasAttendance | database relation shapes | [] | false | false | PASS | logs/flutter-verified.jsonl:446 | Direct production function execution. |
| WB-119 | DutyRequestService | scheduleHasAttendance | database relation shapes | {"id":1} | true | true | PASS | logs/flutter-verified.jsonl:449 | Direct production function execution. |
| WB-120 | DutyRequestService | scheduleHasAttendance | database relation shapes | [1] | true | true | PASS | logs/flutter-verified.jsonl:452 | Direct production function execution. |
| WB-121 | DutyRequestService | scheduleHasAttendance | database relation shapes | "invalid" | false | false | PASS | logs/flutter-verified.jsonl:455 | Direct production function execution. |
| WB-201 | accounts | isAppRole | role allowlist | "user" | true | true | PASS | logs/deno-final.log:4 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-202 | accounts | isAppRole | role allowlist | "inspector" | true | true | PASS | logs/deno-final.log:9 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-203 | accounts | isAppRole | role allowlist | "admin" | true | true | PASS | logs/deno-final.log:14 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-204 | accounts | isAppRole | role allowlist | "it_admin" | true | true | PASS | logs/deno-final.log:19 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-205 | accounts | isAppRole | role allowlist | "owner" | false | false | PASS | logs/deno-final.log:24 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-206 | accounts | isAppRole | role allowlist | "" | false | false | PASS | logs/deno-final.log:29 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-207 | accounts | isAppRole | role allowlist | null | false | false | PASS | logs/deno-final.log:34 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-208 | accounts | isAppRole | role allowlist | 42 | false | false | PASS | logs/deno-final.log:39 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-209 | accounts | isEmploymentCategory | employment allowlist | "regular" | true | true | PASS | logs/deno-final.log:44 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-210 | accounts | isEmploymentCategory | employment allowlist | "contract" | true | true | PASS | logs/deno-final.log:49 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-211 | accounts | isEmploymentCategory | employment allowlist | "temporary" | false | false | PASS | logs/deno-final.log:54 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-212 | accounts | isEmploymentCategory | employment allowlist | null | false | false | PASS | logs/deno-final.log:59 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-213 | accounts | isEmploymentCategory | employment allowlist | 42 | false | false | PASS | logs/deno-final.log:64 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-214 | accounts | usernameValid | username bounds | "ab" | false | false | PASS | logs/deno-final.log:69 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-215 | accounts | usernameValid | username bounds | "abc" | true | true | PASS | logs/deno-final.log:74 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-216 | accounts | usernameValid | username bounds | "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" | true | true | PASS | logs/deno-final.log:79 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-217 | accounts | usernameValid | username bounds | "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" | false | false | PASS | logs/deno-final.log:84 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-218 | accounts | usernameValid | username bounds | "Aaa" | false | false | PASS | logs/deno-final.log:89 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-219 | accounts | usernameValid | username bounds | "a-b" | false | false | PASS | logs/deno-final.log:94 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-220 | accounts | usernameValid | username bounds | "a.b_1" | true | true | PASS | logs/deno-final.log:99 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-221 | accounts | uuidValid | UUID structure and version | "11111111-1111-4111-8111-111111111111" | true | true | PASS | logs/deno-final.log:104 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-222 | accounts | uuidValid | UUID structure and version | "invalid" | false | false | PASS | logs/deno-final.log:109 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-223 | accounts | uuidValid | UUID structure and version | "11111111-1111-0111-8111-111111111111" | false | false | PASS | logs/deno-final.log:114 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-224 | accounts | uuidValid | UUID structure and version | "" | false | false | PASS | logs/deno-final.log:119 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-225 | accounts | optionalString | type, missing, boundary, NUL | "undefined" | null | null | PASS | logs/deno-final.log:124 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-226 | accounts | optionalString | type, missing, boundary, NUL | "null" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:129 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-227 | accounts | optionalString | type, missing, boundary, NUL | "42" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:134 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-228 | accounts | optionalString | type, missing, boundary, NUL | "a" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:139 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-229 | accounts | optionalString | type, missing, boundary, NUL | "abc" | null | null | PASS | logs/deno-final.log:144 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-230 | accounts | optionalString | type, missing, boundary, NUL | "abcd" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:149 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-231 | accounts | optionalString | type, missing, boundary, NUL | "a\u0000b" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:154 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-232 | accounts | optionalString | normalization precedes validation | " ABC " | "abc" | "abc" | PASS | logs/deno-final.log:159 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-233 | accounts | optionalBoolean | strict boolean types | "true" | null | null | PASS | logs/deno-final.log:164 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-234 | accounts | optionalBoolean | strict boolean types | "false" | null | null | PASS | logs/deno-final.log:169 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-235 | accounts | optionalBoolean | strict boolean types | "undefined" | null | null | PASS | logs/deno-final.log:174 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-236 | accounts | optionalBoolean | strict boolean types | "null" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:179 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-237 | accounts | optionalBoolean | strict boolean types | "true" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:184 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-238 | accounts | optionalBoolean | strict boolean types | "1" | "invalid_input" | "invalid_input" | PASS | logs/deno-final.log:189 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-239 | accounts | authProviderMessage | sanitized auth failure | "duplicate username" | "That username is already in use." | "That username is already in use." | PASS | logs/deno-final.log:194 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-240 | accounts | authProviderMessage | sanitized auth failure | "weak password" | "The password does not meet the authentication requirements." | "The password does not meet the authentication requirements." | PASS | logs/deno-final.log:199 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-241 | accounts | authProviderMessage | sanitized auth failure | "secret db details" | "The authentication account could not be processed. Check the details and try again." | "The authentication account could not be processed. Check the details and try again." | PASS | logs/deno-final.log:204 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-242 | accounts | databaseBusinessMessage | unique username | "23505 username" | "That username is already in use." | "That username is already in use." | PASS | logs/deno-final.log:209 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-243 | accounts | databaseBusinessMessage | unknown database error hidden | "XX001 internal details" | null | null | PASS | logs/deno-final.log:214 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-244 | contract-period | contractPeriod | ordered real-date validation | ["2026-09-05","2026-09-05"] | true | true | PASS | logs/deno-final.log:219 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-245 | contract-period | contractPeriod | ordered real-date validation | ["2026-09-06","2026-09-05"] | false | false | PASS | logs/deno-final.log:224 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-246 | contract-period | contractPeriod | ordered real-date validation | ["2026-02-30","2026-03-01"] | false | false | PASS | logs/deno-final.log:229 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-247 | contract-period | contractPeriod | ordered real-date validation | ["2028-02-29","2028-02-29"] | true | true | PASS | logs/deno-final.log:234 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-248 | contract-period | contractPeriod | ordered real-date validation | ["",""] | false | false | PASS | logs/deno-final.log:239 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-249 | contract-period | contractPeriod | ordered real-date validation | [null,null] | false | false | PASS | logs/deno-final.log:244 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-250 | contract-period | contractPeriod | ordered real-date validation | [42,43] | false | false | PASS | logs/deno-final.log:249 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-251 | contract-period | contractPeriod | legacy dates explicitly allowed | [null,null,true] | {"start":null,"end":null} | {"start":null,"end":null} | PASS | logs/deno-final.log:254 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-252 | contract-period | contractPeriod | regular category clears dates | "regular" | {"start":null,"end":null} | {"start":null,"end":null} | PASS | logs/deno-final.log:259 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-253 | api | handleJsonPost | JSON object validation | {} | 200 | 200 | PASS | logs/deno-final.log:264 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-254 | api | handleJsonPost | JSON object validation | [] | 400 | 400 | PASS | logs/deno-final.log:269 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-255 | api | handleJsonPost | JSON object validation | null | 400 | 400 | PASS | logs/deno-final.log:274 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-256 | api | handleJsonPost | JSON object validation | "text" | 400 | 400 | PASS | logs/deno-final.log:279 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-257 | api | handleJsonPost | JSON object validation | 4 | 400 | 400 | PASS | logs/deno-final.log:284 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-258 | api | handleJsonPost | request headers validated | {"Content-Type":"text/plain"} | 415 | 415 | PASS | logs/deno-final.log:289 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-259 | api | handleJsonPost | request headers validated | {"Content-Length":"-1"} | 400 | 400 | PASS | logs/deno-final.log:294 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-260 | api | handleJsonPost | request headers validated | {"Content-Length":"32769"} | 413 | 413 | PASS | logs/deno-final.log:299 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-261 | api | handleJsonPost | request headers validated | {"Origin":"https://untrusted.invalid"} | 403 | 403 | PASS | logs/deno-final.log:304 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-262 | api | handleJsonPost | method routing | "GET" | 405 | 405 | PASS | logs/deno-final.log:309 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-263 | api | handleJsonPost | method routing | "OPTIONS" | 204 | 204 | PASS | logs/deno-final.log:314 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-264 | api | handleJsonPost | invalid JSON | "{broken" | 400 | 400 | PASS | logs/deno-final.log:319 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-265 | api | handleJsonPost | actual UTF8 size limit | "32769 x characters" | 413 | 413 | PASS | logs/deno-final.log:325 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-266 | api | handleJsonPost | unexpected exception sanitized | "Error(secret)" | [500,"internal_error",false] | [500,"internal_error",false] | PASS | logs/deno-final.log:330 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-267 | api | handleJsonPost | allowed CORS and correlation headers | "localhost origin; WB-request" | ["http://localhost:3000","WB-request","no-store"] | ["http://localhost:3000","WB-request","no-store"] | PASS | logs/deno-final.log:336 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-268 | api | authenticatedUserId | malformed authorization rejected | "" | "unauthorized" | "unauthorized" | PASS | logs/deno-final.log:341 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-269 | api | authenticatedUserId | malformed authorization rejected | "Basic fixture" | "unauthorized" | "unauthorized" | PASS | logs/deno-final.log:346 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-270 | api | authenticatedUserId | malformed authorization rejected | "Bearer" | "unauthorized" | "unauthorized" | PASS | logs/deno-final.log:351 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-271 | api | authenticatedUserId | malformed authorization rejected | "Bearer two tokens" | "unauthorized" | "unauthorized" | PASS | logs/deno-final.log:356 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-272 | api | authenticatedUserId | auth provider verifies token | {"authFailed":false} | "11111111-1111-4111-8111-111111111111" | "11111111-1111-4111-8111-111111111111" | PASS | logs/deno-final.log:361 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-273 | api | authenticatedUserId | auth provider verifies token | {"authFailed":true} | "unauthorized" | "unauthorized" | PASS | logs/deno-final.log:366 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-274 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {} | [200,["begin","remove","finish"]] | [200,["begin","remove","finish"]] | PASS | logs/deno-final.log:372 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-275 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"authFailed":true} | [401,[]] | [401,[]] | PASS | logs/deno-final.log:377 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-276 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"beginError":"42501"} | [403,["begin"]] | [403,["begin"]] | PASS | logs/deno-final.log:382 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-277 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"beginError":"P0002"} | [404,["begin"]] | [404,["begin"]] | PASS | logs/deno-final.log:387 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-278 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"beginError":"XX001"} | [500,["begin"]] | [500,["begin"]] | PASS | logs/deno-final.log:392 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-279 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"missingIncident":true} | [500,["begin"]] | [500,["begin"]] | PASS | logs/deno-final.log:398 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-280 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"deleted":true} | [200,["begin"]] | [200,["begin"]] | PASS | logs/deno-final.log:404 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-281 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"shared":true} | [200,["begin","finish"]] | [200,["begin","finish"]] | PASS | logs/deno-final.log:410 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-282 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"path":null} | [200,["begin","finish"]] | [200,["begin","finish"]] | PASS | logs/deno-final.log:416 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-283 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"path":"11111111-1111-4111-8111-111111111111/../x"} | [409,["begin"]] | [409,["begin"]] | PASS | logs/deno-final.log:421 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-284 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"path":"22222222-2222-4222-8222-222222222222/clip.mp4"} | [409,["begin"]] | [409,["begin"]] | PASS | logs/deno-final.log:426 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-285 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"mediaError":true} | [502,["begin","remove"]] | [502,["begin","remove"]] | PASS | logs/deno-final.log:431 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-286 | deleteIncidentHandler | deleteIncidentHandler | authorization and ordered failure handling | {"finishError":true} | [500,["begin","remove","finish"]] | [500,["begin","remove","finish"]] | PASS | logs/deno-final.log:437 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-287 | deleteIncidentHandler | deleteIncidentHandler | invalid ID never touches database | null | [400,[]] | [400,[]] | PASS | logs/deno-final.log:443 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-288 | deleteIncidentHandler | deleteIncidentHandler | invalid ID never touches database | "" | [400,[]] | [400,[]] | PASS | logs/deno-final.log:448 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-289 | deleteIncidentHandler | deleteIncidentHandler | invalid ID never touches database | 42 | [400,[]] | [400,[]] | PASS | logs/deno-final.log:453 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-290 | deleteIncidentHandler | deleteIncidentHandler | invalid ID never touches database | "invalid" | [400,[]] | [400,[]] | PASS | logs/deno-final.log:458 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-291 | admin-create-user | registered handler | caller role and active restrictions | {"role":"user","active":false} | 403 | 403 | PASS | logs/deno-final.log:463 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-292 | admin-create-user | registered handler | caller role and active restrictions | {"role":"user","active":true} | 403 | 403 | PASS | logs/deno-final.log:468 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-293 | admin-create-user | registered handler | caller role and active restrictions | {"role":"inspector","active":false} | 403 | 403 | PASS | logs/deno-final.log:473 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-294 | admin-create-user | registered handler | caller role and active restrictions | {"role":"inspector","active":true} | 403 | 403 | PASS | logs/deno-final.log:478 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-295 | admin-create-user | registered handler | caller role and active restrictions | {"role":"admin","active":false} | 403 | 403 | PASS | logs/deno-final.log:483 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-296 | admin-create-user | registered handler | caller role and active restrictions | {"role":"admin","active":true} | 200 | 200 | PASS | logs/deno-final.log:489 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-297 | admin-create-user | registered handler | caller role and active restrictions | {"role":"it_admin","active":false} | 403 | 403 | PASS | logs/deno-final.log:494 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-298 | admin-create-user | registered handler | caller role and active restrictions | {"role":"it_admin","active":true} | 403 | 403 | PASS | logs/deno-final.log:499 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-299 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{},"body":{"role":"admin"}} | [403,"forbidden_role"] | [403,"forbidden_role"] | PASS | logs/deno-final.log:504 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-300 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"caller":{"role":"it_admin"}},"body":{"role":"admin"}} | [200,null] | [200,null] | PASS | logs/deno-final.log:510 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-301 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"caller":{"role":"it_admin"}},"body":{"role":"it_admin"}} | [200,null] | [200,null] | PASS | logs/deno-final.log:516 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-302 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"caller":{"organization_id":null}},"body":{}} | [403,"forbidden"] | [403,"forbidden"] | PASS | logs/deno-final.log:521 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-303 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"duplicate":true},"body":{}} | [409,"username_in_use"] | [409,"username_in_use"] | PASS | logs/deno-final.log:526 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-304 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{},"body":{"password":"12345"}} | [400,"invalid_input"] | [400,"invalid_input"] | PASS | logs/deno-final.log:531 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-305 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{},"body":{"password":42}} | [400,"invalid_input"] | [400,"invalid_input"] | PASS | logs/deno-final.log:536 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-306 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{},"body":{"role":"owner"}} | [400,"invalid_role"] | [400,"invalid_role"] | PASS | logs/deno-final.log:541 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-307 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{},"body":{"username":"x!"}} | [400,"invalid_username"] | [400,"invalid_username"] | PASS | logs/deno-final.log:546 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-308 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"authError":true},"body":{}} | [400,"auth_account_create_failed"] | [400,"auth_account_create_failed"] | PASS | logs/deno-final.log:551 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-309 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"profileError":true},"body":{}} | [500,"profile_create_failed"] | [500,"profile_create_failed"] | PASS | logs/deno-final.log:557 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-310 | admin-create-user | registered handler | validation, duplicate and rollback | {"options":{"profileError":true,"rollbackError":true},"body":{}} | [500,"account_create_rollback_failed"] | [500,"account_create_rollback_failed"] | PASS | logs/deno-final.log:563 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-311 | admin-manage-user | registered handler | management permission and retention rules | {"options":{"caller":{"role":"user"}},"body":{}} | [403,"forbidden",[]] | [403,"forbidden",[]] | PASS | logs/deno-final.log:570 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-312 | admin-manage-user | registered handler | management permission and retention rules | {"options":{"caller":{"active":false}},"body":{}} | [403,"forbidden",[]] | [403,"forbidden",[]] | PASS | logs/deno-final.log:575 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-313 | admin-manage-user | registered handler | management permission and retention rules | {"options":{},"body":{"action":"delete"}} | [409,"account_deletion_disabled",[]] | [409,"account_deletion_disabled",[]] | PASS | logs/deno-final.log:580 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-314 | admin-manage-user | registered handler | management permission and retention rules | {"options":{},"body":{"action":"bad"}} | [400,"invalid_action",[]] | [400,"invalid_action",[]] | PASS | logs/deno-final.log:585 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-315 | admin-manage-user | registered handler | management permission and retention rules | {"options":{},"body":{"userId":"11111111-1111-4111-8111-111111111111"}} | [400,"self_management_blocked",[]] | [400,"self_management_blocked",[]] | PASS | logs/deno-final.log:590 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-316 | admin-manage-user | registered handler | management permission and retention rules | {"options":{"target":{"organization_id":"org2"}},"body":{}} | [403,"forbidden_target",[]] | [403,"forbidden_target",[]] | PASS | logs/deno-final.log:595 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-317 | admin-manage-user | registered handler | management permission and retention rules | {"options":{},"body":{"role":"inspector"}} | [403,"forbidden_role",[]] | [403,"forbidden_role",[]] | PASS | logs/deno-final.log:600 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-318 | admin-manage-user | registered handler | management permission and retention rules | {"options":{"caller":{"role":"it_admin"}},"body":{}} | [403,"forbidden_target",[]] | [403,"forbidden_target",[]] | PASS | logs/deno-final.log:605 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-319 | admin-manage-user | registered handler | management permission and retention rules | {"options":{"caller":{"role":"it_admin"},"target":{"role":"it_admin"},"itCount":1},"body":{"active":false}} | [409,"last_it_admin",[]] | [409,"last_it_admin",[]] | PASS | logs/deno-final.log:610 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-320 | admin-manage-user | registered handler | management permission and retention rules | {"options":{},"body":{"active":"true"}} | [400,"invalid_input",[]] | [400,"invalid_input",[]] | PASS | logs/deno-final.log:615 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-321 | it-provision-client | registered handler | retired provisioning returns gone | {} | [410,"client_provisioning_retired"] | [410,"client_provisioning_retired"] | PASS | logs/deno-final.log:620 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-322 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{},"body":{"firstName":"Changed"}} | [200,null,["profileUpdate","authUpdate"]] | [200,null,["profileUpdate","authUpdate"]] | PASS | logs/deno-final.log:626 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-323 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{},"body":{"resetDevice":true}} | [200,null,["profileUpdate","authUpdate"]] | [200,null,["profileUpdate","authUpdate"]] | PASS | logs/deno-final.log:632 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-324 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"caller":{"role":"it_admin"},"target":{"role":"admin"}},"body":{}} | [200,null,["profileUpdate","authUpdate"]] | [200,null,["profileUpdate","authUpdate"]] | PASS | logs/deno-final.log:638 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-325 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"caller":{"role":"it_admin"},"target":{"role":"it_admin"},"itCount":2},"body":{"active":false}} | [200,null,["profileUpdate","authUpdate"]] | [200,null,["profileUpdate","authUpdate"]] | PASS | logs/deno-final.log:644 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-326 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"authLookupError":true},"body":{}} | [500,"auth_account_lookup_failed",[]] | [500,"auth_account_lookup_failed",[]] | PASS | logs/deno-final.log:649 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-327 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"profileError":true},"body":{}} | [500,"profile_update_failed",["profileUpdate"]] | [500,"profile_update_failed",["profileUpdate"]] | PASS | logs/deno-final.log:655 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-328 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"authUpdateError":true},"body":{}} | [400,"auth_account_update_failed",["profileUpdate","authUpdate","profileUpdate"]] | [400,"auth_account_update_failed",["profileUpdate","authUpdate","profileUpdate"]] | PASS | logs/deno-final.log:661 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-329 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"authUpdateError":true,"updateRollbackError":true},"body":{}} | [500,"account_update_rollback_failed",["profileUpdate","authUpdate","profileUpdate"]] | [500,"account_update_rollback_failed",["profileUpdate","authUpdate","profileUpdate"]] | PASS | logs/deno-final.log:667 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-330 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{"duplicate":true},"body":{}} | [409,"username_in_use",[]] | [409,"username_in_use",[]] | PASS | logs/deno-final.log:674 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-331 | admin-manage-user | registered handler | successful update and rollback safety | {"options":{},"body":{"employmentCategory":"contract","contractStartDate":"2026-02-30","contractEndDate":"2026-03-01"}} | [400,"invalid_contract_period",[]] | [400,"invalid_contract_period",[]] | PASS | logs/deno-final.log:679 | External Supabase SDK replaced with explicit in-memory fake; no network or real database. |
| WB-401 | SchedulePeriod | calculate | shift duration and time validity | ["2026-09-05","08:00","17:00"] | 540 | 540 | PASS | logs/node.tap:2 | Direct production function execution. |
| WB-402 | SchedulePeriod | calculate | shift duration and time validity | ["2026-09-05","20:00","04:00"] | 480 | 480 | PASS | logs/node.tap:3 | Direct production function execution. |
| WB-403 | SchedulePeriod | calculate | shift duration and time validity | ["2026-09-05","08:00","08:00"] | null | null | PASS | logs/node.tap:4 | Direct production function execution. |
| WB-404 | SchedulePeriod | calculate | shift duration and time validity | ["2026-02-30","08:00","17:00"] | null | null | PASS | logs/node.tap:5 | Direct production function execution. |
| WB-405 | SchedulePeriod | calculate | shift duration and time validity | ["2028-02-29","23:59","00:00"] | 1 | 1 | PASS | logs/node.tap:6 | Direct production function execution. |
| WB-406 | SchedulePeriod | calculate | shift duration and time validity | ["2026-09-05","24:00","17:00"] | null | null | PASS | logs/node.tap:7 | Direct production function execution. |
| WB-407 | SchedulePeriod | calculate | shift duration and time validity | ["2026-09-05","08:60","17:00"] | null | null | PASS | logs/node.tap:8 | Direct production function execution. |
| WB-408 | SchedulePeriod | calculate | shift duration and time validity | ["2026-09-05","","17:00"] | null | null | PASS | logs/node.tap:9 | Direct production function execution. |
| WB-409 | SchedulePeriod | dtrPeriodForDate | calendar and cutoff boundary | "2026-09-15" | "2026-09-15" | "2026-09-15" | PASS | logs/node.tap:10 | Direct production function execution. |
| WB-410 | SchedulePeriod | dtrPeriodForDate | calendar and cutoff boundary | "2026-09-16" | "2026-09-30" | "2026-09-30" | PASS | logs/node.tap:11 | Direct production function execution. |
| WB-411 | SchedulePeriod | dtrPeriodForDate | calendar and cutoff boundary | "2028-02-29" | "2028-02-29" | "2028-02-29" | PASS | logs/node.tap:12 | Direct production function execution. |
| WB-412 | SchedulePeriod | dtrPeriodForDate | calendar and cutoff boundary | "2026-02-29" | null | null | PASS | logs/node.tap:13 | Direct production function execution. |
| WB-413 | SchedulePeriod | dtrPeriodForDate | calendar and cutoff boundary | "2026-13-01" | null | null | PASS | logs/node.tap:14 | Direct production function execution. |
| WB-414 | SchedulePeriod | dtrPeriodForDate | calendar and cutoff boundary | "" | null | null | PASS | logs/node.tap:15 | Direct production function execution. |
| WB-415 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | [] | false | false | PASS | logs/node.tap:16 | Direct production function execution. |
| WB-416 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | null | false | false | PASS | logs/node.tap:17 | Direct production function execution. |
| WB-417 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | [{"period":"morning","start_time":"08:00","end_time":"12:00"},{"period":"afternoon","start_time":"12:00","end_time":"17:00"}] | true | true | PASS | logs/node.tap:18 | Direct production function execution. |
| WB-418 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | [{"period":"morning","start_time":"08:00","end_time":"12:00"},{"period":"afternoon","start_time":"11:59","end_time":"17:00"}] | false | false | PASS | logs/node.tap:19 | Direct production function execution. |
| WB-419 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | [{"period":"morning","start_time":"08:00","end_time":"12:00"},{"period":"morning","start_time":"13:00","end_time":"17:00"}] | false | false | PASS | logs/node.tap:20 | Direct production function execution. |
| WB-420 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | [{"period":"auto","start_time":"08:00","end_time":"12:00"},{"period":"afternoon","start_time":"13:00","end_time":"17:00"}] | false | false | PASS | logs/node.tap:21 | Direct production function execution. |
| WB-421 | SchedulePeriod | buildDutyPlan | empty, overlap and duplicate periods | [{"period":"unknown","start_time":"08:00","end_time":"12:00"}] | false | false | PASS | logs/node.tap:22 | Direct production function execution. |
| WB-422 | SchedulePeriod | buildDutyPlan | sum periods excludes unpaid gap | "08-12 + 13-17" | 480 | 480 | PASS | logs/node.tap:23 | Direct production function execution. |
| WB-423 | SchedulePeriod | buildDutyPlan | null entry should return validation error | [null] | true | "Exception: TypeError: Cannot read properties of null (reading 'period')" | FAIL | logs/node.tap:24 | Direct production function execution. |
| WB-424 | SchedulePeriod | dtrColumnForTime | noon and invalid direction | ["12:00","IN"] | "Afternoon IN" | "Afternoon IN" | PASS | logs/node.tap:25 | Direct production function execution. |
| WB-425 | SchedulePeriod | dtrColumnForTime | noon and invalid direction | ["12:00","OUT"] | "Morning OUT" | "Morning OUT" | PASS | logs/node.tap:26 | Direct production function execution. |
| WB-426 | SchedulePeriod | dtrColumnForTime | noon and invalid direction | ["12:01","OUT"] | "Afternoon OUT" | "Afternoon OUT" | PASS | logs/node.tap:27 | Direct production function execution. |
| WB-427 | SchedulePeriod | dtrColumnForTime | noon and invalid direction | ["23:59","IN"] | "Afternoon IN" | "Afternoon IN" | PASS | logs/node.tap:28 | Direct production function execution. |
| WB-428 | SchedulePeriod | dtrColumnForTime | noon and invalid direction | ["24:00","IN"] | null | null | PASS | logs/node.tap:29 | Direct production function execution. |
| WB-429 | SchedulePeriod | dtrColumnForTime | noon and invalid direction | ["08:00","BAD"] | null | null | PASS | logs/node.tap:30 | Direct production function execution. |
| WB-430 | ContractPeriodJS | validate | ordered real dates | ["2026-09-05","2026-09-05"] | true | true | PASS | logs/node.tap:31 | Direct production function execution. |
| WB-431 | ContractPeriodJS | validate | ordered real dates | ["2026-09-06","2026-09-05"] | false | false | PASS | logs/node.tap:32 | Direct production function execution. |
| WB-432 | ContractPeriodJS | validate | ordered real dates | ["2026-02-30","2026-03-01"] | false | false | PASS | logs/node.tap:33 | Direct production function execution. |
| WB-433 | ContractPeriodJS | validate | ordered real dates | [null,null] | false | false | PASS | logs/node.tap:34 | Direct production function execution. |
| WB-434 | ContractPeriodJS | validate | ordered real dates | ["1899-12-31","1900-01-01"] | false | false | PASS | logs/node.tap:35 | Direct production function execution. |
| WB-435 | ContractPeriodJS | validate | ordered real dates | ["2028-02-29","2028-02-29"] | true | true | PASS | logs/node.tap:36 | Direct production function execution. |
| WB-436 | ContractPeriodJS | dutyError | entire duty must fit contract | ["2026-09-05T00:00:00+08:00","2026-09-06T00:00:00+08:00"] | true | true | PASS | logs/node.tap:37 | Direct production function execution. |
| WB-437 | ContractPeriodJS | dutyError | entire duty must fit contract | ["2026-09-05T20:00:00+08:00","2026-09-06T04:00:00+08:00"] | false | false | PASS | logs/node.tap:38 | Direct production function execution. |
| WB-438 | ContractPeriodJS | dutyError | entire duty must fit contract | ["2026-09-04T23:59:59+08:00","2026-09-05T08:00:00+08:00"] | false | false | PASS | logs/node.tap:39 | Direct production function execution. |
| WB-439 | ContractPeriodJS | dutyError | entire duty must fit contract | ["2026-09-05T08:00:00+08:00","2026-09-05T08:00:00+08:00"] | false | false | PASS | logs/node.tap:40 | Direct production function execution. |
| WB-440 | DtrReport | sessionMinutes | duration boundaries | {} | 0 | 0 | PASS | logs/node.tap:41 | Direct production function execution. |
| WB-441 | DtrReport | sessionMinutes | duration boundaries | {"clock_in_at":"invalid","clock_out_at":"invalid"} | 0 | 0 | PASS | logs/node.tap:42 | Direct production function execution. |
| WB-442 | DtrReport | sessionMinutes | duration boundaries | {"clock_in_at":"2026-09-05T00:00Z","clock_out_at":"2026-09-05T08:00Z"} | 480 | 480 | PASS | logs/node.tap:43 | Direct production function execution. |
| WB-443 | DtrReport | sessionMinutes | duration boundaries | {"clock_in_at":"2026-09-05T00:00Z","clock_out_at":"2026-09-04T23:59Z"} | 0 | 0 | PASS | logs/node.tap:44 | Direct production function execution. |
| WB-444 | DtrReport | sessionMinutes | duration boundaries | {"clock_in_at":"2026-09-05T00:00Z","clock_out_at":"2026-09-05T00:00:59Z"} | 0 | 0 | PASS | logs/node.tap:45 | Direct production function execution. |
| WB-445 | DtrReport | periodFromSelection | calendar selection | ["2028-02","second"] | "2028-02-29" | "2028-02-29" | PASS | logs/node.tap:46 | Direct production function execution. |
| WB-446 | DtrReport | periodFromSelection | calendar selection | ["2026-02","second"] | "2026-02-28" | "2026-02-28" | PASS | logs/node.tap:47 | Direct production function execution. |
| WB-447 | DtrReport | periodFromSelection | calendar selection | ["2026-09","first"] | "2026-09-15" | "2026-09-15" | PASS | logs/node.tap:48 | Direct production function execution. |
| WB-448 | DtrReport | periodFromSelection | calendar selection | ["2026-13","first"] | null | null | PASS | logs/node.tap:49 | Direct production function execution. |
| WB-449 | DtrReport | periodFromSelection | calendar selection | ["bad","first"] | null | null | PASS | logs/node.tap:50 | Direct production function execution. |
| WB-450 | DtrReport | periodFromSelection | calendar selection | ["2026-09","third"] | null | null | PASS | logs/node.tap:51 | Direct production function execution. |
| WB-451 | DtrReport | buildReport | empty attendance creates zero totals | [] | [0,0,15] | [0,0,15] | PASS | logs/node.tap:52 | Direct production function execution. |
| WB-452 | DtrReport | filterSessions | inclusive cutoff bounds | ["2026-08-31","2026-09-01","2026-09-15","2026-09-16"] | ["2026-09-01","2026-09-15"] | ["2026-09-01","2026-09-15"] | PASS | logs/node.tap:53 | Direct production function execution. |
| WB-501 | UserProfileService | validateGuardLogin | role and active branches | {"role":"user","active":false} | "Your account has been disabled. Contact your administrator." | "Your account has been disabled. Contact your administrator." | PASS | logs/flutter-verified.jsonl:171 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-502 | UserProfileService | validateGuardLogin | role and active branches | {"role":"user","active":true} | null | null | PASS | logs/flutter-verified.jsonl:180 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-503 | UserProfileService | validateGuardLogin | role and active branches | {"role":"inspector","active":false} | "Inspector accounts use the web panel." | "Inspector accounts use the web panel." | PASS | logs/flutter-verified.jsonl:189 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-504 | UserProfileService | validateGuardLogin | role and active branches | {"role":"inspector","active":true} | "Inspector accounts use the web panel." | "Inspector accounts use the web panel." | PASS | logs/flutter-verified.jsonl:195 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-505 | UserProfileService | validateGuardLogin | role and active branches | {"role":"admin","active":false} | "admin" | "admin" | PASS | logs/flutter-verified.jsonl:201 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-506 | UserProfileService | validateGuardLogin | role and active branches | {"role":"admin","active":true} | "admin" | "admin" | PASS | logs/flutter-verified.jsonl:207 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-507 | UserProfileService | validateGuardLogin | role and active branches | {"role":"it_admin","active":false} | "it_admin" | "it_admin" | PASS | logs/flutter-verified.jsonl:216 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-508 | UserProfileService | validateGuardLogin | role and active branches | {"role":"it_admin","active":true} | "it_admin" | "it_admin" | PASS | logs/flutter-verified.jsonl:222 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-509 | UserProfileService | validateGuardLogin | missing profile | null | "Account profile not found. Contact your administrator." | "Account profile not found. Contact your administrator." | PASS | logs/flutter-verified.jsonl:230 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-510 | UserProfileService | validateGuardLogin | unknown active role must be denied | {"role":"owner","active":true} | true | false | FAIL | logs/flutter-verified.jsonl:253 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-511 | UserProfileService | getProfile | database error propagated | "HTTP403" | true | true | PASS | logs/flutter-verified.jsonl:263 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-512 | UserRoleService | getRole | profile role returned | "admin" | "admin" | "admin" | PASS | logs/flutter-verified.jsonl:269 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-513 | UserRoleService | currentUserRole | no auth session returns null | null | [null,0] | [null,0] | PASS | logs/flutter-verified.jsonl:275 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-514 | UserRoleService | isAdmin | anonymous user denied | null | false | false | PASS | logs/flutter-verified.jsonl:281 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-515 | UserProfileService | registerDeviceIfNeeded | RPC body preserves device identity | "device-fixture" | {"p_device_id":"device-fixture"} | {"p_device_id":"device-fixture"} | PASS | logs/flutter-verified.jsonl:290 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-516 | AttendanceService | loadOpenSession | no open session | null | null | null | PASS | logs/flutter-verified.jsonl:299 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-517 | AttendanceService | loadOpenSession | query scoped to owner and open status | "g" | ["eq.g","eq.open","1"] | ["eq.g","eq.open","1"] | PASS | logs/flutter-verified.jsonl:308 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-518 | AttendanceService | recordEvent | RPC sends exact validated coordinates | "clock_in;0;0" | {"p_action":"clock_in","p_latitude":0,"p_longitude":0} | {"p_action":"clock_in","p_latitude":0,"p_longitude":0} | PASS | logs/flutter-verified.jsonl:317 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-519 | AttendanceService | recordEvent | invalid server response fails | "scalar response" | true | true | PASS | logs/flutter-verified.jsonl:320 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-520 | AttendanceService | recordEvent | database denial propagates | "HTTP403" | true | true | PASS | logs/flutter-verified.jsonl:323 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-521 | NotificationService | markRead | scoped notification RPC | "n1" | {"p_notification_id":"n1"} | {"p_notification_id":"n1"} | PASS | logs/flutter-verified.jsonl:326 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-522 | NotificationService | acknowledge | acknowledgement RPC | "n1" | {"p_notification_id":"n1"} | {"p_notification_id":"n1"} | PASS | logs/flutter-verified.jsonl:329 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-523 | NotificationService | markAllRead | numeric result or safe default | 3 | 3 | 3 | PASS | logs/flutter-verified.jsonl:337 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-524 | NotificationService | markAllRead | numeric result or safe default | null | 0 | 0 | PASS | logs/flutter-verified.jsonl:343 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-525 | NotificationService | markAllRead | numeric result or safe default | "bad" | 0 | 0 | PASS | logs/flutter-verified.jsonl:352 | Real Dart service and Supabase client; HTTP responses mocked. |
| WB-701 | PostgreSQL / Supabase | record_attendance_event | anonymous or disabled actor | "Planned isolated pgTAP fixture: anonymous or disabled actor" | "denied without insert" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-702 | PostgreSQL / Supabase | record_attendance_event | duplicate time-in and missing time-out session | "Planned isolated pgTAP fixture: duplicate time-in and missing time-out session" | "second punch rejected; one open session" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-703 | PostgreSQL / Supabase | record_attendance_event | foreign tenant schedule / invalid geofence | "Planned isolated pgTAP fixture: foreign tenant schedule / invalid geofence" | "denied transaction" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-704 | PostgreSQL / Supabase | submit_duty_exchange | reciprocal approved shifts / foreign agency | "Planned isolated pgTAP fixture: reciprocal approved shifts / foreign agency" | "valid atomic swap; cross-agency rejection" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-705 | PostgreSQL / Supabase | submit_duty_request | same letter key submitted twice | "Planned isolated pgTAP fixture: same letter key submitted twice" | "one request; idempotent retry" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-706 | PostgreSQL / Supabase | manage_incident_deletion | guard, inspector, admin, foreign tenant | "Planned isolated pgTAP fixture: guard, inspector, admin, foreign tenant" | "only scoped admin may delete" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-707 | PostgreSQL / Supabase | contract enforcement | start/end date boundaries and expired guard | "Planned isolated pgTAP fixture: start/end date boundaries and expired guard" | "inclusive contract; new duty blocked outside dates" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-708 | PostgreSQL / Supabase | notification RPCs / RLS | foreign notification identifier | "Planned isolated pgTAP fixture: foreign notification identifier" | "recipient isolation" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-709 | PostgreSQL / Supabase | schedule lifecycle | completed shift mutation and cancelled duty | "Planned isolated pgTAP fixture: completed shift mutation and cancelled duty" | "retention and lifecycle constraints enforced" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |
| WB-710 | PostgreSQL / Supabase | inspector assignment RLS | assigned versus unrelated guard | "Planned isolated pgTAP fixture: assigned versus unrelated guard" | "only assigned guard scope returned" | "No isolated PostgreSQL runtime or Docker available" | NOT EXECUTED | logs/database-tools.log | Planned database acceptance case; mock-client tests do not establish RLS correctness. |

## References

- Flutter testing: https://docs.flutter.dev/testing/overview
- Sonar Dart LCOV import: https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/test-coverage/dart-test-coverage
- Sonar coverage parameters: https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/test-coverage/test-coverage-parameters
