-- Media cleanup is performed through the Storage API, never by deleting its SQL catalogue rows.
alter table public.incidents add column deletion_requested_at timestamptz;
create table public.incident_deletion_audit (
  incident_id uuid primary key,
  organization_id uuid not null references public.organizations(id),
  deleted_by uuid not null references public.profiles(id),
  deleted_at timestamptz not null default now()
);
alter table public.incident_deletion_audit enable row level security;
revoke all on public.incident_deletion_audit from public, anon, authenticated;
grant select on public.incident_deletion_audit to authenticated;
create policy "HR and IT read deletion audit" on public.incident_deletion_audit for select to authenticated
using (public.is_it_admin() or (public.is_admin() and organization_id = public.current_organization_id()));

-- Only the authenticated Edge Function's service client may call this two-phase operation.
-- The caller's active HR role and active organization are checked again at each phase.
create or replace function public.manage_incident_deletion(p_incident_id uuid, p_actor_id uuid, p_finish boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_org uuid; r public.incidents;
begin
  select p.organization_id into v_org from public.profiles p join public.organizations o on o.id = p.organization_id
    where p.id = p_actor_id and p.role = 'admin' and p.active and o.active;
  if v_org is null then raise exception 'Only active HR / Operations can delete emergency reports.' using errcode = '42501'; end if;
  select * into r from public.incidents where id = p_incident_id and organization_id = v_org for update;
  if not found then
    if exists (select 1 from public.incident_deletion_audit where incident_id = p_incident_id and organization_id = v_org) then
      return jsonb_build_object('deleted',true);
    end if;
    raise exception 'Incident not found or no longer accessible.' using errcode = 'P0002';
  end if;
  if r.video_path is not null then perform pg_advisory_xact_lock(hashtextextended(r.video_path,0)); end if;
  if p_finish then
    if r.deletion_requested_at is null then raise exception 'Start media cleanup before deleting the report.'; end if;
    if r.video_path is not null
      and exists (select 1 from storage.objects where bucket_id = 'incident-videos' and name = r.video_path)
      and not exists (select 1 from public.incidents where id <> r.id and video_path = r.video_path) then
      raise exception 'Video cleanup is incomplete. Retry deleting the report.';
    end if;
    insert into public.incident_deletion_audit(incident_id, organization_id, deleted_by)
      values(r.id, r.organization_id, p_actor_id);
    delete from public.user_notifications where entity_type = 'incident' and entity_id = r.id;
    delete from public.incidents where id = r.id;
    return jsonb_build_object('deleted',true);
  end if;
  update public.incidents set deletion_requested_at = coalesce(deletion_requested_at,now()) where id = r.id;
  return jsonb_build_object('deleted',false, 'video_path',r.video_path, 'user_id',r.user_id,
    'video_shared',exists(select 1 from public.incidents where id <> r.id and video_path = r.video_path));
end;
$$;
revoke all on function public.manage_incident_deletion(uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.manage_incident_deletion(uuid,uuid,boolean) to service_role;

create or replace function public.protect_incident_cleanup()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.deletion_requested_at is not null and new.status is distinct from old.status then
    raise exception 'This report is being deleted. Retry deletion instead of changing its status.';
  end if;
  if new.video_path is not null and (tg_op = 'INSERT' or new.video_path is distinct from old.video_path) then
    perform pg_advisory_xact_lock(hashtextextended(new.video_path,0));
    if exists (select 1 from public.incidents where video_path = new.video_path and deletion_requested_at is not null) then
      raise exception 'This video is being deleted. Capture new evidence for this report.';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.protect_incident_cleanup() from public, anon, authenticated;
create trigger protect_incident_cleanup before insert or update on public.incidents
for each row execute function public.protect_incident_cleanup();
notify pgrst, 'reload schema';
