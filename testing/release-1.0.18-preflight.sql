select (select count(*) from public.profiles) as profiles,
 (select count(*) from public.profiles where role::text='it_admin') as it_admins,
 (select count(*) from public.schedules) as schedules,
 (select count(*) from public.incidents) as incidents,
 (select count(*) from public.incidents where photo_data is null and video_path is null) as incidents_without_evidence,
 (select count(*) from (select lower(email) from public.profiles where email<>'' group by lower(email) having count(*)>1) d) as duplicate_email_groups;
