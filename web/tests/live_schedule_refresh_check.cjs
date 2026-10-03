// Reproduce the original schema ambiguity and verify the actual fixed SELECT.
// Anonymous API calls intentionally return no data; Operations Head RLS is verified by
// supabase/tests/schedule_refresh_read_check.sql using counts only.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const html=fs.readFileSync(path.join(root,'web/admin/schedule.html'),'utf8');
const selection=html.match(/\.from\('schedules'\)\s*\.select\('([^']+)'\)/)?.[1];
if(!selection)throw new Error('Could not find the schedule history query.');
const publicKey=fs.readFileSync(path.join(root,'web/js/supabase-firebase-bridge.js'),'utf8').match(/const KEY = '([^']+)'/)?.[1];
const endpoint='https://syyofdcynuzgergqlaqj.supabase.co/rest/v1/schedules';
const results=[];
async function probe(name,select,expectedStatus,expectedCode){
  const response=await fetch(`${endpoint}?select=${encodeURIComponent(select)}&limit=1`,{headers:{apikey:publicKey}});
  const body=await response.json();
  const pass=response.status===expectedStatus && (!expectedCode || body.code===expectedCode);
  results.push({name,status:pass?'PASS':'FAIL',httpStatus:response.status,errorCode:body.code || null,
    message:body.message || null,rows:Array.isArray(body)?body.length:null});
}
(async()=>{
  await probe('Old ambiguous request reproduces PGRST201','*,attendance_sessions(id,status),accomplishment_reports(id),shift_swap_requests(id)',300,'PGRST201');
  await probe('Explicit offered and target links resolve successfully',selection,200);
  if(process.argv.includes('--deployed')){
    const response=await fetch('https://security-agency-management-system-nu.vercel.app/admin/schedule.html?verify=schedule-refresh');
    const deployed=Buffer.from(await response.arrayBuffer());
    const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
    results.push({name:'Deployed schedule page matches tested source',status:response.ok && hash(deployed)===hash(Buffer.from(html))?'PASS':'FAIL',httpStatus:response.status,sha256:hash(deployed)});
  }
  const out=path.join(root,'build/qa/schedule-refresh');fs.mkdirSync(out,{recursive:true});
  const report={date:new Date().toISOString(),readOnly:true,results};
  fs.writeFileSync(path.join(out,'live-query-check.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  if(results.some(r=>r.status==='FAIL'))process.exitCode=1;
})().catch(error=>{console.error(error.message);process.exitCode=1;});
