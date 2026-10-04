begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
alter table public.profiles add column if not exists removed_at timestamptz;

create or replace function private.guard_deployment_label(p_guard uuid,p_org uuid,p_at timestamptz)
returns text language sql stable security definer set search_path='' as $$
  select coalesce(
    (select concat_ws(' · ',coalesce(nullif(l.label,''),nullif(s.location_label,'')),nullif(l.address,''))
     from public.schedules s left join public.locations l on l.id=s.location_id and l.organization_id=p_org
     where s.user_id=p_guard and s.organization_id=p_org and s.approval_status in ('approved','changed')
       and (p_at between s.start_at and s.end_at or exists(select 1 from public.attendance_sessions a where a.schedule_id=s.id and a.clock_in_at<=p_at and coalesce(a.clock_out_at,now())>=p_at))
     order by s.start_at desc limit 1),
    (select concat_ws(' · ',l.label,nullif(l.address,'')) from public.profiles p join public.locations l on l.id=p.assigned_location_id and l.organization_id=p_org where p.id=p_guard and p.organization_id=p_org)
  );
$$;
revoke all on function private.guard_deployment_label(uuid,uuid,timestamptz) from public,anon,authenticated;

create or replace function private.attach_incident_deployment_site()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.location_label:=coalesce(private.guard_deployment_label(new.user_id,new.organization_id,coalesce(new.captured_at,new.created_at,now())),nullif(trim(new.location_label),''));
  return new;
end; $$;
revoke all on function private.attach_incident_deployment_site() from public,anon,authenticated;
create trigger attach_incident_deployment_site before insert on public.incidents for each row execute function private.attach_incident_deployment_site();

