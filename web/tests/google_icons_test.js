const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const manifest = JSON.parse(read('assets/fonts/material-symbols-rounded.json'));
const names = new Set(manifest.icons);
const font = fs.readFileSync(path.join(root, 'assets/fonts/material-symbols-rounded.woff2'));

assert.equal(font.subarray(0, 4).toString(), 'wOF2', 'The bundled Google icon font must be valid WOFF2.');
assert.ok(font.length > 1000 && font.length < 100000, 'Keep the icon subset under 100 KB.');
assert.equal(names.size, manifest.icons.length, 'Icon names must be unique.');
assert.deepEqual(manifest.icons, [...manifest.icons].sort(), 'The Google API requires sorted icon names.');
assert.equal(manifest.family, 'Material Symbols Rounded');
assert.equal(manifest.license, 'Apache-2.0');
assert.match(read('assets/fonts/LICENSE.txt'), /Apache License/);
assert.match(read('css/google-icons.css'), /@font-face/);
assert.match(read('css/google-icons.css'), /material-symbols-rounded\.woff2/);
assert.doesNotMatch(read('css/google-icons.css'), /@import/, 'Interface icons must load without a third-party request.');
assert.match(read('css/theme-preference.css'), /@import url\('\.\/google-icons\.css'\)/);

function sourceFiles(folder) {
  return fs.readdirSync(folder, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(folder, entry.name);
    if (entry.isDirectory()) return ['tests', 'node_modules', 'downloads'].includes(entry.name) ? [] : sourceFiles(file);
    return /\.(html|js)$/.test(entry.name) ? [file] : [];
  });
}

let checkedIcons = 0;
for (const file of sourceFiles(root)) {
  const source = fs.readFileSync(file, 'utf8');
  for (const match of source.matchAll(/<[^>]+class=["'][^"']*material-symbols-rounded[^"']*["'][^>]*>\s*([a-z_]+)\s*</g)) {
    assert.ok(names.has(match[1]), `${path.relative(root, file)}: bundle the ${match[1]} icon.`);
    checkedIcons++;
  }
}
assert.ok(checkedIcons > 100, 'Every portal should use the shared Material icons.');

// Runtime-selected states are not literal icon markup, so guard those names too.
for (const name of ['dark_mode', 'light_mode', 'check_circle', 'error', 'warning', 'info', 'help',
  'notifications', 'notifications_active', 'emergency', 'health_and_safety', 'calendar_month',
  'location_on', 'swap_horiz', 'assignment_turned_in', 'manage_accounts', 'campaign', 'delete']) {
  assert.ok(names.has(name), `Missing dynamic icon ${name}.`);
}
for (const file of ['admin/dashboard.html', 'inspector/dashboard.html', 'it-admin/dashboard.html',
  'staff/login.html']) {
  assert.match(read(file), /material-symbols-rounded/, `${file} must use Google icons.`);
}
assert.match(read('css/theme-preference.css'), /\.btn-close:not\(\.sl-material-close\)/);
assert.match(read('css/app-experience.css'), /\.sl-dialog-icon\.material-symbols-rounded/);
assert.match(read('js/notification-center.js'), /emptyIcon\.setAttribute\('aria-hidden', 'true'\)/);
assert.match(read('js/platform-configuration.js'), /title: 'Contact support', icon: 'help'/,
  'The support dialog must use a bundled Google icon.');

console.log(`Google Material icon checks passed: ${names.size} bundled symbols, ${checkedIcons} markup references, ${(font.length / 1024).toFixed(1)} KB font.`);
