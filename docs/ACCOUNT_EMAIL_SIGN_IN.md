# Email account sign-in

Accounts are provisioned with an existing email address (including Gmail) and a separate app password. This does not create a Gmail mailbox or use the person's Google password. Public registration, Google OAuth and outbound welcome/reset emails are outside this change.

Operations Heads create and edit Guard/Inspector emails in Personnel. IT Admins create and edit Operations Head/IT Admin emails in account management. The current IT Admin can use **Change my email**, with their current app password; this cannot change their own role or enabled status.

Existing accounts keep their IDs, attendance, DTR, reports and app passwords. Enter each person's real address through Edit. Do not replace old aliases with guessed addresses. Until migration, existing usernames can still sign in. After migration, that account signs in with its real email and existing app password. New accounts require a valid email; new synthetic aliases cannot be created.

Incident reports filed with a historical alias display the person's current email when available through the caller's authorized profile access. Saved report snapshots remain unchanged. Without an entered email, the UI says “Email not added.”

Prepared locally only. Release together with the pending migrations, including 20260914000003_account_email_identity.sql, updated admin-create-user/admin-manage-user functions, web files and guard app source. The email uniqueness index intentionally rejects case-insensitive collisions rather than silently choosing an account. This change does not send email messages or require Google OAuth credentials.
