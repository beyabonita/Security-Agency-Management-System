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

Deploy Edge Functions whenever their source changes:

```powershell
npx --yes supabase functions deploy admin-create-user
npx --yes supabase functions deploy admin-manage-user
npx --yes supabase functions deploy it-provision-client
```

Validate function source before deploying:

```powershell
npx --yes deno fmt --check supabase/functions
npx --yes deno lint supabase/functions
npx --yes deno check supabase/functions/admin-create-user/index.ts supabase/functions/admin-manage-user/index.ts supabase/functions/it-provision-client/index.ts
```

The account APIs allow the production portal origins by default. Add an approved additional origin without changing source by setting the comma-separated `ALLOWED_WEB_ORIGINS` Edge Function secret.

Public Auth signup is disabled in `config.toml` because accounts are provisioned only through the authorized Edge Functions. For an existing hosted project, verify the equivalent Auth provider setting in the Supabase Dashboard. Do not push the entire local `config.toml` to production without reviewing local redirect URLs and network settings.

The service-role key is provided only inside Supabase Edge Functions. Do not add it to a `.env` file committed to the repository, Flutter client, or static web app.
