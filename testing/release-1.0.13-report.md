# Release 1.0.13 / Build 14

## Behavior

- Swap Duty and Absent remain available for duties scheduled today, ongoing overnight duties, and future duties, including after Time In or Time Out. Pending duplicate requests remain blocked. Approval and the required letter are retained.
- A started-duty Swap Duty request uses replacement coverage rather than rewriting a reciprocal exchange with existing attendance. The Operational Head confirms an open session's actual end and records a reason. The original schedule, recorded work, and a verification audit remain with the original Guard; a separate replacement schedule covers the remaining period. Partial absence preserves worked hours.
- Active-duty Time Out no longer waits for GPS permission, a fresh fix, or a site refresh. A recent trustworthy point is used when available; otherwise the server records missing GPS explicitly. Outside-post Time Out is recorded with a flag. The duty log and DTR show these flags. Time In remains geofenced. A forgotten Time Out after scheduled end still requires Operational Head verification.
- The agency Admin display label is Operational Head; role identifiers, permissions, and IT Admin labels are retained.
- Scheduling has a 2-Shift / 3-Shift dropdown, one Guard selector per shift, a named preview, and the Guards already assigned to the selected site/date/setup. Two shifts are 06:00–18:00 and 18:00–06:00 next day; three are 06:00–14:00, 14:00–22:00, and 22:00–06:00 next day. Saving is atomic and rejects duplicate Guards, conflicts, invalid contracts, and cross-agency assignments.
- Operational Head and Inspector navigation include a local SVG Live Map icon.

## Verification

- Flutter analysis: no issues. All 127 current Flutter cases have passing results across the full run and focused rerun (19 cases).
- All 185 browser cases have passing results across the full run (181 passed) and four focused reruns. One test selector was updated for the additional roster card; the other three passed on a single-worker rerun after timing failures.
- Database: 29 new behavior checks, 46 existing reciprocal-exchange checks, and 33 existing request/deletion checks passed in rollback-only transactions. The 29 new checks also passed after deployment.
- Node rendering-security, DTR, bundled-icon, branding, and QR checks passed. Desktop and phone roster screenshots were inspected; no horizontal phone overflow.
- No real phone GPS route was performed by these automated checks.

## Database deployment

Applied only `20260911000000_gps_timeout_and_same_day_requests` and `20260911000001_duty_relief_and_shift_rosters` to the linked project `uqtupmpofjqrnefgrexm`.

## Android and web deployment

- Android 1.0.13 (Build 14) was built and verified as a non-debuggable release with the existing application ID and signing certificate.
- APK size: 63,775,638 bytes. SHA-256: `c0662801c34bbadaaa6fe9dd4dbc7a3e83316346ad75a0498c292d7ce9953c92`.
- Vercel production deployment `dpl_BPWGub1y9trpVvQqEeKQhFQtDwQX` is ready at `https://security-agency-management-system-h2vax0lq6-codex-a9d1.vercel.app`. The primary, admin, and download public addresses point to this release.
- Live verification on September 12, 2026 passed for the password policy, roster, Operational Head labels, Live Map icon, duty relief, and exact deployed source comparisons. The complete public APK download matches the verified local size and checksum. Evidence: `release-1.0.13-live-verification.json`.
- Live browser checks passed for the QR target, light/dark install dialogs, keyboard focus, download headers, legacy download redirect, and absence of page errors. Chromium started the APK download but did not finish within the test's 20-second limit; the independent full HTTP download passed checksum verification. Evidence: `../build/qa/guard-app-modal/live/results.json`.
