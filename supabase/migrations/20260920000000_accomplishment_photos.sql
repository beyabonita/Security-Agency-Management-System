-- Photo reports can be filed after Time In, including during an open duty.
-- Retain historical text-only reports and allow a later handover report.
alter table public.accomplishment_reports
  add column photo_path text,
  add column photo_name text,
  drop constraint accomplishment_reports_schedule_id_key;
create unique index accomplishment_photo_path_unique on public.accomplishment_reports(photo_path) where photo_path is not null;
create index accomplishment_schedule_idx on public.accomplishment_reports(schedule_id);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('accomplishment-photos','accomplishment-photos',false,10485760,array['image/jpeg','image/png']);
create function private.can_view_accomplishment_photo(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.accomplishment_reports r where r.photo_path=p_path
    and private.can_view_personnel(r.guard_id,r.organization_id));
$$;
revoke all on function private.can_view_accomplishment_photo(text) from public,anon;
grant execute on function private.can_view_accomplishment_photo(text) to authenticated;
alter policy "inspector private media boundary" on storage.objects
using (public.current_role()<>'inspector'
  or (bucket_id='incident-videos' and (
    (public.is_active_duty_personnel() and (storage.foldername(name))[1]=(select auth.uid())::text)
    or private.can_view_incident_video(name)))
  or (bucket_id='accomplishment-photos' and private.can_view_accomplishment_photo(name)));
create policy "guards upload accomplishment photos" on storage.objects for insert to authenticated
with check (bucket_id='accomplishment-photos' and public.is_active_guard()
  and (storage.foldername(name))[1]=auth.uid()::text);
create policy "authorized accomplishment photo readers" on storage.objects for select to authenticated
using (bucket_id='accomplishment-photos' and (
  (public.is_active_guard() and (storage.foldername(name))[1]=auth.uid()::text)
  or private.can_view_accomplishment_photo(name)
));
create policy "guards discard unsubmitted accomplishment photos" on storage.objects for delete to authenticated
using (bucket_id='accomplishment-photos' and public.is_active_guard()
  and (storage.foldername(name))[1]=auth.uid()::text
  and not exists(select 1 from public.accomplishment_reports r where r.photo_path=storage.objects.name));
create or replace function public.submit_accomplishment_report(
  p_schedule_id uuid,p_summary text,p_detailed_narrative text,p_issues_encountered text default ''
) returns public.accomplishment_reports language plpgsql security definer set search_path='' as $$
begin
  raise exception 'Update the Guard app to attach a photo to your accomplishment report.';
end;
$$;
create function public.submit_accomplishment_report(
  p_schedule_id uuid,p_summary text,p_detailed_narrative text,p_issues_encountered text,
  p_photo_path text,p_photo_name text
) returns public.accomplishment_reports language plpgsql security definer set search_path='' as $$
declare
  v_org uuid := public.current_organization_id();
  v_report public.accomplishment_reports;
begin
  if not public.is_active_guard() or v_org is null then
    raise exception 'Only an active Guard can submit an accomplishment report.' using errcode='42501';
  end if;
  if char_length(btrim(coalesce(p_summary,''))) not between 1 and 1500 then
    raise exception 'Enter a duty summary of up to 1,500 characters.';
  end if;
  if char_length(btrim(coalesce(p_detailed_narrative,''))) not between 1 and 5000 then
    raise exception 'Enter a detailed narrative of up to 5,000 characters.';
  end if;
  if char_length(btrim(coalesce(p_issues_encountered,''))) > 1500 then
    raise exception 'Issues encountered cannot exceed 1,500 characters.';
  end if;
  if char_length(coalesce(p_photo_name,'')) not between 1 and 180 or p_photo_name ~ '[[:cntrl:]/\\]' then
    raise exception 'Choose a photo with a valid filename.';
  end if;
  if p_photo_path is null or p_photo_path !~ ('^'||auth.uid()::text||'/[a-f0-9]{32}\.(jpg|png)$') then
    raise exception 'Attach your JPG or PNG photo report.';
  end if;
  -- Serialize submission and cleanup on the storage object. A retry after an
  -- interrupted response returns the original report instead of duplicating it.
  perform 1 from storage.objects o where o.bucket_id='accomplishment-photos' and o.name=p_photo_path
    and (o.metadata->>'size')::bigint between 1 and 10485760
    and o.metadata->>'mimetype'=case when p_photo_path like '%.jpg' then 'image/jpeg' else 'image/png' end
    for update;
  if not found then raise exception 'Upload a JPG or PNG photo of up to 10 MB before submitting.'; end if;
  select * into v_report from public.accomplishment_reports where photo_path=p_photo_path;
  if found then
    if v_report.guard_id<>auth.uid() or v_report.organization_id<>v_org or v_report.schedule_id<>p_schedule_id
      or v_report.summary<>btrim(p_summary) or v_report.detailed_narrative<>btrim(p_detailed_narrative)
      or v_report.issues_encountered<>btrim(coalesce(p_issues_encountered,'')) then
      raise exception 'This photo is already filed with another report.';
    end if;
    return v_report;
  end if;
  perform 1 from public.schedules s where s.id=p_schedule_id and s.user_id=auth.uid()
    and s.organization_id=v_org and s.approval_status in ('approved','changed') for update;
  if not found then raise exception 'Choose one of your assigned duties.'; end if;
  if not exists(select 1 from public.attendance_sessions a where a.schedule_id=p_schedule_id
    and a.user_id=auth.uid() and a.organization_id=v_org and a.clock_in_at is not null
    and a.status in ('open','closed')) then
    raise exception 'Record Time In for this duty before submitting an accomplishment report.';
  end if;
  insert into public.accomplishment_reports(schedule_id,guard_id,organization_id,summary,detailed_narrative,
    issues_encountered,photo_path,photo_name,review_status)
  values(p_schedule_id,auth.uid(),v_org,btrim(p_summary),btrim(p_detailed_narrative),
    btrim(coalesce(p_issues_encountered,'')),p_photo_path,p_photo_name,'submitted') returning * into v_report;
  return v_report;
end;
$$;
revoke all on function public.submit_accomplishment_report(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.submit_accomplishment_report(uuid,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';