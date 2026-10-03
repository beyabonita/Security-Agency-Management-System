import { ApiError, handleJsonPost, authenticatedUserId, serviceClient } from '../../../supabase/functions/_shared/api.ts';
import * as accounts from '../../../supabase/functions/_shared/accounts.ts';
import { contractPeriod } from '../../../supabase/functions/_shared/contract-period.ts';
import { deleteIncidentHandler } from '../../../supabase/functions/admin-delete-incident/handler.ts';

let serial=200;
function eq(actual:unknown, expected:unknown) {
  if(JSON.stringify(actual)!==JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}; actual ${JSON.stringify(actual)}`);
}
function wb(module:string, method:string, scenario:string, input:unknown, expected:unknown, run:()=>unknown|Promise<unknown>) {
  const id=`WB-${++serial}`;
  Deno.test(`${id} ${module}.${method}: ${scenario}`,async()=>{
    const meta={id,module,method,scenario,input,expected,framework:'Deno.test',source:'testing/whitebox/unit_tests/backend_test.ts'};
    try { const actual=await run(); console.log('WB_EVIDENCE '+JSON.stringify({...meta,actual,at:new Date().toISOString()})); eq(actual,expected); }
    catch(e) { console.log('WB_ERROR '+JSON.stringify({...meta,error:String(e)})); throw e; }
  });
}
function errorCode(run:()=>unknown) { try {run();return null;} catch(e){return e instanceof ApiError ? e.code : String(e);} }
const actor='11111111-1111-4111-8111-111111111111';
const target='22222222-2222-4222-8222-222222222222';
const req=(body:unknown={},headers:Record<string,string>={},method='POST')=>new Request('https://example.invalid/unit',{method,headers:{'Content-Type':'application/json',Authorization:'Bearer fixture',...headers},...(method==='GET'||method==='OPTIONS'?{}:{body:JSON.stringify(body)})});

for(const role of ['user','inspector','admin','it_admin','owner','',null,42]) wb('accounts','isAppRole','role allowlist',role,['user','inspector','admin','it_admin'].includes(role as string),()=>accounts.isAppRole(role));
for(const category of ['regular','contract','temporary',null,42]) wb('accounts','isEmploymentCategory','employment allowlist',category,['regular','contract'].includes(category as string),()=>accounts.isEmploymentCategory(category));
for(const [value,expected] of [['ab',false],['abc',true],['a'.repeat(32),true],['a'.repeat(33),false],['Aaa',false],['a-b',false],['a.b_1',true]] as const) wb('accounts','usernameValid','username bounds',value,expected,()=>accounts.usernameValid(value));
for(const [value,expected] of [[actor,true],['invalid',false],['11111111-1111-0111-8111-111111111111',false],['',false]] as const) wb('accounts','uuidValid','UUID structure and version',value,expected,()=>accounts.uuidValid(value));
for(const [value,expected] of [[undefined,null],[null,'invalid_input'],[42,'invalid_input'],['a','invalid_input'],['abc',null],['abcd','invalid_input'],['a\0b','invalid_input']] as const) wb('accounts','optionalString','type, missing, boundary, NUL',String(value),expected,()=>errorCode(()=>accounts.optionalString({x:value},'x','Value',{min:2,max:3})));
wb('accounts','optionalString','normalization precedes validation',' ABC ','abc',()=>accounts.optionalString({x:' ABC '},'x','Value',{max:3,normalize:v=>v.trim().toLowerCase()}));
for(const v of [true,false,undefined,null,'true',1]) wb('accounts','optionalBoolean','strict boolean types',String(v),typeof v==='boolean'||v===undefined?null:'invalid_input',()=>errorCode(()=>accounts.optionalBoolean({x:v},'x','Value')));
for(const [message,expected] of [['duplicate username','That username is already in use.'],['weak password','The password does not meet the authentication requirements.'],['secret db details','The authentication account could not be processed. Check the details and try again.']]) wb('accounts','authProviderMessage','sanitized auth failure',message,expected,()=>accounts.authProviderMessage(new Error(message)));
wb('accounts','databaseBusinessMessage','unique username','23505 username','That username is already in use.',()=>accounts.databaseBusinessMessage({code:'23505',message:'duplicate username'}));
wb('accounts','databaseBusinessMessage','unknown database error hidden','XX001 internal details',null,()=>accounts.databaseBusinessMessage({code:'XX001',message:'internal details'})??null);
for(const [s,e,ok] of [['2026-09-05','2026-09-05',true],['2026-09-06','2026-09-05',false],['2026-02-30','2026-03-01',false],['2028-02-29','2028-02-29',true],['','',false],[null,null,false],[42,43,false]] as const) wb('contract-period','contractPeriod','ordered real-date validation',[s,e],ok,()=>!contractPeriod('contract',s,e).error);
wb('contract-period','contractPeriod','legacy dates explicitly allowed',[null,null,true],{start:null,end:null},()=>contractPeriod('contract',null,null,true));
wb('contract-period','contractPeriod','regular category clears dates','regular',{start:null,end:null},()=>contractPeriod('regular','2026-01-01','2026-12-31'));

for(const [body,status] of [[{},200],[[],400],[null,400],['text',400],[4,400]] as const) wb('api','handleJsonPost','JSON object validation',body,status,async()=>(await handleJsonPost(req(body),()=>({data:{ok:true}}))).status);
for(const [headers,status] of [[{'Content-Type':'text/plain'},415],[{'Content-Length':'-1'},400],[{'Content-Length':'32769'},413],[{Origin:'https://untrusted.invalid'},403]] as const) wb('api','handleJsonPost','request headers validated',headers,status,async()=>{let called=false;const r=await handleJsonPost(req({},headers),()=>{called=true;return {data:{}};});eq(called,false);return r.status;});
for(const [method,status] of [['GET',405],['OPTIONS',204]] as const) wb('api','handleJsonPost','method routing',method,status,async()=>{let called=false;const r=await handleJsonPost(req({}, {},method),()=>{called=true;return {data:{}};});eq(called,false);return r.status;});
wb('api','handleJsonPost','invalid JSON','{broken',400,async()=>(await handleJsonPost(new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json'},body:'{broken'}),()=>({data:{}}))).status);
wb('api','handleJsonPost','actual UTF8 size limit','32769 x characters',413,async()=>(await handleJsonPost(req({x:'x'.repeat(32769)}),()=>({data:{}}))).status);
wb('api','handleJsonPost','unexpected exception sanitized','Error(secret)',[500,'internal_error',false],async()=>{const r=await handleJsonPost(req(),()=>{throw new Error('secret');});const b=await r.json();return [r.status,b.code,JSON.stringify(b).includes('secret')];});
wb('api','handleJsonPost','allowed CORS and correlation headers','localhost origin; WB-request',['http://localhost:3000','WB-request','no-store'],async()=>{const r=await handleJsonPost(req({}, {Origin:'http://localhost:3000','X-Request-Id':'WB-request'}),()=>({data:{}}));return [r.headers.get('Access-Control-Allow-Origin'),r.headers.get('X-Request-Id'),r.headers.get('Cache-Control')];});
for(const header of ['', 'Basic fixture','Bearer','Bearer two tokens']) wb('api','authenticatedUserId','malformed authorization rejected',header,'unauthorized',async()=>{try{await authenticatedUserId(req({}, {Authorization:header}),{auth:{getUser:()=>{throw new Error('must not call');}}} as any);return null;}catch(e){return (e as ApiError).code;}});
for(const bad of [false,true]) wb('api','authenticatedUserId','auth provider verifies token',{authFailed:bad},bad?'unauthorized':actor,async()=>{try{return await authenticatedUserId(req(),{auth:{getUser:()=>({data:{user:bad?null:{id:actor}},error:null})}} as any);}catch(e){return (e as ApiError).code;}});

function fixture(o:Record<string,any>={}) {
  const calls:string[]=[];
  const caller={role:'admin',active:true,organization_id:'org1',...o.caller};
  const managed={id:target,role:'user',active:true,organization_id:'org1',username:'guard',email:'guard@asamanion-26858.auth',employment_category:'regular',first_name:'A',last_name:'B',middle_initial:'',...o.target};
  const client:any={auth:{getUser:()=>({data:{user:o.authFailed?null:{id:actor}},error:null}),admin:{
    createUser:()=>{calls.push('authCreate');return {data:{user:o.authError?null:{id:target}},error:o.authError?{message:'duplicate'}:null};},
    deleteUser:()=>{calls.push('rollback');return {error:o.rollbackError?{message:'failed'}:null};},
    getUserById:()=>({data:{user:o.authLookupError?null:{id:target,user_metadata:{}}},error:null}),
    updateUserById:()=>{calls.push('authUpdate');return {data:{user:{id:target}},error:o.authUpdateError?{message:'password rejected'}:null};}
  }},from:(table:string)=>{
    const filters:Record<string,any>={};let updating=false;let count=false;
    const result=()=>{
      if(table==='organizations')return {data:{id:'org1',active:true},error:null};
      if(updating){const failed=o.profileError||(o.updateRollbackError&&calls.filter(x=>x==='profileUpdate').length>1);return {data:failed?null:{id:target},error:failed?{message:'failed'}:null};}
      if(count)return {count:o.itCount??2,error:null};
      if(filters.id===actor)return {data:o.noCaller?null:caller,error:o.lookupError?{message:'failed'}:null};
      if(filters.id===target)return {data:managed,error:null};
      return {data:o.duplicate?{id:'duplicate'}:null,error:null};
    };
    const q:any={select:(_s:unknown,opts:any)=>{count=!!opts?.count;return q;},eq:(k:string,v:unknown)=>{filters[k]=v;return q;},neq:()=>q,update:()=>{updating=true;calls.push('profileUpdate');return q;},maybeSingle:async()=>result(),then:(resolve:any,reject:any)=>Promise.resolve(result()).then(resolve,reject)};return q;
  },rpc:(_name:string,args:any)=>{calls.push(args.p_finish?'finish':'begin');if(o.beginError&&!args.p_finish)return {data:null,error:{code:o.beginError}};if(args.p_finish)return {data:{deleted:true},error:o.finishError?{message:'failed'}:null};return {data:o.missingIncident?null:{user_id:actor,video_path:o.path===undefined?`${actor}/clip.mp4`:o.path,deleted:o.deleted,video_shared:o.shared},error:null};},storage:{from:()=>({remove:()=>{calls.push('remove');return {error:o.mediaError?{message:'failed'}:null};}})}};
  return {client,calls};
}
for(const [o,status,expectedCalls] of [[{},200,['begin','remove','finish']],[{authFailed:true},401,[]],[{beginError:'42501'},403,['begin']],[{beginError:'P0002'},404,['begin']],[{beginError:'XX001'},500,['begin']],[{missingIncident:true},500,['begin']],[{deleted:true},200,['begin']],[{shared:true},200,['begin','finish']],[{path:null},200,['begin','finish']],[{path:`${actor}/../x`},409,['begin']],[{path:`${target}/clip.mp4`},409,['begin']],[{mediaError:true},502,['begin','remove']],[{finishError:true},500,['begin','remove','finish']]] as const) wb('deleteIncidentHandler','deleteIncidentHandler','authorization and ordered failure handling',o,[status,expectedCalls],async()=>{const f=fixture(o);const r=await deleteIncidentHandler(req({incidentId:target}),()=>f.client);return [r.status,f.calls];});
for(const id of [null,'',42,'invalid']) wb('deleteIncidentHandler','deleteIncidentHandler','invalid ID never touches database',id,[400,[]],async()=>{const f=fixture();const r=await deleteIncidentHandler(req({incidentId:id}),()=>f.client);return [r.status,f.calls];});

// Capture registered callbacks, without opening a server or issuing HTTP requests.
const captured:((r:Request)=>Promise<Response>)[]=[];
const originalServe=Deno.serve;
(Deno as any).serve=(fn:any)=>{captured.push(fn);return {};};
await import('../../../supabase/functions/admin-create-user/index.ts');
await import('../../../supabase/functions/admin-manage-user/index.ts');
await import('../../../supabase/functions/it-provision-client/index.ts');
(Deno as any).serve=originalServe;
Deno.env.set('SUPABASE_URL','https://example.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','unit-test-placeholder');
const createBody={username:'newguard',password:'fixture-password',firstName:'Test',lastName:'Guard',role:'user'};
for(const role of ['user','inspector','admin','it_admin']) {
  for(const active of [false,true]) wb('admin-create-user','registered handler','caller role and active restrictions',{role,active},active&&role==='admin'?200:403,async()=>{const f=fixture({caller:{role,active}});(globalThis as any).__whiteboxClient=f.client;const r=await captured[0](req(createBody));if(r.status!==200)eq(f.calls,[]);return r.status;});
}
for(const [o,body,status,code] of [[{},{role:'admin'},403,'forbidden_role'],[{caller:{role:'it_admin'}},{role:'admin'},200,null],[{caller:{role:'it_admin'}},{role:'it_admin'},200,null],[{caller:{organization_id:null}},{},403,'forbidden'],[{duplicate:true},{},409,'username_in_use'],[{}, {password:'12345'},400,'invalid_input'],[{}, {password:42},400,'invalid_input'],[{}, {role:'owner'},400,'invalid_role'],[{}, {username:'x!'},400,'invalid_username'],[{authError:true},{},400,'auth_account_create_failed'],[{profileError:true},{},500,'profile_create_failed'],[{profileError:true,rollbackError:true},{},500,'account_create_rollback_failed']] as const) wb('admin-create-user','registered handler','validation, duplicate and rollback',{options:o,body},[status,code],async()=>{const f=fixture(o);(globalThis as any).__whiteboxClient=f.client;const r=await captured[0](req({...createBody,...body}));const b=await r.json();if((o as any).profileError)eq(f.calls,['authCreate','profileUpdate','rollback']);return [r.status,b.code??null];});
for(const [o,body,status,code] of [[{caller:{role:'user'}},{},403,'forbidden'],[{caller:{active:false}},{},403,'forbidden'],[{}, {action:'delete'},409,'account_deletion_disabled'],[{}, {action:'bad'},400,'invalid_action'],[{}, {userId:actor},400,'self_management_blocked'],[{target:{organization_id:'org2'}},{},403,'forbidden_target'],[{}, {role:'inspector'},403,'forbidden_role'],[{caller:{role:'it_admin'}},{},403,'forbidden_target'],[{caller:{role:'it_admin'},target:{role:'it_admin'},itCount:1},{active:false},409,'last_it_admin'],[{}, {active:'true'},400,'invalid_input']] as const) wb('admin-manage-user','registered handler','management permission and retention rules',{options:o,body},[status,code,[]],async()=>{const f=fixture(o);(globalThis as any).__whiteboxClient=f.client;const r=await captured[1](req({action:'update',userId:target,...body}));return [r.status,(await r.json()).code,f.calls];});
wb('it-provision-client','registered handler','retired provisioning returns gone',{},[410,'client_provisioning_retired'],async()=>{const r=await captured[2](req());return [r.status,(await r.json()).code];});
for(const [o,body,status,code,expectedCalls] of [
  [{},{firstName:'Changed'},200,null,['profileUpdate','authUpdate']],
  [{},{resetDevice:true},200,null,['profileUpdate','authUpdate']],
  [{caller:{role:'it_admin'},target:{role:'admin'}},{},200,null,['profileUpdate','authUpdate']],
  [{caller:{role:'it_admin'},target:{role:'it_admin'},itCount:2},{active:false},200,null,['profileUpdate','authUpdate']],
  [{authLookupError:true},{},500,'auth_account_lookup_failed',[]],
  [{profileError:true},{},500,'profile_update_failed',['profileUpdate']],
  [{authUpdateError:true},{},400,'auth_account_update_failed',['profileUpdate','authUpdate','profileUpdate']],
  [{authUpdateError:true,updateRollbackError:true},{},500,'account_update_rollback_failed',['profileUpdate','authUpdate','profileUpdate']],
  [{duplicate:true},{},409,'username_in_use',[]],
  [{},{employmentCategory:'contract',contractStartDate:'2026-02-30',contractEndDate:'2026-03-01'},400,'invalid_contract_period',[]]
] as const)wb('admin-manage-user','registered handler','successful update and rollback safety',{options:o,body},[status,code,expectedCalls],async()=>{const f=fixture(o);(globalThis as any).__whiteboxClient=f.client;const r=await captured[1](req({action:'update',userId:target,...body}));return [r.status,(await r.json()).code??null,f.calls];});
