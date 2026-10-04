-- Migration: Add extended personnel profile attributes and license documents
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS personnel_id text,
ADD COLUMN IF NOT EXISTS middle_name text,
ADD COLUMN IF NOT EXISTS date_of_birth date,
ADD COLUMN IF NOT EXISTS gender text,
ADD COLUMN IF NOT EXISTS civil_status text,
ADD COLUMN IF NOT EXISTS complete_address text,
ADD COLUMN IF NOT EXISTS date_hired date,
ADD COLUMN IF NOT EXISTS contract_status text DEFAULT 'Active',
ADD COLUMN IF NOT EXISTS license_security_url text,
ADD COLUMN IF NOT EXISTS license_firearms_url text;

COMMENT ON COLUMN public.profiles.personnel_id IS 'Unique agency-assigned personnel identification code';
COMMENT ON COLUMN public.profiles.middle_name IS 'Full middle name of the personnel';
COMMENT ON COLUMN public.profiles.date_of_birth IS 'Date of birth of the personnel';
COMMENT ON COLUMN public.profiles.gender IS 'Gender identity (Male, Female, Other)';
COMMENT ON COLUMN public.profiles.civil_status IS 'Civil status (Single, Married, Widowed, Separated)';
COMMENT ON COLUMN public.profiles.complete_address IS 'Full residential address';
COMMENT ON COLUMN public.profiles.date_hired IS 'Date of joining / hiring at the security agency';
COMMENT ON COLUMN public.profiles.contract_status IS 'Employment / contract status (Active, Probationary, Completed, Terminated, Expired)';
COMMENT ON COLUMN public.profiles.license_security_url IS 'URL or Data URL for License to Exercise Security Profession (LESP)';
COMMENT ON COLUMN public.profiles.license_firearms_url IS 'URL or Data URL for License to Carry Firearms (LTCF)';