create or replace function public.incident_deployment_site(p_incident_id uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare i public.incidents;
begin
  select * into i from public.incidents where id=p_incident_id;
  if not found or not private.can_view_personnel(i.user_id,i.organization_id) then
    raise exception 'This incident is not available to you.' using errcode='42501';
  end if;
  return coalesce(nullif(i.location_label,''),private.guard_deployment_label(i.user_id,i.organization_id,coalesce(i.captured_at,i.created_at)),'No assigned deployment site');
end; $$;
revoke all on function public.incident_deployment_site(uuid) from public,anon;
grant execute on function public.incident_deployment_site(uuid) to authenticated;

create or replace function public.live_guard_map_snapshot()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('server_now',now(),'locations',coalesce((
    select jsonb_agg(to_jsonb(g)||jsonb_build_object('location_label',concat_ws(' · ',coalesce(nullif(l.label,''),g.location_label),nullif(l.address,''))))
    from public.list_live_guard_locations() g
    join public.attendance_sessions a on a.id=g.session_id
    left join public.schedules s on s.id=a.schedule_id
    left join public.locations l on l.id=s.location_id and l.organization_id=s.organization_id
  ),'[]'::jsonb));
$$;
revoke all on function public.live_guard_map_snapshot() from public,anon;
grant execute on function public.live_guard_map_snapshot() to authenticated;
notify pgrst,'reload schema';

alter table public.shift_swap_requests
  add column guard_response text check(guard_response in ('pending','approved','declined')),
  add column guard_responded_at timestamptz;

drop policy if exists "tenant swap request visibility" on public.shift_swap_requests;
create policy "tenant swap request visibility" on public.shift_swap_requests for select to authenticated
using (public.is_it_admin() or (organization_id=public.current_organization_id() and public.current_organization_is_active()
  and (requester_id=(select auth.uid()) or (target_guard_id=(select auth.uid()) and public.is_active_guard()) or public.is_admin())));

create or replace function public.submit_duty_exchange(p_schedule_id uuid,p_target_schedule_id uuid,p_reason text,p_letter_path text,p_letter_name text)
returns public.shift_swap_requests language plpgsql security definer set search_path='' as $$
declare r public.shift_swap_requests; a public.schedules; b public.schedules;
  v_org uuid:=public.current_organization_id(); v_source_name text; v_target_name text;
begin
  if not coalesce(public.is_active_guard(),false) or v_org is null then raise exception 'Only an active Guard can submit a swap.' using errcode='42501'; end if;
  select * into r from public.shift_swap_requests where letter_path=p_letter_path and requester_id=auth.uid() and organization_id=v_org;
  if found then
    if r.requested_schedule_id is distinct from p_schedule_id or r.target_schedule_id is distinct from p_target_schedule_id or r.reason is distinct from trim(p_reason) then raise exception 'This letter is already filed with another request.'; end if;
    return r;
  end if;
  if char_length(trim(coalesce(p_reason,''))) not between 5 and 1500 then raise exception 'Enter a reason between 5 and 1500 characters.'; end if;
  if char_length(trim(coalesce(p_letter_name,''))) not between 1 and 180 or p_letter_name ~ '[[:cntrl:]/\\]' then raise exception 'Choose a valid letter filename.'; end if;
  if p_letter_path is null or p_letter_path !~ ('^'||auth.uid()::text||'/[A-Za-z0-9-]+\.(pdf|jpg|png)$') or not exists(
    select 1 from storage.objects o where o.bucket_id='request-letters' and o.name=p_letter_path and (o.metadata->>'size')::bigint between 1 and 5242880
      and o.metadata->>'mimetype'=case when p_letter_path like '%.pdf' then 'application/pdf' when p_letter_path like '%.jpg' then 'image/jpeg' else 'image/png' end
  ) then raise exception 'Attach an owned PDF, JPG or PNG letter (up to 5 MB).'; end if;
  perform s.id from public.schedules s where s.organization_id=v_org and s.id in(p_schedule_id,p_target_schedule_id) order by s.id for update;
  select * into a from public.schedules where id=p_schedule_id and organization_id=v_org and user_id=auth.uid();
  if not found then raise exception 'Choose one of your own duty periods.' using errcode='42501'; end if;
  if not private.duty_exchange_eligible(a.id,p_target_schedule_id) then raise exception 'These duties are no longer available for exchange. Refresh and choose another duty.'; end if;
  select * into b from public.schedules where id=p_target_schedule_id;
  select coalesce(nullif(trim(concat_ws(' ',first_name,middle_initial,last_name)),''),username,'Guard') into v_source_name from public.profiles where id=a.user_id;
  select coalesce(nullif(trim(concat_ws(' ',first_name,middle_initial,last_name)),''),username,'Guard') into v_target_name from public.profiles where id=b.user_id;
  insert into public.shift_swap_requests(requester_id,requested_schedule_id,target_schedule_id,target_guard_id,reason,organization_id,request_type,letter_path,letter_name,status,guard_response,exchange_snapshot)
  values(auth.uid(),a.id,b.id,b.user_id,trim(p_reason),v_org,'swap',p_letter_path,trim(p_letter_name),'pending_admin','pending',
    jsonb_build_object('offered',private.duty_exchange_snapshot(a.id),'requested',private.duty_exchange_snapshot(b.id),'requester_name',v_source_name,'target_name',v_target_name)) returning * into r;
  return r;
end; $$;

create function public.respond_to_duty_swap(p_request_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
declare r public.shift_swap_requests;
begin
  if not coalesce(public.is_active_guard(),false) or p_approve is null then raise exception 'Only an active Guard can respond.' using errcode='42501'; end if;
  select * into r from public.shift_swap_requests where id=p_request_id and organization_id=public.current_organization_id()
    and target_guard_id=auth.uid() and target_schedule_id is not null for update;
  if not found then raise exception 'This swap request is not addressed to you.' using errcode='42501'; end if;
  if r.status<>'pending_admin' or r.guard_response is distinct from 'pending' then raise exception 'This request has already been answered.'; end if;
  if p_approve then
    perform s.id from public.schedules s where s.id in(r.requested_schedule_id,r.target_schedule_id) order by s.id for update;
    if private.duty_exchange_snapshot(r.requested_schedule_id) is distinct from r.exchange_snapshot->'offered'
      or private.duty_exchange_snapshot(r.target_schedule_id) is distinct from r.exchange_snapshot->'requested'
      or not private.duty_exchange_eligible(r.requested_schedule_id,r.target_schedule_id,r.id) then
      raise exception 'A duty has changed or is no longer available. Decline this request and ask for a new one.';
    end if;
  end if;
  update public.shift_swap_requests set guard_response=case when p_approve then 'approved' else 'declined' end,
    guard_responded_at=now(),status=case when p_approve then 'pending_admin' else 'rejected' end,updated_at=now() where id=r.id;
end; $$;
revoke all on function public.respond_to_duty_swap(uuid,boolean) from public,anon;
grant execute on function public.respond_to_duty_swap(uuid,boolean) to authenticated;

alter function public.decide_duty_request(uuid,boolean,text,uuid) rename to decide_consented_duty_request;
alter function public.decide_consented_duty_request(uuid,boolean,text,uuid) set schema private;
revoke all on function private.decide_consented_duty_request(uuid,boolean,text,uuid) from public,anon,authenticated;
create function public.decide_duty_request(p_request_id uuid,p_approve boolean,p_note text default '',p_replacement_guard_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare r public.shift_swap_requests;
begin
  if not coalesce(public.is_admin(),false) then raise exception 'Only Operations Head can approve duty changes.' using errcode='42501'; end if;
  select * into r from public.shift_swap_requests where id=p_request_id and organization_id=public.current_organization_id() for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.target_schedule_id is not null and r.guard_response is distinct from 'approved' then raise exception 'The selected Guard must approve this swap first.'; end if;
  perform private.decide_consented_duty_request(p_request_id,p_approve,p_note,p_replacement_guard_id);
end; $$;
revoke all on function public.decide_duty_request(uuid,boolean,text,uuid) from public,anon;
grant execute on function public.decide_duty_request(uuid,boolean,text,uuid) to authenticated;
create or replace function public.notify_shift_request_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient record; v_title text := case when new.request_type = 'absence' then 'Absence request' else 'Swap request' end;
begin
  if new.target_schedule_id is not null and new.guard_response='pending' then
    if tg_op='INSERT' or old.guard_response is distinct from new.guard_response then
      perform public.insert_user_notification(new.target_guard_id,new.organization_id,'shift_request','normal',
        'Shift swap request for your approval',coalesce(new.exchange_snapshot->>'requester_name','A Guard')||' wants to exchange duties with you. Approve or decline in Letter requests.',
        'shift_request','shift_swap_request',new.id,jsonb_build_object('status','pending_guard'),false,new.requester_id,
        'shift-request:'||new.id::text||':guard-consent',now()+interval '90 days');
      perform public.insert_user_notification(new.requester_id,new.organization_id,'shift_request','normal',
        'Awaiting the selected Guard','Your swap request must be accepted by the selected Guard before Operations Head review.',
        'shift_request','shift_swap_request',new.id,jsonb_build_object('status','pending_guard'),false,new.requester_id,
        'shift-request:'||new.id::text||':guard-waiting',now()+interval '90 days');
    end if;
    return new;
  end if;
  if new.guard_response='declined' and old.guard_response is distinct from new.guard_response then
    perform public.insert_user_notification(new.requester_id,new.organization_id,'shift_request','normal',
      'Shift swap declined',coalesce(new.exchange_snapshot->>'target_name','The selected Guard')||' declined the swap. Your duties remain unchanged.',
      'shift_request','shift_swap_request',new.id,jsonb_build_object('status','rejected'),false,new.target_guard_id,
      'shift-request:'||new.id::text||':guard-declined',now()+interval '90 days');
    return new;
  end if;
  if new.status = 'pending_admin' and (tg_op = 'INSERT' or old.status is distinct from new.status or old.guard_response is distinct from new.guard_response) then
    for v_recipient in select id from public.profiles where active and role = 'admin' and organization_id = new.organization_id loop
      perform public.insert_user_notification(v_recipient.id, new.organization_id, 'shift_request', 'high',
        v_title || ' awaiting approval', 'Review the Guard''s request and attached letter.',
        'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status,'request_type',new.request_type),
        false, new.requester_id, 'shift-request:' || new.id::text || ':admin', now() + interval '90 days');
    end loop;
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'normal',
      v_title || ' submitted', 'Your request was sent directly to Operational Head for approval.',
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status), false, new.requester_id,
      'shift-request:' || new.id::text || ':direct-submitted', now() + interval '90 days');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('approved','rejected','cancelled') then
    perform public.insert_user_notification(new.requester_id, new.organization_id, 'shift_request', 'high',
      v_title || ' ' || new.status,
      left('Operational Head ' || new.status || ' your request.' || case when nullif(new.admin_note,'') is null then '' else ' ' || new.admin_note end, 1000),
      'shift_request', 'shift_swap_request', new.id, jsonb_build_object('status',new.status), false, new.admin_decision_by,
      'shift-request:' || new.id::text || ':decision:' || new.status, now() + interval '180 days');
    if new.status = 'approved' and new.target_guard_id is not null and new.target_guard_id <> new.requester_id then
      perform public.insert_user_notification(new.target_guard_id, new.organization_id, 'schedule', 'high',
        'Duty assigned through an approved swap', 'Operational Head assigned you a duty. Check your schedule.',
        'schedule', 'shift_swap_request', new.id, jsonb_build_object('schedule_id',coalesce(new.replacement_schedule_id,new.requested_schedule_id)), false,
        new.admin_decision_by, 'shift-request:' || new.id::text || ':target-approved', now() + interval '180 days');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists notify_shift_request_event on public.shift_swap_requests;
create trigger notify_shift_request_event after insert or update of status,guard_response on public.shift_swap_requests
for each row execute function public.notify_shift_request_event();
-- Existing unanswered exchanges must also obtain the selected Guard's consent.
update public.shift_swap_requests set guard_response='pending'
where target_schedule_id is not null and status in ('pending_admin','pending_inspector') and guard_response is null;
notify pgrst,'reload schema';

-- Rollback-only behavioral tests. No real Guard's duties or uploaded files are changed.

create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
create temp table exchange_fixture(key text primary key,id uuid not null default gen_random_uuid());
insert into exchange_fixture(key) values ('admin'),('guard'),('peer'),('other'),('inspector'),('site'),('site2'),
 ('offered'),('target'),('conflict'),('request'),('ended'),('draft'),('absent'),('started'),('foreign_org');
insert into exchange_fixture(key,id) values ('org',public.beneficiary_organization_id());
create function pg_temp.f(k text) returns uuid language sql stable as $$select id from pg_temp.exchange_fixture where key=k$$;
insert into auth.users(id,email,raw_user_meta_data)
 select id,'exchange-test-'||id::text||'@example.invalid','{}'::jsonb
 from exchange_fixture where key in ('admin','guard','peer','other','inspector');
update public.profiles p set role=case f.key when 'admin' then 'admin'::public.app_role
 when 'inspector' then 'inspector'::public.app_role else 'user'::public.app_role end,
 active=true,organization_id=pg_temp.f('org'),first_name='Exchange',last_name=f.key,
 employment_category=case when f.key='peer' then 'contract' else 'regular' end,
 contract_start_date=case when f.key='peer' then date '2000-01-01' end,
 contract_end_date=case when f.key='peer' then date '2099-12-31' end
 from exchange_fixture f where p.id=f.id;
insert into public.locations(id,organization_id,label,latitude,longitude,radius_meters)
 values(pg_temp.f('site'),pg_temp.f('org'),'Exchange Site A',10.67,122.95,100),
 (pg_temp.f('site2'),pg_temp.f('org'),'Exchange Site B',10.68,122.96,100);
-- Same-time different-post exchange exercises intermediate-overlap handling.
insert into public.schedules(id,organization_id,user_id,location_id,location_label,start_at,end_at,duty_date,dtr_period)
 values(pg_temp.f('offered'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'Exchange Site A','2098-01-01 08:00+08','2098-01-01 12:00+08','2098-01-01','morning'),
 (pg_temp.f('target'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B','2098-01-01 08:00+08','2098-01-01 12:00+08','2098-01-01','morning'),
 (pg_temp.f('absent'),pg_temp.f('org'),pg_temp.f('guard'),pg_temp.f('site'),'Exchange Site A','2098-01-02 08:00+08','2098-01-02 12:00+08','2098-01-02','morning'),
 (pg_temp.f('draft'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B','2098-01-03 08:00+08','2098-01-03 12:00+08','2098-01-03','morning'),
 (pg_temp.f('started'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B','2098-01-04 08:00+08','2098-01-04 12:00+08','2098-01-04','morning'),
 (pg_temp.f('ended'),pg_temp.f('org'),pg_temp.f('peer'),pg_temp.f('site2'),'Exchange Site B',now()-interval '6 hours',now()-interval '2 hours',current_date,'morning');
update public.schedules set approval_status='draft' where id=pg_temp.f('draft');
insert into public.attendance_sessions(organization_id,schedule_id,user_id,location_id,duty_date,scheduled_start_at,scheduled_end_at,clock_in_at,clock_in_latitude,clock_in_longitude)
 select organization_id,id,user_id,location_id,duty_date,start_at,end_at,start_at,10.68,122.96 from public.schedules where id=pg_temp.f('started');
insert into storage.objects(bucket_id,name,metadata)
 select 'request-letters',pg_temp.f('guard')||'/'||n||'.pdf','{"mimetype":"application/pdf","size":30}'::jsonb
 from unnest(array['swap','absence','again','stale','started','reject']) n;
insert into storage.objects(bucket_id,name,metadata) values
 ('request-letters',pg_temp.f('peer')||'/absence.pdf','{"mimetype":"application/pdf","size":30}');
create temp table exchange_results(n integer generated always as identity,result text);
insert into exchange_results(result) select no_plan();
grant all on all tables in schema pg_temp to authenticated;
grant all on all sequences in schema pg_temp to authenticated;
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;

insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('offered'),pg_temp.f('target'),'Please exchange',pg_temp.f('guard')||'/swap.pdf','Letter.pdf')$$,'Guard submits exchange');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/swap.pdf') where key='request';
insert into exchange_results(result) select is((select guard_response from public.shift_swap_requests where id=pg_temp.f('request')),'pending','Swap initially awaits Guard consent');
insert into exchange_results(result) select throws_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),true)$$,'42501',null,'Requester cannot approve own swap');
reset role;
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id=pg_temp.f('admin')),0::bigint,'Operations Head is not notified before consent');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'P0001',null,'Operations Head cannot bypass Guard consent');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('other')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),true)$$,'42501',null,'Unrelated Guard cannot respond');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into exchange_results(result) select is((select count(*) from public.shift_swap_requests where id=pg_temp.f('request')),1::bigint,'Target Guard can read invitation');
insert into exchange_results(result) select lives_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),true)$$,'Target Guard accepts');
insert into exchange_results(result) select throws_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),false)$$,'P0001',null,'Response cannot execute twice');
reset role;
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('guard'),'Consent alone does not alter schedules');
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id=pg_temp.f('admin')),1::bigint,'Operations Head notified after consent');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('admin')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.decide_duty_request(pg_temp.f('request'),true)$$,'Operations Head approves accepted swap');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('offered')),pg_temp.f('peer'),'Peer assigned original duty');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('target')),pg_temp.f('guard'),'Requester assigned exchanged duty');
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.submit_duty_exchange(pg_temp.f('target'),pg_temp.f('offered'),'Please exchange back',pg_temp.f('guard')||'/again.pdf','Letter.pdf')$$,'Second exchange can be requested');
update exchange_fixture set id=(select id from public.shift_swap_requests where letter_path=pg_temp.f('guard')||'/again.pdf') where key='request';
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('peer')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.respond_to_duty_swap(pg_temp.f('request'),false)$$,'Target Guard declines');
insert into exchange_results(result) select is((select guard_response from public.shift_swap_requests where id=pg_temp.f('request')),'declined','Decline is recorded');
reset role;
insert into exchange_results(result) select is((select count(*) from public.user_notifications where entity_id=pg_temp.f('request') and recipient_id=pg_temp.f('admin')),0::bigint,'Declined request is not forwarded');
insert into exchange_results(result) select is((select user_id from public.schedules where id=pg_temp.f('target')),pg_temp.f('guard'),'Decline leaves schedule unchanged');
-- Deployment detail resolution and map snapshot shape.
update public.locations set address='123 Main Street, Bacolod, Negros Occidental, Philippines' where id=pg_temp.f('site');
update public.profiles set assigned_location_id=pg_temp.f('site') where id=pg_temp.f('guard');
insert into exchange_results(result) select ok(private.guard_deployment_label(pg_temp.f('guard'),pg_temp.f('org'),now()) like '%123 Main Street%','Site resolver returns full saved address');
insert into exchange_results(result) select ok(public.live_guard_map_snapshot() ? 'server_now' and public.live_guard_map_snapshot() ? 'locations','Live map preserves snapshot contract');
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('guard')::text,true);end$$;
insert into exchange_results(result) select lives_ok($$select public.file_incident_report('other',repeat('A',104),'Test narrative',now(),null,null,10.67,122.95,null)$$,'Incident filing resolves the assigned home post without a client label');
reset role;
insert into exchange_results(result) select ok((select location_label like '%123 Main Street%' from public.incidents where user_id=pg_temp.f('guard') order by created_at desc limit 1),'New incident stores full deployment address');
update exchange_fixture set id=(select id from public.incidents where user_id=pg_temp.f('guard') order by created_at desc limit 1) where key='request';
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub',pg_temp.f('other')::text,true);end$$;
insert into exchange_results(result) select throws_ok($$select public.incident_deployment_site(pg_temp.f('request'))$$,'42501',null,'Unrelated Guard cannot retrieve incident site');
reset role;
insert into exchange_results(result) select * from finish();
select result from exchange_results order by n;
rollback;
