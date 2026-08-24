-- Enum additions must be committed before they can be referenced.
alter type public.app_role add value if not exists 'it_admin';
alter type public.app_role add value if not exists 'operations_head';
