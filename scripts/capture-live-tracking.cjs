// Screenshot-only rendering with an isolated headless Chrome profile; no user browser session.
const {spawn}=require('node:child_process'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
(async()=>{
 const profile=await fs.mkdtemp(path.join(os.tmpdir(),'sentinel-map-preview-'));
 const proc=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',[
   '--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'
 ],{windowsHide:true,stdio:['ignore','ignore','pipe']});
 let browser;
 try {
  const endpoint=await new Promise((resolve,reject)=>{
   const timeout=setTimeout(()=>reject(new Error('Chrome startup timed out')),30000);
   proc.stderr.on('data',chunk=>{const match=chunk.toString().match(/DevTools listening on (ws:\/\/[^\s]+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});
   proc.on('error',reject);
  });
  browser=new WebSocket(endpoint);await new Promise((r,j)=>{browser.onopen=r;browser.onerror=j;});
  let serial=0;const pending=new Map();
  browser.onmessage=({data})=>{const msg=JSON.parse(data);if(pending.has(msg.id)){const {resolve,reject}=pending.get(msg.id);pending.delete(msg.id);msg.error?reject(new Error(msg.error.message)):resolve(msg.result);}};
  const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});browser.send(JSON.stringify({id,method,params,sessionId}));});
  for(const [role,width,height,mobile]of [['admin',1440,1000,false],['inspector',390,1000,true]]){
   const {targetId}=await send('Target.createTarget',{url:'about:blank'});
   const {sessionId}=await send('Target.attachToTarget',{targetId,flatten:true});
   await send('Page.enable',{},sessionId);
   await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile},sessionId);
   await send('Page.navigate',{url:`http://127.0.0.1:4175/${role}/live-tracking.html`},sessionId);
   await new Promise(r=>setTimeout(r,8000));
   const metrics=await send('Runtime.evaluate',{expression:'JSON.stringify({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,status:document.getElementById("trackingStatus")?.textContent,count:document.getElementById("guardCount")?.textContent})',returnByValue:true},sessionId);
   console.log(role+': '+metrics.result.value);
   const shot=await send('Page.captureScreenshot',{format:'png'},sessionId);
   await fs.writeFile(path.resolve(__dirname,`../testing/live-tracking/${role}-preview.png`),Buffer.from(shot.data,'base64'));
   await send('Target.closeTarget',{targetId});
  }
  await send('Browser.close');
 } finally {browser?.close();proc.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
