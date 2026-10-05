-- Migration: 20261005000003_assign_custom_shift_roster.sql
-- Description:
-- 1. Archive auto-generated shifting setup templates created by one-off time edits.
-- 2. Provide assign_custom_shift_roster RPC so one-off custom duty hours can be assigned
--    directly to guards without creating permanent shifting setup templates.

-- Archive auto-generated shifting setup templates
UPDATE public.shift_roster_setups
SET archived_at = coalesce(archived_at, now())
WHERE name ~* '^\d+\s*Shifts\s*\(\d{1,2}(:\d{2})?\s*(AM|PM)';

-- Create function to assign custom shift roster without saving templates
CREATE OR REPLACE FUNCTION public.assign_custom_shift_roster(
  p_location_id uuid,
  p_duty_date date,
  p_guard_ids uuid[],
  p_shifts jsonb
)
RETURNS SETOF public.schedules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  i integer;
  v_key bigint;
  shift_end timestamptz;
  created public.schedules;
  remaining integer[] := '{}';
  selected_guards uuid[] := '{}';
  s text;
  e text;
BEGIN
  IF NOT coalesce(public.is_admin(), false) OR NOT coalesce(public.current_organization_is_active(), false) THEN
    RAISE EXCEPTION 'Only an active Operations Head can assign a shift roster.' USING errcode = '42501';
  END IF;
  IF p_duty_date IS NULL OR NOT isfinite(p_duty_date) OR p_duty_date < (now() AT TIME ZONE 'Asia/Manila')::date THEN
    RAISE EXCEPTION 'Choose today or a future schedule date.';
  END IF;
  IF p_shifts IS NULL OR jsonb_typeof(p_shifts) IS DISTINCT FROM 'array' OR jsonb_array_length(p_shifts) NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Provide between 1 and 4 shifts.';
  END IF;
  IF cardinality(p_guard_ids) IS DISTINCT FROM jsonb_array_length(p_shifts)
    OR array_ndims(p_guard_ids) IS DISTINCT FROM 1 OR array_lower(p_guard_ids, 1) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'Choose a different Guard for each remaining shift.';
  END IF;
  FOR i IN 1..jsonb_array_length(p_shifts) LOOP
    s := p_shifts->(i-1)->>'start_time';
    e := p_shifts->(i-1)->>'end_time';
    shift_end := ((p_duty_date + CASE WHEN e::time < s::time THEN 1 ELSE 0 END) + e::time) AT TIME ZONE 'Asia/Manila';
    IF shift_end <= now() THEN CONTINUE; END IF;
    remaining := array_append(remaining, i);
    selected_guards := array_append(selected_guards, p_guard_ids[i]);
  END LOOP;
  IF cardinality(remaining) = 0 THEN
    RAISE EXCEPTION 'No ongoing or upcoming shifts remain on this date.';
  END IF;
  IF (SELECT count(DISTINCT g) FROM unnest(selected_guards) g) <> cardinality(remaining) THEN
    RAISE EXCEPTION 'Choose a different Guard for each remaining shift.';
  END IF;
  FOR v_key IN SELECT DISTINCT pg_catalog.hashtextextended(public.current_organization_id()::text || ':' || g::text, 0)
    FROM unnest(selected_guards) g ORDER BY 1 LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(v_key);
  END LOOP;
  IF EXISTS(
    SELECT 1 FROM unnest(selected_guards) g
    WHERE NOT EXISTS(
      SELECT 1 FROM public.profiles p
      WHERE p.id = g AND p.organization_id = public.current_organization_id() AND p.active AND p.role = 'user'
    )
  ) THEN
    RAISE EXCEPTION 'All assigned Guards must be active in your agency.';
  END IF;
  FOREACH i IN ARRAY remaining LOOP
    FOR created IN SELECT * FROM public.create_dtr_schedule(
      p_guard_ids[i],
      p_location_id,
      p_duty_date,
      jsonb_build_array(
        jsonb_build_object(
          'period', 'auto',
          'start_time', p_shifts->(i-1)->>'start_time',
          'end_time', p_shifts->(i-1)->>'end_time',
          'next_day', false
        )
      )
    ) LOOP
      RETURN NEXT created;
    END LOOP;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_custom_shift_roster(uuid, date, uuid[], jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.assign_custom_shift_roster(uuid, date, uuid[], jsonb) TO authenticated;
NOTIFY pgrst, 'reload schema';
