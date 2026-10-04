# Guard app 1.0.20 (Build 21)

## Photo accomplishment reports

- Guards upload a finished JPG or PNG report from their phone (up to 10 MB).
- The original photo is preserved. Guards can preview and replace it before submission.
- A photo, duty summary, and detailed narrative are required; issues encountered remain optional.
- Reports can be submitted after Time In while duty is open, or after Time Out. Follow-up reports for the same duty preserve earlier submissions.
- Operations Head can view the submitted photo and open it at full size alongside written details and review controls.
- Photos are stored privately. Guards can access their own photos; authorized reviewers can access filed reports. Unrelated guards cannot access them.
- Retrying an interrupted submission with the same photo returns the original report instead of creating a duplicate.
- Historical written reports are retained. Older Guard app versions must update before submitting new accomplishment reports.
- Mobile notices now use the Super Admin role label, consistent with the web portals.

## Validation

- 18 rollback-isolated database checks passed, covering required fields, during-duty and completed-duty submissions, retries, photo ownership, reviewer access, and protection of filed attachments.
- 12 Flutter tests passed, including photo validation, replacement, required written details, and interrupted submission retries.
- Changed report code passed static analysis.
- The Operations Head viewer passed browser checks for full-size photo access and recovery after failed loading, using the supplied sample photo locally.

## Release components

- Android APK: version 1.0.20, build 21, same application ID and signing certificate as the previous release.
- Database migration: `20260920000000_accomplishment_photos.sql`.
- Web report viewer, app download links, and QR code.

Download: https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.20

Build, deployment, signature, live website, and APK download verification records are saved under `testing/release-1.0.20-*`.
