# SonarQube analysis

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
