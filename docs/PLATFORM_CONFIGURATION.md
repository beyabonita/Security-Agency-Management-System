# Platform configuration

Only an active IT Admin can save these settings in **System controls**.

- **Support email:** when configured, shows Contact support on Staff/IT login pages and Admin, Inspector, and IT web panels. It opens a dialog showing the address, Copy email, and Open email app. Opening an email app requires a configured device/browser mail handler; an active email address alone does not configure one. Clipboard failures leave the address selected for manual copying. This is a contact shortcut, not an in-app ticket or email-sending service. Clearing the setting hides it. Use an address intended to be public; the settings row and audit history remain private.
- **New-site geofence default:** pre-fills each newly opened Add Deployment Site form. It never changes an existing site's radius or attendance geofence. Admin can still enter the radius for an individual site.
- **Portal announcement:** publishing requires 3–240 characters. Saving updates the current page banner; other visible pages refresh within a minute or when returning to them. Disabling removes the banner. Publishing a changed notice also uses the existing notification workflow, including active Guard accounts. Previously sent inbox notices are not recalled when the banner is disabled.

Saving identical values succeeds without changing the stored timestamp, editor, audit history, or sending another notification. A failed audit-history refresh does not turn a successful configuration save into an error.

## Verification

- `supabase/tests/database/006_platform_configuration.sql`: 49 rollback assertions for permissions, validation, real saves/audit, public support reads, notifications, and no-op saves.
- `web/tests/platform_controls.spec.js`: mocked browser tests for settings submission and shared support/banner presentation.
- The same browser suite also checks the support dialog, clipboard-denied fallback, keyboard actions, and notice/theme layout on both login pages at desktop, tablet, and phone widths in both themes.
- `web/tests/geofence_default.spec.js`: mocked browser tests for delayed defaults, retry behavior, manual input, and preserving existing sites.
- `web/tests/live_platform_controls_smoke.cjs`: verifies an unchanged save using the real UI/API and checks that values, saved timestamp, and audit count are preserved. Changed payloads are intercepted before transmission.

The broader `backend_hardening_schema_check.sql` also reports an existing per-row `auth.uid()` policy performance check outside these configuration changes. No row-level policies were changed as part of this fix.
