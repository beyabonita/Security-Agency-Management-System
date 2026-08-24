const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');
const gradle = read('android', 'app', 'build.gradle.kts');

assert.match(gradle, /namespace = "com\.sentinellink\.app"/);
assert.match(gradle, /applicationId = "com\.sentinellink\.app"/);
assert.match(gradle, /taskGraph\.whenReady/);
assert.match(gradle, /Release signing is not configured/);
assert.doesNotMatch(gradle, /com\.example\.flutter_application_1/);

assert.ok(fs.existsSync(path.join(root, 'android', 'signing.properties.example')));
assert.ok(fs.existsSync(path.join(
  root,
  'android',
  'app',
  'src',
  'main',
  'kotlin',
  'com',
  'sentinellink',
  'app',
  'MainActivity.kt',
)));
assert.ok(!fs.existsSync(path.join(
  root,
  'android',
  'app',
  'src',
  'main',
  'kotlin',
  'com',
  'example',
  'flutter_application_1',
  'MainActivity.kt',
)));

console.log('Android release configuration checks passed.');
