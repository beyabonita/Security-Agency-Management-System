const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
http.createServer((req,res)=>{
  let file;try{file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));}catch{res.writeHead(400).end();return;}
  if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
  if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return;}
  res.setHeader('Content-Type',({'.html':'text/html','.css':'text/css','.js':'text/javascript','.json':'application/json','.png':'image/png'}[path.extname(file)]||'text/plain')+'; charset=utf-8');
  fs.createReadStream(file).pipe(res);
}).listen(9173,'127.0.0.1',()=>console.log('Evidence viewer http://127.0.0.1:9173/reports/White-Box-Testing-Report.html'));
