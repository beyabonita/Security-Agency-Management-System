# Release 1.0.19 (build 20)

## Changes

- Deployment Site search suggests Philippine places and businesses while typing. City/province and place-type filters remain available. Removed Use My Location. Suggestions depend on available map data; the city filter helps distinguish branches.
- Schedule personnel filters and roster guard selectors support typing a name. A guard selected in one roster slot is excluded from other slots. Existing server checks still prevent duplicate assignments.
- Deployment Sites now includes View guards, showing personnel assigned to the establishment through their home post or ongoing/upcoming schedule. Scheduled guard shifts can also be filtered by site.
- Incident reports resolve the assigned deployment site when filing, including the full saved address. Older reports without a site label can resolve it from the guard's duty at the report time, falling back to their assigned home post. Removed the coordinates row.
- Replaced Response and review with Reviewer Note and removed the legacy Sentinel Link immediate-action text. Reviewer identity/history remains available.
- Reciprocal shift exchanges require the selected guard to approve or decline first. Only accepted exchanges reach the Operations Head for final approval. Guard consent alone does not change either schedule. Declined exchanges leave schedules unchanged.
- Operations Head can remove Guard and Inspector personnel from the active directory. Removal disables access and retains historical attendance, reports, and references.
- Account name fields capitalize words and reject numbers; the account service validates names as well. Account creation/edit password fields have Show/Hide controls.
- Live guard map cards use the deployment site's label and full saved address. Accurate addresses must exist in the site's saved record.
- Removed urgency labels from web and Guard app notifications. Notification delivery, acknowledgement, and routing continue to work.

## Installation

Install Guard app 1.0.19 (build 20) to receive and respond to swap invitations. Existing installations use the same application ID and signing certificate.

Download: https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.19

## Validation

- Database: 24 rollback-isolated checks covering consent permissions, notification routing, final approval, decline, unchanged schedules, incident site resolution, and access controls.
- Web: roster lifecycle checks (43), incident/request/personnel/notification checks (33), Philippine location search checks (6), and a removal confirmation check. The duplicate-selection case was also rerun successfully.
- Guard app: 24 distinct relevant Flutter tests, including target-guard approval and decline; analysis of changed Dart files passed.
- Account functions: 18 tests, including server name validation and removal permissions.
- Android release build completed, metadata and release mode verified, and signing certificate matched the prior downloadable app.

## Deployment components

- Database migrations: 20260919000000_site_details_and_personnel_removal and 20260919000001_guard_swap_consent.
- Account functions: admin-create-user and admin-manage-user.
- Static portals and the Guard APK are deployed together. Live verification records are stored under testing/release-1.0.19-*.

No test data was retained by the database validation, and no database reset was performed.
