const fs = require('node:fs');
const migration = fs.readFileSync('supabase/migrations/20260908000000_attendance_shift_rollover.sql', 'utf8');
fs.writeFileSync('testing/apply-attendance-rollover.sql', `begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $$ begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260908000000') then
    raise exception 'Attendance rollover migration is already applied.';
  end if;
end $$;
${migration}
insert into supabase_migrations.schema_migrations(version,name,statements)
values ('20260908000000','attendance_shift_rollover',array[$migration$${migration}$migration$]);
notify pgrst, 'reload schema';
commit;
select version, name from supabase_migrations.schema_migrations where version='20260908000000';
`);
