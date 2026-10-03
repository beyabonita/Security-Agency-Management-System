const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..', '..');
const webRoot = path.join(projectRoot, 'web');

function read(relativePath) {
  return fs.readFileSync(path.join(projectRoot, relativePath), 'utf8');
}

function pngDimensions(relativePath) {
  const bytes = fs.readFileSync(path.join(projectRoot, relativePath));
  assert.equal(bytes.subarray(1, 4).toString('ascii'), 'PNG', `${relativePath} must be a PNG`);
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

function htmlFiles(folder) {
  return fs.readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(folder, entry.name);
    if (entry.isDirectory()) return htmlFiles(absolute);
    return entry.name.endsWith('.html') ? [absolute] : [];
  });
}

const requiredImages = [
  'assets/branding/sentinel_link_mark.png',
  'assets/branding/sentinel_link_app_icon.png',
  'assets/branding/sentinel_link_logo.png',
  'assets/branding/twenty_twenty_security_agency_shield.png',
  'web/icons/sentinel-link-mark.png',
  'web/favicon.png',
  'web/icons/Icon-192.png',
  'web/icons/Icon-512.png',
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
  'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png',
];

requiredImages.forEach((relativePath) => {
  assert.ok(fs.statSync(path.join(projectRoot, relativePath)).size > 100, `${relativePath} is empty`);
  const dimensions = pngDimensions(relativePath);
  assert.ok(dimensions.width > 0 && dimensions.height > 0, `${relativePath} has invalid dimensions`);
});

assert.ok(
  fs.statSync(path.join(projectRoot, 'web/assets/twentytwenty-agency-office.jpg')).size > 100,
  'agency office login background is empty',
);

htmlFiles(webRoot).filter((absolutePath) => !absolutePath.includes(`${path.sep}tests${path.sep}`)).forEach((absolutePath) => {
  const relativePath = path.relative(webRoot, absolutePath).replaceAll('\\', '/');
  const html = fs.readFileSync(absolutePath, 'utf8');
  assert.match(html, /<link\s+rel=["']icon["']/i, `${relativePath} is missing the system favicon`);
});

assert.match(read('web/admin/css/admin-theme.css'), /sentinel-link-mark\.png/);
assert.match(read('web/inspector/css/inspector-theme.css'), /sentinel-link-mark\.png/);
assert.match(read('web/staff/login.html'), /icons\/sentinel-link-mark\.png/);
assert.match(read('web/staff/login.html'), /data-guard-app-setup/);
assert.match(read('web/staff/guard-app.js'), /supports Android devices only/);
assert.doesNotMatch(read('web/staff/app-download.html'), /iOS|iPhone|iPad|TestFlight/);
const releaseVersion = read('pubspec.yaml').match(/^version:\s*([\d.]+)\+\d+/m)[1];
assert.ok(read('web/staff/login.html').includes(`security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=${releaseVersion}`));
assert.match(read('web/staff/app-download.html'), /login\.html#guard-app-setup/);
assert.match(read('web/staff/login.html'), /Twenty-Twenty Security Agency/);
assert.match(read('web/staff/login.html'), /Security Agency Management System/);
assert.match(read('web/staff/login.css'), /twentytwenty-agency-office\.jpg/);
assert.match(read('web/system-access-7d92a4/login.html'), /twentytwenty-agency-office\.jpg/);
assert.match(read('web/js/theme-preference.js'), /sentinel-link-theme/);
assert.match(read('web/staff/guard-app.js'), /dataset\.platform/);
assert.match(read('web/system-access-7d92a4/login.html'), /icons\/sentinel-link-mark\.png/);
assert.match(read('lib/login.dart'), /SentinelBrandMark/);
assert.match(read('lib/homepage.dart'), /SentinelBrandMark/);
assert.match(read('pubspec.yaml'), /flutter_launcher_icons:\s*\n\s+android: true/);
assert.match(read('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'), /ic_launcher_foreground/);

console.log('Security Agency Management System branding asset checks passed.');
