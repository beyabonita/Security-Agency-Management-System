-- Auth remains the source of sign-in identities. Prevent profile email collisions,
-- including concurrent account updates. Keep legacy aliases until explicitly migrated.
create unique index if not exists profiles_email_case_insensitive_key
  on public.profiles (lower(email)) where email <> '';
notify pgrst, 'reload schema';
