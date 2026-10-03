# 1,000-row data-volume fixture

Run `seed_1000.sql` in the **Supabase SQL Editor of a test database** as `postgres`. Edit `load_config.guard_ids` near the top to an array of existing active regular test-guard UUIDs from one active agency, for example `array['actual-uuid-here'::uuid]`. Use this read-only query to find them:

```sql
select id, username, first_name, last_name, organization_id
from public.profiles
where role = 'user' and active and employment_category = 'regular'
order by username;
```

Choose accounts created for testing. One guard produces 200 historical duty dates; ten guards produce 20 dates each. Dates end yesterday by default. Existing overlapping duties cause an atomic failure; use otherwise unused test guards or adjust the ending date. Run the whole script together. If the editor leaves a failed transaction open, run `ROLLBACK;` before retrying.

| Table | New rows |
|---|---:|
| Locations | 100 |
| Schedules | 200 |
| Attendance sessions | 200 |
| Incidents | 200 |
| Accomplishment reports | 100 |
| Notifications | 200 |
| **Total** | **1,000** |

This covers the main operational records. It reuses existing organizations and Auth-linked profiles. It does not invent account credentials, assignment history, approval requests, platform settings, or deletion audits. The script requires the schema represented by the repository migrations through September 5, 2026; it does not apply migrations.

Automatic notification triggers are disabled only inside this transaction and restored before commit, with table locks preventing concurrent writes. Validation and foreign-key triggers remain enabled. A rollback also restores trigger state. Exactly 200 clearly marked test notifications are inserted explicitly. The script creates no permanent helper tables and makes no updates to existing profiles, including their cached duty-day totals.

The seed uses direct privileged inserts to prepare data. It does not test application RPC validation or row-level authorization. The PNG incident placeholder is tiny, so this does not represent realistic image/video storage or bandwidth. Closed sessions include deterministic late arrivals and early departures. All 200 schedules are historical completed duties; 100 have accomplishment reports. Use matching historical date filters in the application to see them.

After seeding, check the returned table counts and exercise list pagination, search, date filters, attendance/DTR calculations and report generation using the test accounts. Measure response times in those flows. Supabase/API row limits can truncate results; verifying a visible page is not proof that all 1,000 rows were retrieved. A successful insert establishes only that the database accepted this fixture; it does not demonstrate concurrent-user capacity or a load-test pass.

Run `cleanup_1000.sql` to remove this exact complete batch. Cleanup refuses partial/unmarked batches and additional records referencing the fixtures. It clears only the synthetic schedules' completion flags after removing synthetic reports and attendance; database history-protection triggers remain enabled. It must be used only for this test fixture.

Validation performed: reviewed against the local migration schemas and triggers. These scripts have **not been executed against a database**; no performance result is claimed.
