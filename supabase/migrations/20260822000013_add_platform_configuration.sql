-- Super Admin configuration is stored in one protected record. These settings
-- affect new deployment-site defaults and the optional portal-wide notice.

create table if not exists public.platform_settings (
  singleton boolean primary key default true check (singleton),
  support_email text not null default '',
  default_geofence_radius integer not null default 100 check (default_geofence_radius between 25 and 1000),
  portal_announcement text not null default '' check (char_length(portal_announcement) <= 240),
  portal_announcement_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.platform_settings_audit (
  id uuid primary key default gen_random_uuid(),
  changed_at timestamptz not null default now(),
  changed_by uuid references public.profiles(id) on delete set null,
  changed_fields text[] not null default '{}',
  settings jsonb not null
);

insert into public.platform_settings (singleton)
values (true)
on conflict (singleton) do nothing;

alter table public.platform_settings enable row level security;
alter table public.platform_settings_audit enable row level security;

create policy "it admin reads platform settings"
on public.platform_settings
for select
to authenticated
using (public.is_it_admin());

create policy "it admin reads platform settings audit"
on public.platform_settings_audit
for select
to authenticated
using (public.is_it_admin());

revoke insert, update, delete on public.platform_settings from authenticated;
revoke insert, update, delete on public.platform_settings_audit from authenticated;
grant select on public.platform_settings, public.platform_settings_audit to authenticated;

create or replace function public.update_platform_settings(
  p_support_email text,
  p_default_geofence_radius integer,
  p_portal_announcement text,
  p_portal_announcement_enabled boolean
)
returns public.platform_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.platform_settings;
  v_support_email text := lower(trim(coalesce(p_support_email, '')));
  v_announcement text := trim(coalesce(p_portal_announcement, ''));
  v_changed_fields text[] := array[]::text[];
begin
  if not public.is_it_admin() then
    raise exception 'Only IT Admin can change platform settings.';
  end if;
  if v_support_email <> ''
    and v_support_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid support email address.';
  end if;
  if p_default_geofence_radius not between 25 and 1000 then
    raise exception 'Default geofence radius must be between 25 and 1,000 meters.';
  end if;
  if char_length(v_announcement) > 240 then
    raise exception 'Portal announcement must be 240 characters or fewer.';
  end if;
  if p_portal_announcement_enabled and v_announcement = '' then
    raise exception 'Enter an announcement before publishing it.';
  end if;

  select * into v_settings
  from public.platform_settings
  where singleton
  for update;

  if not found then
    insert into public.platform_settings (singleton, support_email, default_geofence_radius, portal_announcement, portal_announcement_enabled, updated_by)
    values (true, v_support_email, p_default_geofence_radius, v_announcement, p_portal_announcement_enabled, auth.uid())
    returning * into v_settings;
    v_changed_fields := array['support_email', 'default_geofence_radius', 'portal_announcement', 'portal_announcement_enabled'];
  else
    if v_settings.support_email is distinct from v_support_email then v_changed_fields := array_append(v_changed_fields, 'support_email'); end if;
    if v_settings.default_geofence_radius is distinct from p_default_geofence_radius then v_changed_fields := array_append(v_changed_fields, 'default_geofence_radius'); end if;
    if v_settings.portal_announcement is distinct from v_announcement then v_changed_fields := array_append(v_changed_fields, 'portal_announcement'); end if;
    if v_settings.portal_announcement_enabled is distinct from p_portal_announcement_enabled then v_changed_fields := array_append(v_changed_fields, 'portal_announcement_enabled'); end if;

    update public.platform_settings
    set support_email = v_support_email,
        default_geofence_radius = p_default_geofence_radius,
        portal_announcement = v_announcement,
        portal_announcement_enabled = p_portal_announcement_enabled,
        updated_at = now(),
        updated_by = auth.uid()
    where singleton
    returning * into v_settings;
  end if;

  if cardinality(v_changed_fields) > 0 then
    insert into public.platform_settings_audit (changed_by, changed_fields, settings)
    values (
      auth.uid(),
      v_changed_fields,
      jsonb_build_object(
        'support_email', v_settings.support_email,
        'default_geofence_radius', v_settings.default_geofence_radius,
        'portal_announcement', v_settings.portal_announcement,
        'portal_announcement_enabled', v_settings.portal_announcement_enabled
      )
    );
  end if;

  return v_settings;
end;
$$;

create or replace function public.default_geofence_radius()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select default_geofence_radius from public.platform_settings where singleton),
    100
  )
$$;

create or replace function public.current_platform_announcement()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when portal_announcement_enabled then nullif(portal_announcement, '')
    else null
  end
  from public.platform_settings
  where singleton
$$;

grant execute on function public.update_platform_settings(text, integer, text, boolean) to authenticated;
grant execute on function public.default_geofence_radius() to authenticated;
grant execute on function public.current_platform_announcement() to anon, authenticated;
