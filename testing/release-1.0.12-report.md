# Release 1.0.12 / Build 13

Published on September 8, 2026.

## Changes

- New and changed passwords require at least 8 characters, including an uppercase letter, lowercase letter, digit, and symbol. Both account-management forms, both account Edge Functions, and the hosted Supabase Auth settings enforce the rule. Existing passwords remain usable; blank optional password edits preserve the current password.
- Password validation now respects the provider's 72-byte maximum and preserves the supplied secret exactly.
- Guard GPS capture stops at the known scheduled duty end even when a network refresh stalls. A permission prompt completing after duty end cannot restart capture, and an old duty timer cannot stop a newer duty.
- Cancelled dialogs cannot use a delayed validation result to confirm a different dialog.
- Schedule history displays the saved guard name when the current profile is unavailable, with HTML escaping retained.
- The Android update includes the earlier automatic GPS, moving markers, and Admin verification of missing Time Out changes.

## Validation

- Flutter analysis of `lib` and `test`: no issues.
- Flutter tests: 126 passed.
- Browser suite: 179 passed initially; two schedule-name assertions found the history display bug. After fixing it, all 23 schedule lifecycle checks passed, including a new regression test. All 182 current browser cases have passing results across the main run and focused rerun.
- Node security, password, session, GPS marker, DTR, branding, QR, and Android configuration checks passed.
- Deno password tests and nine incident-handler tests passed. Edge Function type, lint, and formatting checks passed.
- Android release build succeeded. Package `com.sentinellink.app`, version `1.0.12`, build `13`, non-debuggable, same signing certificate as the previously distributed APK. The existing capstone signing arrangement is documented in `docs/MOBILE_RELEASE.md`.
- Live Admin and IT Admin password forms verified. Live QR/modal browser checks passed with no page errors. Both browser and HTTP downloads completed and matched the local APK.
- APK SHA-256: `32bfcca62ca2b3be0bbe55821520787cae3450e613b966dd1c24f09cf9189ddd` (63,562,646 bytes).
- Automated checks did not install the APK on a physical phone or validate a real GPS route.

## Published destinations

- Portal: https://security-agency-management-system-nu.vercel.app
- IT Admin: https://security-agency-management-system-admin.vercel.app
- APK: https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.12
- Vercel deployment: `dpl_CJxY9n49qR9zgBsaz2hTy1iX1QkW`.
- Supabase project: `uqtupmpofjqrnefgrexm`; updated account Edge Functions and Auth password settings deployed.

The deployment, build, test, signature, source-manifest, and public-download evidence is saved alongside this report. Live modal evidence is in `build/qa/guard-app-modal/live/results.json`.
