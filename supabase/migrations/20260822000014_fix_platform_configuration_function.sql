-- Correct the audit-array initializer so schema lint remains clean.

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
