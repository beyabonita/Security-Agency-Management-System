insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('incident-videos', 'incident-videos', false, 15728640, array['video/mp4', 'video/quicktime', 'video/webm'])
on conflict (id) do nothing;

create policy "guards upload own incident video" on storage.objects for insert to authenticated
  with check (bucket_id = 'incident-videos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "incident staff reads video" on storage.objects for select to authenticated
  using (bucket_id = 'incident-videos' and public.is_staff());
create policy "guards read own incident video" on storage.objects for select to authenticated
  using (bucket_id = 'incident-videos' and (storage.foldername(name))[1] = auth.uid()::text);
