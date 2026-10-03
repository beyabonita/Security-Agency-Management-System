// Loopback-only preview. Never connects a locally served portal to hosted Supabase.
const fs=require('node:fs'),http=require('node:http'),path=require('node:path');
const root=path.resolve(__dirname,'../web');
const demo=process.argv.includes('--demo');
const url=process.env.SUPABASE_URL||'http://127.0.0.1:54321';
if(!['127.0.0.1','localhost','[::1]'].includes(new URL(url).hostname)) throw new Error('Only a local Supabase URL is allowed.');
const key=process.env.SUPABASE_PUBLISHABLE_KEY||'local-preview-no-key';
const config=JSON.stringify({url,key}).replaceAll('<','\\u003c');
const inject=`<script>window.SENTINEL_LOCAL_SUPABASE=${config};window.SENTINEL_LIVE_TRACKING_ENABLED=true;window.SENTINEL_LIVE_TRACKING_DEMO=${demo};</script>`;
const types={'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2'};
http.createServer((req,res)=>{
  try {
    const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(name.split('/').some(p=>p.startsWith('.'))||name.includes('\\')) {res.writeHead(403).end();return;}
    const file=path.resolve(root,'.'+(name==='/'?'/admin/live-tracking.html':name));
    if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
    let body=fs.readFileSync(file);
    if(file.endsWith('.html'))body=Buffer.from(body.toString().replace('<head>','<head>'+inject));
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(body);
  } catch(_){res.writeHead(404).end('Not found');}
}).listen(4175,'127.0.0.1',()=>console.log(`Local ${demo?'SIMULATED map':'Supabase map'}: http://127.0.0.1:4175/admin/live-tracking.html`));
