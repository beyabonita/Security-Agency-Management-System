-- Migration: 20261116000001_contract_expiry_7day_reminder.sql
-- Description:
-- Adds automatic 7-day advance contract expiration reminder notifications for
-- both Security Guards (Mobile App notifications inbox & realtime alert) and
-- Operations Heads (Web Console notification center).

CREATE OR REPLACE FUNCTION public.check_expiring_guard_contracts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() AT TIME ZONE 'Asia/Manila')::date;
  v_guard record;
  v_admin record;
  v_days_left integer;
  v_when_text text;
  v_date_label text;
  v_guard_name text;
  v_count integer := 0;
BEGIN
  FOR v_guard IN
    SELECT
      p.id,
      p.organization_id,
      p.first_name,
      p.middle_initial,
      p.last_name,
      p.username,
      p.contract_end_date
    FROM public.profiles p
    WHERE p.role = 'user'
      AND p.active = true
      AND p.removed_at IS NULL
      AND p.contract_end_date IS NOT NULL
      AND (p.contract_end_date - v_today) BETWEEN 0 AND 7
  LOOP
    v_days_left := (v_guard.contract_end_date - v_today);
    v_when_text := CASE
      WHEN v_days_left = 0 THEN 'today'
      WHEN v_days_left = 1 THEN 'in 1 day'
      ELSE 'in ' || v_days_left::text || ' days'
    END;
    v_date_label := to_char(v_guard.contract_end_date, 'Mon DD, YYYY');
    v_guard_name := coalesce(
      nullif(trim(concat_ws(' ',
        v_guard.first_name,
        CASE WHEN nullif(trim(v_guard.middle_initial), '') IS NOT NULL THEN trim(v_guard.middle_initial) || '.' ELSE NULL END,
        v_guard.last_name
      )), ''),
      nullif(v_guard.username, ''),
      'Security Guard'
    );

    -- 1. Notify the Guard on the Mobile App (realtime user_notifications)
    PERFORM public.insert_user_notification(
      v_guard.id,
      v_guard.organization_id,
      'account',
      'high',
      CASE WHEN v_days_left = 0 THEN 'Contract Ends Today' ELSE 'Contract Expiring Soon (7-Day Reminder)' END,
      'Reminder: Your employment contract will end on ' || v_date_label || ' (' || v_when_text || '). Please coordinate with the Operations Head for contract renewal.',
      'personnel',
      'profile',
      v_guard.id,
      jsonb_build_object(
        'contract_end_date', v_guard.contract_end_date,
        'days_remaining', v_days_left
      ),
      false,
      null,
      'contract-expiry-7d:' || v_guard.id::text || ':' || v_guard.contract_end_date::text,
      now() + interval '30 days'
    );

    -- 2. Notify active Operations Heads in the same organization
    FOR v_admin IN
      SELECT a.id
      FROM public.profiles a
      WHERE a.organization_id = v_guard.organization_id
        AND a.role = 'admin'
        AND a.active = true
    LOOP
      PERFORM public.insert_user_notification(
        v_admin.id,
        v_guard.organization_id,
        'account',
        'high',
        'Guard Contract Expiring Soon',
        v_guard_name || '''s employment contract will end on ' || v_date_label || ' (' || v_when_text || '). Review in Personnel for renewal.',
        'personnel',
        'profile',
        v_guard.id,
        jsonb_build_object(
          'guard_id', v_guard.id,
          'guard_name', v_guard_name,
          'contract_end_date', v_guard.contract_end_date,
          'days_remaining', v_days_left
        ),
        false,
        v_guard.id,
        'contract-expiry-7d-admin:' || v_guard.id::text || ':' || v_guard.contract_end_date::text,
        now() + interval '30 days'
      );
    END LOOP;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.check_expiring_guard_contracts() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.check_expiring_guard_contracts() TO authenticated;

CREATE OR REPLACE FUNCTION public.trigger_check_expiring_guard_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF new.role = 'user' AND new.active = true AND new.contract_end_date IS NOT NULL THEN
    PERFORM public.check_expiring_guard_contracts();
  END IF;
  RETURN new;
END;
$$;

REVOKE ALL ON FUNCTION public.trigger_check_expiring_guard_contract() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS check_expiring_guard_contract_on_profile ON public.profiles;
CREATE TRIGGER check_expiring_guard_contract_on_profile
AFTER INSERT OR UPDATE OF contract_end_date, employment_category, active
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.trigger_check_expiring_guard_contract();

NOTIFY pgrst, 'reload schema';

