# Guard app download flow

- Staff login **Open mobile setup** and **Get app** open the shared installation modal without navigating or clearing login input.
- The QR image and its clickable link target the APK itself. There is no setup-page or modal intermediary for a scan. The scanner/browser may require the person to open the QR link and approve the download; installation always follows Android's permission flow.
- Old `/staff/app-download.html` bookmarks redirect to `/staff/login.html#guard-app-setup`. Closing that modal removes only the setup hash.
- The modal uses the existing app-dialog component, supports both themes and keyboard/touch controls, and disables the APK action on detected unsupported phones. The direct QR remains an Android APK link on every device.
- The current APK is v1.0.18 / Build 19. The location panel is removed. An app-wide tracker starts from successful Time In and uses an Android foreground location service for screen-off updates, automatic GPS recovery, and background session renewal. Android requests notification and background battery permissions once. Tracking stops at Time Out or scheduled duty end. The live map lists guards waiting for GPS and animates received locations. Physical screen-off testing is still required on the target phone.

## QR maintenance

Install test dependencies using `npm ci` in `web/tests`. When changing the published APK URL, update both the QR link and the modal download link in `web/staff/login.html`, then run:

```text
node web/tests/generate_guard_app_qr.cjs
node web/tests/guard_app_qr_test.js
```

The decoder test checks the actual PNG payload against the modal link and attachment headers. Browser tests also decode the rendered QR at its displayed size.

## Verification

- `guard_app_modal.spec.js`: modal triggers, fields preserved, keyboard controls, responsive themes, old links, and isolated browser download fixtures (not real APK files).
- `portal_smoke.spec.js`: supported/unsupported phone detection and existing login regressions.
- `live_guard_app_modal_smoke.cjs`: actual live modal/QR checks and complete APK download with SHA-256 comparison to the published source file. No login, installation, or database writes.

Deploy using the established full web release staging, including `web/downloads`. The older portal-only deployment helper excludes APKs and must not replace a release serving the download domain. Preserve the APK attachment MIME and Content-Disposition headers in `web/vercel.json`.
