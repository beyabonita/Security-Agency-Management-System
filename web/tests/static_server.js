const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const port = Number(process.env.PORT || 4173);
const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.apk': 'application/vnd.android.package-archive',
};

// Mirror the login redirects configured on Vercel so local navigation behaves
// like production instead of returning a plain 404 page.
const localRedirects = new Map([
  ['/admin/login.html', '/staff/login.html'],
  ['/inspector/login.html', '/staff/login.html'],
  ['/it-admin/login.html', '/system-access-7d92a4/login.html'],
]);

function requestPath(requestUrl) {
  return decodeURIComponent(new URL(requestUrl, 'http://127.0.0.1').pathname);
}

function fileFor(requestUrl) {
  const pathname = requestPath(requestUrl);
  const relativePath = pathname === '/' ? 'staff/login.html' : pathname.replace(/^\/+/, '');
  const candidate = path.resolve(root, relativePath);
  if (!candidate.startsWith(`${root}${path.sep}`)) return null;
  return candidate;
}

http.createServer((request, response) => {
  const pathname = requestPath(request.url || '/');
  const redirect = localRedirects.get(pathname);
  if (redirect) {
    response.writeHead(302, { Location: redirect, 'Cache-Control': 'no-store' });
    response.end();
    return;
  }

  const file = fileFor(request.url || '/');
  if (!file) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  fs.readFile(file, (error, content) => {
    if (error) {
      response.writeHead(error.code === 'ENOENT' ? 404 : 500);
      response.end(error.code === 'ENOENT' ? 'Not found' : 'Server error');
      return;
    }
    response.writeHead(200, {
      'Content-Type': mimeTypes[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    response.end(content);
  });
}).listen(port, '127.0.0.1', () => {
  console.log(`Security Agency Management System test server listening on ${port}`);
});
