# Supabase operations

This directory contains forward-only migrations for a fresh Sentinel Link database. It does not import Firebase data.

Apply migrations and verify the linked project from the repository root:

```powershell
npx --yes supabase link --project-ref <project-ref>
npx --yes supabase db push
npx --yes supabase db lint --linked --level warning
```

`tests/database/*.sql` contains pgTAP regression contracts. With Docker available, run them against a disposable local database:

```powershell
npx --yes supabase start
npx --yes supabase test db supabase/tests/database
npx --yes supabase stop
```

The other `tests/*_schema_check.sql` files can be pasted into the linked project's SQL editor after a migration. They are read-only contract checks and must not be used as migrations.

## Schedule lifecycle

`20260904000000_fix_schedule_policy_and_safe_deletion.sql` breaks the circular
schedule/location RLS dependency using a caller-scoped helper in the non-exposed
`private` schema. Keep the personnel and location tenant checks on schedule writes.

Admin deletes unused schedules through `delete_unused_schedule(p_schedule_id)`.
Schedules with attendance, completed duty, accomplishment reports, or shift-change
requests are retained. A database trigger protects direct deletes too; do not
replace the attendance foreign key's `RESTRICT` action with `CASCADE`.

`tests/database/004_schedule_lifecycle.sql` tests real authenticated-role writes,
authorization boundaries, and history preservation. It uses transaction-local
fixtures and rolls back all test records and notifications. When Docker is not
available, its full TAP results can also be read using:

```powershell
npx --yes supabase db query --linked --file supabase/tests/database/004_schedule_lifecycle.sql
```

Check the returned TAP lines for `not ok`; the query command itself does not
return a failing exit code for failed assertions. The normal pgTAP test runner in
CI does enforce assertion failures.

## Duty-request letters and emergency cleanup

Guards submit Swap or Absence requests through `submit_duty_request`. A PDF, JPG,
or PNG letter (maximum 5 MB) is required and stored privately in
`request-letters`. New requests go directly to the Guard's Admin;
Inspectors cannot read the letter or decide the request. Admin must choose an
available replacement Guard when approving a swap. Approved absences retain the
cancelled schedule as an audit record and create no attendance.

Emergency report deletion runs through `admin-delete-incident`. It verifies the Admin's
active tenant role, removes the referenced private video through the Storage API,
then deletes the database photo/report and related alerts. A failed cleanup keeps
the report available for retry. Never delete `storage.objects` directly.

Deploy Edge Functions whenever their source changes:

```powershell
npx --yes supabase functions deploy admin-create-user
npx --yes supabase functions deploy admin-manage-user
npx --yes supabase functions deploy it-provision-client
npx --yes supabase functions deploy admin-delete-incident --no-verify-jwt
```

Validate function source before deploying:

```powershell
npx --yes deno fmt --check supabase/functions
npx --yes deno lint supabase/functions
npx --yes deno check supabase/functions/admin-create-user/index.ts supabase/functions/admin-manage-user/index.ts supabase/functions/it-provision-client/index.ts supabase/functions/admin-delete-incident/index.ts
npx --yes deno test --allow-env --allow-net supabase/functions/admin-delete-incident/handler_test.ts
```

The account APIs allow the production portal origins by default. Add an approved additional origin without changing source by setting the comma-separated `ALLOWED_WEB_ORIGINS` Edge Function secret.

Public Auth signup is disabled in `config.toml` because accounts are provisioned only through the authorized Edge Functions. For an existing hosted project, verify the equivalent Auth provider setting in the Supabase Dashboard. Do not push the entire local `config.toml` to production without reviewing local redirect URLs and network settings.

The service-role key is provided only inside Supabase Edge Functions. Do not add it to a `.env` file committed to the repository, Flutter client, or static web app.
