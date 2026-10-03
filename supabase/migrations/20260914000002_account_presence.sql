-- Presence is recent contact from a valid Auth session, not profile.active.
create table public.account_presence_sessions (
  session_id uuid primary key,
  user_id uuid references public.profiles(id) on delete set null,
  display_name text not null,
  role text not null,
  signed_in_at timestamptz not null,
  last_seen_at timestamptz,
  signed_out_at timestamptz,
  client_kind text check (client_kind in ('web','app'))
);
create index account_presence_user_seen on public.account_presence_sessions(user_id,last_seen_at desc);
create index account_presence_history on public.account_presence_sessions(signed_in_at desc,session_id);
alter table public.account_presence_sessions enable row level security;
revoke all on public.account_presence_sessions from public, anon, authenticated;

-- Auth deletes sessions on sign-out/revocation. Preserve their history before
-- the clients lose authentication, including global sign-out and other tabs.
create or replace function private.record_account_auth_session()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    update public.account_presence_sessions set signed_out_at = clock_timestamp()
    where session_id = old.id and signed_out_at is null;
    return old;
  end if;
  insert into public.account_presence_sessions(session_id,user_id,display_name,role,signed_in_at,last_seen_at)
  select new.id,p.id,coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.middle_initial,p.last_name)),''),p.username,'Account'),
    p.role::text,coalesce(new.created_at,clock_timestamp()),clock_timestamp() from public.profiles p where p.id = new.user_id
  on conflict(session_id) do nothing;
  return new;
end;
$$;
revoke all on function private.record_account_auth_session() from public,anon,authenticated;
create trigger record_account_auth_session after insert or delete on auth.sessions
for each row execute function private.record_account_auth_session();

create or replace function public.touch_account_presence(p_client_kind text default 'web')
returns void language plpgsql security definer set search_path = '' as $$
declare v_session uuid := nullif(auth.jwt()->>'session_id','')::uuid;
begin
  if p_client_kind not in ('web','app') or p_client_kind is null then
    raise exception 'Invalid client.';
  end if;
  -- Lock the session so a simultaneous logout cannot race this heartbeat.
  perform 1 from auth.sessions s join public.profiles p on p.id=s.user_id
  where s.id=v_session and s.user_id=auth.uid() and p.active
    and (s.not_after is null or s.not_after > now()) for share of s;
  if not found then raise exception 'Session is no longer active.' using errcode='42501'; end if;
  insert into public.account_presence_sessions(session_id,user_id,display_name,role,signed_in_at,last_seen_at,client_kind)
  select s.id,p.id,coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.middle_initial,p.last_name)),''),p.username,'Account'),
    p.role::text,coalesce(s.created_at,clock_timestamp()),clock_timestamp(),p_client_kind
  from auth.sessions s join public.profiles p on p.id=s.user_id where s.id=v_session
  on conflict(session_id) do update set last_seen_at=excluded.last_seen_at,client_kind=excluded.client_kind
    where public.account_presence_sessions.signed_out_at is null;
end;
$$;
revoke all on function public.touch_account_presence(text) from public,anon;
grant execute on function public.touch_account_presence(text) to authenticated;

create or replace function public.it_account_activity(
  p_search text default '',p_role text default '',p_status text default '',
  p_accounts_page integer default 0,p_history_page integer default 0
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_accounts jsonb; v_history jsonb;
begin
  if not exists(select 1 from public.profiles p join auth.sessions s on s.user_id=p.id
    where p.id=auth.uid() and p.role::text='it_admin' and p.active
      and s.id=nullif(auth.jwt()->>'session_id','')::uuid and (s.not_after is null or s.not_after>now())) then
    raise exception 'IT Admin access required.' using errcode='42501';
  end if;
  if coalesce(p_accounts_page,-1)<0 or coalesce(p_history_page,-1)<0 or p_accounts_page>100000 or p_history_page>100000 then
    raise exception 'Invalid page.';
  end if;
  with accounts as (
    select p.id,coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.middle_initial,p.last_name)),''),p.username,'Account') as name,
      p.username,p.email,p.role::text as role,p.active as account_enabled,max(a.last_seen_at) as last_seen_at,
      coalesce(bool_or(p.active and a.signed_out_at is null and s.id is not null
        and (s.not_after is null or s.not_after>now()) and a.last_seen_at>now()-interval '90 seconds'),false) as online
    from public.profiles p left join public.account_presence_sessions a on a.user_id=p.id
    left join auth.sessions s on s.id=a.session_id group by p.id
  ), filtered as (
    select * from accounts where (coalesce(p_role,'')='' or role=p_role or (p_role='admin' and role='operations_head'))
      and (coalesce(p_status,'')='' or (p_status='online' and online) or (p_status='offline' and not online))
      and concat_ws(' ',name,email) ilike '%'||left(coalesce(p_search,''),160)||'%'
  ) select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(r)) from
    (select * from filtered order by online desc,lower(name),id limit 50 offset p_accounts_page*50) r),'[]'::jsonb)) into v_accounts;
  with history as (
    select a.session_id,a.display_name as name,a.role,a.signed_in_at,a.last_seen_at,a.signed_out_at,a.client_kind,
      case when a.signed_out_at is not null then 'Session ended'
        when s.id is null or (s.not_after is not null and s.not_after<=now()) then 'Session expired'
        when not coalesce(p.active,false) then 'Account disabled'
        when a.last_seen_at>now()-interval '90 seconds' then 'Online'
        else 'Offline' end as status
    from public.account_presence_sessions a left join auth.sessions s on s.id=a.session_id
    left join public.profiles p on p.id=a.user_id
    where (coalesce(p_role,'')='' or a.role=p_role or (p_role='admin' and a.role='operations_head'))
      and concat_ws(' ',a.display_name,p.email) ilike '%'||left(coalesce(p_search,''),160)||'%'
  ) select jsonb_build_object('total',(select count(*) from history),'rows',coalesce((select jsonb_agg(to_jsonb(r)) from
    (select * from history order by signed_in_at desc,session_id limit 50 offset p_history_page*50) r),'[]'::jsonb)) into v_history;
  return jsonb_build_object('accounts',v_accounts,'history',v_history,'checked_at',clock_timestamp());
end;
$$;
revoke all on function public.it_account_activity(text,text,text,integer,integer) from public,anon;
grant execute on function public.it_account_activity(text,text,text,integer,integer) to authenticated;
notify pgrst,'reload schema';
