// One-time, explicitly scoped test cleanup. Never part of deployment/migrations.
const fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto'),cp=require('child_process');
const cli='C:/Users/Administrator/AppData/Local/npm-cache/_npx/aa8e5c70f9d8d161/node_modules/supabase/dist/supabase.js';
const project='uqtupmpofjqrnefgrexm',base=`https://${project}.supabase.co`;
const ids=['ca2a9eca-8eb2-4750-9aef-94e82b1a4107','0d8bad51-1171-4647-8050-0e2a7b938a6d','9371dc23-a195-4b40-8c72-1acb810227aa','0b73fcd3-2c0a-46e4-8995-e260d7029dc1','80af7225-22f6-4b76-a5dd-6a53f04c4fbf','8b874098-45e5-4d8c-8686-dab182f1c0c8','9aab838d-9ba3-488f-991a-d9e9cf2de4cf','dfe5c192-47a7-4d92-8afe-8bb3e8c009b1','8fbe314e-4e1b-4569-b96d-8d97be6bcc4b','f6409f76-1b86-4cfb-a1f2-08ec3b630061','5fd8075d-39a8-4a2b-bc4f-117b8a589059','9dd704fd-5a23-43f3-8289-29b545d8f2c4','14019305-33d5-4da4-a7bb-8c2b2f2d705c'];
const keep=['d58eff33-ebca-4966-9eb4-e7e38eac0601','17d01c1b-b6f1-4174-be2d-872704dc31eb','36753b64-c55e-4239-adb7-df68fc2fbc31','94b55b74-df0d-4ef1-87f5-01b57889090d','87da457d-e637-4db8-bbb1-ed2ea45a1912','deceb6db-70d9-4be0-8db7-e22581ff6de3','8079204a-ff81-470e-ab4e-c495a230b44f'];
const quoted=values=>values.map(v=>`'${v}'`).join(','),target=`(${quoted(ids)})`,kept=`(${quoted(keep)})`;
function run(args){try{return cp.execFileSync(process.execPath,[cli,...args],{encoding:'utf8',maxBuffer:256*1024*1024,stdio:['ignore','pipe','pipe']});}catch(e){throw Error('Supabase command failed: '+String(e.stderr||e.stdout||'').slice(0,700));}}
function query(sql){const raw=run(['db','query','--linked',sql]);const data=JSON.parse(raw.slice(raw.indexOf('{')));if(!data.rows)throw Error('Database query did not return expected rows');return data.rows;}
function fileQuery(file){const raw=run(['db','query','--linked','--file',file]);const data=JSON.parse(raw.slice(raw.indexOf('{')));if(!data.rows)throw Error('Database cleanup query failed');return data.rows;}
const pointer='testing/removed-guards-backup-path.txt';
const mode=process.argv[2]||'prepare';
async function storageKey(){const raw=run(['projects','api-keys','--project-ref',project,'--reveal','--output','json']);const data=JSON.parse(raw.trim());const keys=Array.isArray(data)?data:data.keys||data.api_keys;const key=keys?.find(k=>k.name==='service_role')?.api_key||keys?.find(k=>k.type==='secret')?.api_key;if(!key)throw Error('No backend storage key available');return key;}
async function storageFetch(url,key,options={}){const response=await fetch(base+'/storage/v1/'+url,{...options,headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json',...options.headers},signal:AbortSignal.timeout(60000)});if(!response.ok)throw Error(`Storage request failed: ${response.status}`);return response;}
const matchIds=(column)=>`${column} in ${target}`;
const predicates={
 profiles:matchIds('id'),schedules:matchIds('user_id'),attendance_sessions:matchIds('user_id'),attendance_punches:matchIds('user_id'),incidents:matchIds('user_id'),accomplishment_reports:matchIds('guard_id'),guard_assignment_history:matchIds('guard_id'),guard_live_locations:matchIds('user_id'),account_presence_sessions:matchIds('user_id'),attendance_timeout_reviews:matchIds('guard_id'),
 shift_swap_requests:`requester_id in ${target} or target_guard_id in ${target} or requested_schedule_id in (select id from public.schedules where user_id in ${target}) or target_schedule_id in (select id from public.schedules where user_id in ${target}) or replacement_schedule_id in (select id from public.schedules where user_id in ${target})`,
 incident_deletion_audit:`incident_id in (select id from public.incidents where user_id in ${target})`,
 user_notifications:`exists(select 1 from cleanup_entities e where to_jsonb(t)::text like '%'||e.id::text||'%')`
};
const order=['user_notifications','account_presence_sessions','guard_live_locations','attendance_timeout_reviews','shift_swap_requests','accomplishment_reports','attendance_sessions','attendance_punches','guard_assignment_history','incident_deletion_audit','incidents','schedules','profiles'];
function cleanupSql(tables,commit){
let sql=`begin; set local lock_timeout='5s'; set local statement_timeout='90s';
${tables.map(t=>`lock table public.${t} in access exclusive mode;`).join('\n')}
lock table auth.users in share row exclusive mode;
do $$begin
 if (select count(*) from public.profiles where id in ${target} and role='user' and not active and removed_at is not null)<>13 then raise exception 'Cleanup target changed; stop';end if;
 if (select count(*) from public.profiles where id in ${kept} and removed_at is null)<>7 then raise exception 'Preserved personnel changed; stop';end if;
end$$;
create temp table cleanup_entities(id uuid primary key) on commit drop;
insert into cleanup_entities select id from public.profiles where id in ${target};
insert into cleanup_entities select id from public.schedules where user_id in ${target} on conflict do nothing;
insert into cleanup_entities select id from public.incidents where user_id in ${target} on conflict do nothing;
insert into cleanup_entities select id from public.attendance_sessions where user_id in ${target} on conflict do nothing;
insert into cleanup_entities select id from public.accomplishment_reports where guard_id in ${target} on conflict do nothing;
insert into cleanup_entities select id from public.shift_swap_requests where ${predicates.shift_swap_requests} on conflict do nothing;
create temp table cleanup_rows(table_name text,row_data jsonb) on commit drop;
create temp table cleanup_protected(table_name text,row_data jsonb) on commit drop;
create temp table cleanup_auth_keep on commit drop as select id,to_jsonb(u) as row_data from auth.users u where id not in ${target};
`;
for(const t of tables){const pred=predicates[t]||'false';sql+=`insert into cleanup_rows select '${t}',to_jsonb(t) from public.${t} t where coalesce((${pred}),false);\ninsert into cleanup_protected select '${t}',to_jsonb(t) from public.${t} t where not coalesce((${pred}),false);\n`;}
sql+=`create temp table cleanup_triggers on commit drop as select c.relname as table_name,t.tgname,t.tgenabled from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='public'::regnamespace and not t.tgisinternal and c.relname in (${quoted(order)});
do $$declare t record;begin for t in select * from cleanup_triggers loop execute format('alter table public.%I disable trigger %I',t.table_name,t.tgname);end loop;end$$;\n`;
for(const t of order){const key=t==='account_presence_sessions'?'session_id':t==='guard_live_locations'?'user_id':t==='incident_deletion_audit'?'incident_id':'id';sql+=`delete from public.${t} where ${key} in (select (row_data->>'${key}')::uuid from cleanup_rows where table_name='${t}');\n`;}
sql+=`delete from auth.users where id in ${target};
do $$declare t record;begin for t in select * from cleanup_triggers loop execute format('alter table public.%I %s trigger %I',t.table_name,case t.tgenabled when 'D' then 'disable' when 'A' then 'enable always' when 'R' then 'enable replica' else 'enable' end,t.tgname);end loop;end$$;
do $$begin if exists(select 1 from auth.users where id in ${target}) then raise exception 'Removed Auth account still exists';end if;
if exists(select 1 from cleanup_auth_keep k left join auth.users u on u.id=k.id where u.id is null or to_jsonb(u) is distinct from k.row_data) then raise exception 'Preserved Auth account changed';end if;end$$;
`;
for(const t of tables)sql+=`do $$begin if exists((select row_data from cleanup_protected where table_name='${t}' except select to_jsonb(t) from public.${t} t) union all (select to_jsonb(t) from public.${t} t except select row_data from cleanup_protected where table_name='${t}')) then raise exception 'Unexpected change to preserved public.${t}';end if;end$$;\n`;
sql+=`select table_name,count(*) as removed from cleanup_rows group by table_name order by table_name;\n${commit?'commit':'rollback'};`;
return sql;
}
(async()=>{
if(mode==='prepare'){
 const tables=query("select c.relname as name from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p') and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass and d.objid=c.oid and d.deptype='e') order by c.relname").map(r=>r.name);
 const known=[...Object.keys(predicates),'organizations','locations','platform_settings','platform_settings_audit','shift_roster_setups'];
 if(tables.some(t=>!known.includes(t)))throw Error('Unknown public table; review before cleanup');
 const backup=path.join(os.homedir(),'.codex','backups','sams-removed-guards-'+Date.now());fs.mkdirSync(backup,{recursive:true});fs.writeFileSync(pointer,backup);
 const union=tables.map(t=>`select '${t}' as table_name,coalesce(jsonb_agg(to_jsonb(t)),'[]') as data from public.${t} t`).concat([`select 'auth.users',coalesce(jsonb_agg(to_jsonb(t)),'[]') from auth.users t where id in ${target}`,`select 'auth.identities',coalesce(jsonb_agg(to_jsonb(t)),'[]') from auth.identities t where user_id in ${target}`,`select 'storage.objects',coalesce(jsonb_agg(to_jsonb(t)),'[]') from storage.objects t`]).join(' union all ');
 const data=query('begin transaction isolation level repeatable read read only;'+union+';commit;');fs.writeFileSync(path.join(backup,'database-backup.json'),JSON.stringify(data));
 const objects=data.find(r=>r.table_name==='storage.objects').data.filter(o=>ids.includes(o.owner_id)||ids.includes(o.name.split('/')[0]));
 const key=await storageKey();const manifest=[];
 for(const [i,obj] of objects.entries()){
  if(!ids.includes(obj.name.split('/')[0])||!ids.includes(obj.owner_id))throw Error('Ambiguous upload ownership');
  const bytes=Buffer.from(await (await storageFetch('object/'+encodeURIComponent(obj.bucket_id)+'/'+obj.name.split('/').map(encodeURIComponent).join('/'),key)).arrayBuffer());
  const file=`upload-${i}${path.extname(obj.name)}`;fs.writeFileSync(path.join(backup,file),bytes);manifest.push({bucket:obj.bucket_id,name:obj.name,file,size:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
 }
 fs.writeFileSync(path.join(backup,'uploads.json'),JSON.stringify(manifest,null,2));
 const dry=path.join(backup,'cleanup-dry-run.sql');fs.writeFileSync(dry,cleanupSql(tables,false));fs.writeFileSync(path.join(backup,'cleanup-commit.sql'),cleanupSql(tables,true));
 const result=fileQuery(dry);fs.writeFileSync(path.join(backup,'dry-run-result.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify({backup,uploadedFilesBackedUp:manifest.length,dryRun:result,allOtherPublicRowsPreserved:true},null,2));
}else if(mode==='execute'){
 const backup=fs.readFileSync(pointer,'utf8'),manifest=JSON.parse(fs.readFileSync(path.join(backup,'uploads.json'),'utf8'));
 fileQuery(path.join(backup,'cleanup-dry-run.sql'));
 const key=await storageKey();
 for(const item of manifest){const bytes=fs.readFileSync(path.join(backup,item.file));if(crypto.createHash('sha256').update(bytes).digest('hex')!==item.sha256)throw Error('Upload backup check failed');}
 for(const bucket of new Set(manifest.map(m=>m.bucket))){const prefixes=manifest.filter(m=>m.bucket===bucket).map(m=>m.name);await storageFetch('object/'+encodeURIComponent(bucket),key,{method:'DELETE',body:JSON.stringify({prefixes})});}
 const remaining=query(`select count(*) as count from storage.objects where owner_id in ${target} or split_part(name,'/',1) in ${target}`);if(Number(remaining[0].count)!==0)throw Error('Target uploads remain; database cleanup stopped');
 const result=fileQuery(path.join(backup,'cleanup-commit.sql'));fs.writeFileSync(path.join(backup,'cleanup-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({removed:result,uploadedFilesRemoved:manifest.length,backup},null,2));
}else throw Error('Unknown mode');
})().catch(e=>{console.error(e.message);process.exit(1);});
