-- Private incident videos must follow the same organization boundary as the
-- incident record that references them.
drop policy if exists "guards upload own incident video" on storage.objects;
drop policy if exists "incident staff reads video" on storage.objects;
drop policy if exists "guards read own incident video" on storage.objects;

create policy "active personnel upload own incident video"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'incident-videos'
  and public.is_active_duty_personnel()
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "tenant incident staff reads video"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'incident-videos'
  and (
    public.is_it_admin()
    or (
      public.is_staff()
      and exists (
        select 1
        from public.incidents i
        where i.video_path = storage.objects.name
          and i.organization_id = public.current_organization_id()
      )
    )
  )
);

create policy "active personnel read own incident video"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'incident-videos'
  and public.is_active_duty_personnel()
  and (storage.foldername(name))[1] = auth.uid()::text
);
