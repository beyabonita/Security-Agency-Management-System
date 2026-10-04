select
 exists(select 1 from storage.buckets where id='accomplishment-photos' and public=false and file_size_limit=10485760) as private_photo_storage_ready,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='accomplishment_reports' and column_name='photo_path') as photo_report_column_ready,
 has_function_privilege('authenticated','public.submit_accomplishment_report(uuid,text,text,text,text,text)','EXECUTE') as authenticated_submission_enabled,
 not has_function_privilege('anon','public.submit_accomplishment_report(uuid,text,text,text,text,text)','EXECUTE') as anonymous_submission_blocked;