-- Migration: 20261105000001_contract_driven_site_shifts.sql
-- Description:
-- Adds contract-driven shift schedule configuration to deployment sites (public.locations).
-- When adding/editing a client site, operations heads can define the site's default shifting model
-- and hours (e.g. 2 shifts 12h, 3 shifts 8h, single daytime shift, or custom shift intervals).
-- The duty scheduling roster will automatically apply the site's contracted shifts upon selection,
-- eliminating repetitive manual shift setup selection.

ALTER TABLE public.locations
  ADD COLUMN IF NOT EXISTS shift_model text NOT NULL DEFAULT '2_shifts_12h',
  ADD COLUMN IF NOT EXISTS custom_shift_hours jsonb DEFAULT NULL;

COMMENT ON COLUMN public.locations.shift_model IS
  'Contract shifting model identifier: 2_shifts_12h, 2_shifts_12h_07, 3_shifts_8h, 1_shift_8h, or custom';

COMMENT ON COLUMN public.locations.custom_shift_hours IS
  'Array of custom shift objects specifying contract hours and names: [{"start_time": "06:00", "end_time": "18:00", "label": "Day Shift"}]';

NOTIFY pgrst, 'reload schema';
