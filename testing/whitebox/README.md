# White-box evidence package

Start with [the complete report](reports/White-Box-Testing-Report.md), or open [the HTML results viewer](reports/White-Box-Testing-Report.html).

- `unit_tests/`: new automated tests that import production code; no production fixes.
- `logs/flutter-verified.jsonl`: authoritative final Flutter JSON reporter stream.
- `logs/deno-final.log`: authoritative final backend unit output.
- `logs/node.tap`: authoritative JavaScript TAP output.
- `logs/WB-*.txt`: extracted per-case evidence, linked to original runner output.
- `coverage/`: original LCOV, path-normalized import copies, summary and Deno HTML.
- `sonarqube/`: real scanner/server logs, API exports and analysis configuration.
- `screenshots/`: genuine screenshots of saved runner evidence and SonarQube.
- `reports/test-cases.csv`: all test cases, including ten planned database cases marked NOT EXECUTED.
- `logs/source-integrity.json`: before/after SHA-256 comparison of 229 production files.

Tests cover selected important internal logic. This is not whole-system or complete branch coverage. Mocked service/SDK tests do not prove live Auth, storage or PostgreSQL RLS behavior. No browser testing framework was used. Browser interaction was only used to view/capture evidence.

## Reproduce from the repository root

Flutter 3.47.1 / Dart 3.13.1, Node 24.13.0 and Deno 2.9.6 were used. Dependencies must match the supplied pubspec.lock. The Deno import map replaces the external Supabase SDK with a fake; do not remove it when running these unit tests.

```powershell
flutter test --no-pub --branch-coverage --coverage-path testing/whitebox/coverage/dart.lcov.info --reporter json testing/whitebox/unit_tests/core_test.dart testing/whitebox/unit_tests/services_test.dart > testing/whitebox/logs/flutter-verified.jsonl
deno test --no-check --allow-env --config testing/whitebox/unit_tests/deno.json --coverage=testing/whitebox/coverage/deno-final testing/whitebox/unit_tests/backend_test.ts > testing/whitebox/logs/deno-final.log
node --test --experimental-test-coverage --test-coverage-include='web/js/*.js' --test-reporter=tap --test-reporter-destination=testing/whitebox/logs/node.tap --test-reporter=lcov --test-reporter-destination=testing/whitebox/coverage/javascript.lcov.info testing/whitebox/unit_tests/web_test.cjs
node testing/whitebox/reports/build-report.cjs
```

Expected current outcomes: Flutter exits nonzero for two reproduced defects; Node exits nonzero for one defect; Deno passes. Reruns replace evidence at these paths; archive this package first. `--no-check` on Deno permits the intentionally partial SDK fake; this is runtime unit testing, not a TypeScript type-check result.

## Local SonarQube

The evaluation server resides outside the repository at `C:/Temp/sams-whitebox-tools/sonarqube-26.9.0.129388`. It is configured to bind to `127.0.0.1:9000` only, with embedded H2 for evaluation. The initial default password was changed; the current local credential is DPAPI-encrypted outside this package. Analysis tokens are revoked after each run. No credentials are included in this evidence package.

Run `sonarqube/run-local-analysis.ps1` from the repository root with the local evaluation server running. This script is specific to this local evaluation instance; do not use it against a shared server. SonarQube Community Build does not list a Dart analyzer: Dart LCOV remains standalone evidence, while JavaScript/TypeScript coverage can be imported. The language list is retained in `sonarqube/languages.json`.

Screenshots are captures of rendered saved evidence, not screenshots of a terminal during execution. Original machine-readable execution logs are the primary proof. Failed setup attempts are retained and excluded from final test totals. PostgreSQL test execution was unavailable; the ten database cases are a follow-up plan, not fabricated executions.

After rebuilding the report, run `node testing/whitebox/reports/finalize-sonar.cjs` to integrate the final SonarQube exports. The quality gate checks new violations relative to the earlier baseline; it does not override unit failures.

