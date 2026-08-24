-- Cache auth.uid() once per statement and keep one permissive SELECT policy per
-- table/role. This preserves the existing access model while avoiding repeated
-- policy evaluation for every scanned row.

drop policy if exists "organization members read own organization" on public.organizations;
drop policy if exists "it admin views beneficiary configuration" on public.organizations;
create policy "organization visibility"
on public.organizations
for select to authenticated
using (
  public.is_it_admin()
  or id = public.current_organization_id()
);

drop policy if exists "tenant profile visibility" on public.profiles;
create policy "tenant profile visibility"
on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

drop policy if exists "tenant location visibility" on public.locations;
create policy "tenant location visibility"
on public.locations
for select to authenticated
using (
  public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and (
      public.is_staff()
      or exists (
        select 1
        from public.schedules schedule
        where schedule.location_id = locations.id
          and schedule.user_id = (select auth.uid())
      )
    )
  )
);

drop policy if exists "operations manages tenant locations" on public.locations;
drop policy if exists "operations inserts tenant locations" on public.locations;
drop policy if exists "operations deletes tenant locations" on public.locations;
create policy "operations manages tenant locations"
on public.locations
for update to authenticated
using (
  public.is_admin()
  and organization_id = public.current_organization_id()
)
with check (
  public.is_admin()
  and organization_id = public.current_organization_id()
);
create policy "operations inserts tenant locations"
on public.locations
for insert to authenticated
with check (
  public.is_admin()
  and organization_id = public.current_organization_id()
);
create policy "operations deletes tenant locations"
on public.locations
for delete to authenticated
using (
  public.is_admin()
  and organization_id = public.current_organization_id()
);

drop policy if exists "tenant schedule visibility" on public.schedules;
create policy "tenant schedule visibility"
on public.schedules
for select to authenticated
using (
  public.is_it_admin()
  or user_id = (select auth.uid())
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

drop policy if exists "operations manages tenant schedules" on public.schedules;
drop policy if exists "operations inserts tenant schedules" on public.schedules;
drop policy if exists "operations deletes tenant schedules" on public.schedules;
create policy "operations manages tenant schedules"
on public.schedules
for update to authenticated
using (
  public.is_admin()
  and organization_id = public.current_organization_id()
)
with check (
  public.is_admin()
  and organization_id = public.current_organization_id()
  and exists (
    select 1
    from public.profiles personnel
    where personnel.id = schedules.user_id
      and personnel.organization_id = schedules.organization_id
      and personnel.role in ('user', 'inspector')
  )
  and (
    schedules.location_id is null
    or exists (
      select 1
      from public.locations post
      where post.id = schedules.location_id
        and post.organization_id = schedules.organization_id
    )
  )
);
create policy "operations inserts tenant schedules"
on public.schedules
for insert to authenticated
with check (
  public.is_admin()
  and organization_id = public.current_organization_id()
  and exists (
    select 1
    from public.profiles personnel
    where personnel.id = schedules.user_id
      and personnel.organization_id = schedules.organization_id
      and personnel.role in ('user', 'inspector')
  )
  and (
    schedules.location_id is null
    or exists (
      select 1
      from public.locations post
      where post.id = schedules.location_id
        and post.organization_id = schedules.organization_id
    )
  )
);
create policy "operations deletes tenant schedules"
on public.schedules
for delete to authenticated
using (
  public.is_admin()
  and organization_id = public.current_organization_id()
);

drop policy if exists "tenant attendance visibility" on public.attendance_punches;
create policy "tenant attendance visibility"
on public.attendance_punches
for select to authenticated
using (
  public.is_it_admin()
  or user_id = (select auth.uid())
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

drop policy if exists "tenant incident visibility" on public.incidents;
create policy "tenant incident visibility"
on public.incidents
for select to authenticated
using (
  public.is_it_admin()
  or user_id = (select auth.uid())
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

drop policy if exists "tenant assignment history visibility" on public.guard_assignment_history;
create policy "tenant assignment history visibility"
on public.guard_assignment_history
for select to authenticated
using (
  guard_id = (select auth.uid())
  or public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

drop policy if exists "tenant swap request visibility" on public.shift_swap_requests;
create policy "tenant swap request visibility"
on public.shift_swap_requests
for select to authenticated
using (
  requester_id = (select auth.uid())
  or inspector_id = (select auth.uid())
  or public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and public.is_operations_staff()
  )
);

drop policy if exists "tenant accomplishment visibility" on public.accomplishment_reports;
create policy "tenant accomplishment visibility"
on public.accomplishment_reports
for select to authenticated
using (
  guard_id = (select auth.uid())
  or public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

drop policy if exists "tenant attendance session visibility" on public.attendance_sessions;
create policy "tenant attendance session visibility"
on public.attendance_sessions
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.is_it_admin()
  or (
    organization_id = public.current_organization_id()
    and public.is_staff()
  )
);

-- Storage reads are the union of own-video and tenant-staff access. Keeping the
-- union in one SELECT policy avoids evaluating two permissive policies.
drop policy if exists "active personnel upload own incident video" on storage.objects;
create policy "active personnel upload own incident video"
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'incident-videos'
  and public.is_active_duty_personnel()
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "tenant incident staff reads video" on storage.objects;
drop policy if exists "active personnel read own incident video" on storage.objects;
create policy "tenant incident staff reads video"
on storage.objects
for select to authenticated
using (
  bucket_id = 'incident-videos'
  and (
    (
      public.is_active_duty_personnel()
      and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    or public.is_it_admin()
    or (
      public.is_staff()
      and exists (
        select 1
        from public.incidents incident
        where incident.video_path = storage.objects.name
          and incident.organization_id = public.current_organization_id()
      )
    )
  )
);

drop policy if exists "active personnel remove own unfiled incident video" on storage.objects;
create policy "active personnel remove own unfiled incident video"
on storage.objects
for delete to authenticated
using (
  bucket_id = 'incident-videos'
  and public.is_active_duty_personnel()
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and not exists (
    select 1
    from public.incidents incident
    where incident.video_path = storage.objects.name
  )
);
