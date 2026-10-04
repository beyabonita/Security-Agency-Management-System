// Run after npm ci in web/tests. The login's direct APK link is the source of truth.
const fs = require('node:fs');
const path = require('node:path');
const QRCode = require('qrcode');
const html = fs.readFileSync(path.join(__dirname, '../staff/login.html'), 'utf8');
const target = html.match(/class="qr-frame" href="([^"]+)"/)[1];
if (!/^https:\/\/(?:security-agency-management-system-download\.vercel\.app|www\.tts-agency\.site)\/downloads\/[^?]+\.apk(?:\?v=[\d.]+)?$/.test(target)) {
  throw Error('QR target must be the public Android APK, not the setup page.');
}
QRCode.toFile(path.join(__dirname, '../staff/guard-app-qr.png'), target, {
  type: 'png', width: 560, margin: 4, errorCorrectionLevel: 'M',
  color: { dark: '#000000', light: '#ffffff' },
}).then(() => console.log('Generated direct APK QR code:', target)).catch(error => {
  console.error(error); process.exitCode = 1;
});
