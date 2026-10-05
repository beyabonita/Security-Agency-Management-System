const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');
const failures = [];

function expectIncludes(source, text, label) {
  if (!source.includes(text)) failures.push(`Missing ${label}`);
}

function expectExcludes(source, text, label) {
  if (source.includes(text)) failures.push(`Unsafe ${label}`);
}

function expectMatches(source, pattern, label) {
  if (!pattern.test(source)) failures.push(`Missing ${label}`);
}

function assertInlineScriptsParse(source, label) {
  const scripts = source.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi);
  for (const match of scripts) {
    try {
      // Compile only; browser globals are intentionally not executed in this check.
      new Function(match[1]);
    } catch (error) {
      failures.push(`${label} has invalid inline JavaScript: ${error.message}`);
    }
  }
}

function assertJavaScriptParses(source, label) {
  try {
    new Function(source);
  } catch (error) {
    failures.push(`${label} has invalid JavaScript: ${error.message}`);
  }
}

const adminUsers = read('admin', 'users.html');
expectIncludes(adminUsers, 'escapeHtml(fullName)', 'escaped admin personnel names');
expectIncludes(adminUsers, 'escapeHtml(displayLoginId(data))', 'escaped admin usernames');
expectIncludes(adminUsers, "onclick=\"assignDeployment('${id}')\"", 'ID-only deployment action');
expectIncludes(adminUsers, "onclick=\"viewDTR('${id}')\"", 'ID-only DTR action');
expectExcludes(adminUsers, "assignDeployment('${id}','", 'name in deployment handler attribute');
expectExcludes(adminUsers, "viewDTR('${id}','", 'name in DTR handler attribute');
expectIncludes(adminUsers, "from('attendance_sessions')", 'schedule-linked admin DTR query');
expectExcludes(adminUsers, 'time_records', 'legacy admin DTR collection');
expectIncludes(adminUsers, "from('accomplishment_reports')", 'admin accomplishment review list');
expectIncludes(adminUsers, "rpc('review_accomplishment_report'", 'server-side accomplishment review');
expectExcludes(adminUsers, "from('accomplishment_reports').insert", 'direct accomplishment insertion');
expectIncludes(adminUsers, "rpc('assign_guard_inspector'", 'tenant-safe Inspector assignment');
expectIncludes(adminUsers, "from('guard_assignment_history')", 'visible assignment history');
expectIncludes(adminUsers, 'appDialog.runBusy(btn', 'animated personnel account creation');
expectIncludes(adminUsers, 'account created. Username:', 'consistent personnel creation toast');
expectExcludes(adminUsers, 'id="createGuardSuccess"', 'legacy inline personnel creation success message');
const inspectorPersonnelTable = adminUsers.match(/<section class="personnel-table-section" aria-labelledby="inspectorPersonnelHeading">[\s\S]*?<\/section>/)?.[0] || '';
expectIncludes(inspectorPersonnelTable, 'Inspector Personnel', 'Inspector personnel table');
expectExcludes(inspectorPersonnelTable, '>DTR<', 'Inspector personnel DTR column');
const inspectorRowRenderer = adminUsers.match(/function renderInspectorRow[\s\S]*?(?=\nfunction togglePersonnelActions)/)?.[0] || '';
expectExcludes(inspectorRowRenderer, 'viewDTR', 'Inspector personnel DTR action');
for (const page of ['dashboard.html', 'users.html', 'locations.html', 'schedule.html', 'incidents.html', 'swaps.html']) {
  const source = read('admin', page);
  expectIncludes(source, '</span> Personnel</a>', `${page} Personnel navigation label`);
  expectExcludes(source, '</span> Users</a>', `${page} legacy Users navigation label`);
}
const adminDashboard = read('admin', 'dashboard.html');
expectIncludes(adminDashboard, 'id="deploymentSiteFilter"', 'Operations Head deployment filters');
expectIncludes(adminDashboard, 'id="contractDonut"', 'Operations Head contract-status chart');
expectIncludes(adminDashboard, 'id="attendanceDonut"', 'Operations Head attendance-overview chart');
expectIncludes(adminDashboard, 'id="recentIncidentTableBody"', 'Operations Head recent incident table');
expectIncludes(adminDashboard, "data-incident-id", 'safe dashboard incident row identifier');
expectExcludes(adminDashboard, 'onclick="openDetail', 'dashboard inline incident opener');
assertInlineScriptsParse(adminDashboard, 'admin/dashboard.html');
assertInlineScriptsParse(adminUsers, 'admin/users.html');

const inspectorUsers = read('inspector', 'users.html');
expectIncludes(inspectorUsers, 'escapeHtml(fullName)', 'escaped inspector personnel names');
expectIncludes(inspectorUsers, 'escapeHtml(label)', 'escaped inspector duty-location labels');
expectIncludes(inspectorUsers, "onclick=\"viewDTR('${doc.id}')\"", 'ID-only inspector DTR action');
expectExcludes(inspectorUsers, "viewDTR('${doc.id}', '", 'name in inspector DTR handler attribute');
expectIncludes(inspectorUsers, "from('attendance_sessions')", 'schedule-linked inspector DTR query');
expectExcludes(inspectorUsers, 'time_records', 'legacy inspector DTR collection');
assertInlineScriptsParse(inspectorUsers, 'inspector/users.html');

const inspectorAttendancePath = path.join(root, 'inspector', 'attendance.html');
if (fs.existsSync(inspectorAttendancePath)) {
  failures.push('Inspector personal attendance page must be removed');
}
for (const page of ['dashboard.html', 'users.html', 'locations.html', 'incidents.html', 'swaps.html']) {
  const source = read('inspector', page);
  expectExcludes(source, 'href="attendance.html"', `${page} Inspector attendance navigation`);
  expectExcludes(source, "rpc('record_attendance_event'", `${page} Inspector attendance mutation`);
  expectExcludes(source, 'data-action="clock_', `${page} Inspector Time In/Out control`);
  expectExcludes(source, 'href="swaps.html"', `${page} Inspector duty-request approval navigation`);
}

const schedule = read('admin', 'schedule.html');
expectIncludes(schedule, '>${escapeHtml(guard.name)}${guard.role', 'escaped personnel filter labels');
const roster = read('admin', 'js', 'shift-roster.js');
expectIncludes(roster, '${escapeHtml(g.name)}</option>', 'escaped roster Guard names');
expectIncludes(roster, '${escapeHtml(currentName(ids[i]))}', 'escaped roster preview names');
assertJavaScriptParses(roster, 'admin/js/shift-roster.js');
assertInlineScriptsParse(schedule, 'admin/schedule.html');

const adminSwapsPage = read('admin', 'swaps.html');
const adminDutyRequests = read('admin', 'js', 'duty-requests.js');
expectIncludes(adminDutyRequests, "from('shift_swap_requests')", 'admin duty-request query');
expectIncludes(adminDutyRequests, "from('schedules')", 'admin schedule-linked duty details');
expectIncludes(adminDutyRequests, "from('request-letters').createSignedUrl", 'private request-letter download');
expectIncludes(adminDutyRequests, "'decide_duty_request':'decide_duty_relief'", 'authorized exchange and relief decisions');
expectIncludes(adminDutyRequests, 'request_type', 'swap and absence distinction');
expectExcludes(adminDutyRequests, 'innerHTML = r.reason', 'unescaped request reason');
assertInlineScriptsParse(adminSwapsPage, 'admin/swaps.html');
assertJavaScriptParses(adminDutyRequests, 'admin/js/duty-requests.js');

const inspectorSwaps = read('inspector', 'swaps.html');
expectIncludes(inspectorSwaps, "from('shift_swap_requests')", 'Inspector request-history query');
expectIncludes(inspectorSwaps, "from('schedules')", 'Inspector schedule-linked request history');
expectExcludes(inspectorSwaps, "rpc('review_shift_swap_by_inspector'", 'retired Inspector approval action');
assertInlineScriptsParse(inspectorSwaps, 'inspector/swaps.html');

for (const panel of ['admin', 'inspector']) {
  const locations = read(panel, 'locations.html');
  const locationError = panel === 'admin'
    ? 'escapeHtml(err?.message || "Could not load deployment sites.")'
    : 'escapeHtml(err?.message || "Could not load locations.")';
  expectIncludes(locations, locationError, `${panel} escaped location-load error`);
  if (panel === 'admin') {
    expectIncludes(locations, 'L.divIcon', 'CSS-rendered admin location marker');
    expectIncludes(locations, 'icon: locationPinIcon', 'custom admin location marker assignment');
    expectExcludes(locations, 'L.marker(DEFAULT_CENTER, { draggable: true }).addTo(map);', 'external default Leaflet marker');
    expectIncludes(locations, 'countrycodes: "ph"', 'hard Philippine geocoder country filter');
    expectIncludes(locations, 'bounded: "1"', 'bounded Philippine geocoder search');
    expectIncludes(locations, 'viewbox: PHILIPPINES_VIEWBOX', 'Philippine geocoder viewbox');
    expectIncludes(locations, 'result.address?.country_code === "ph"', 'defensive Philippine result validation');
    expectIncludes(locations, 'id="addressSearchButton"', 'explicit address-search action');
    expectExcludes(locations, 'setTimeout(() => searchAddress(query)', 'Nominatim autocomplete requests');
    expectIncludes(locations, 'requestId !== geolocationRequestId', 'stale geolocation callback guard');
    expectIncludes(locations, 'locationRecords.get(id)', 'cached deployment-site edit path');
    expectExcludes(locations, 'appDialog.toast(message, { tone: "danger" })', 'geolocation permission toast');
  }
  assertInlineScriptsParse(locations, `${panel}/locations.html`);
}

const vercelConfig = read('vercel.json');
expectIncludes(vercelConfig, 'sams-it-portal.vercel.app', 'dedicated IT Admin host');
expectIncludes(vercelConfig, 'security-agency-ms.vercel.app', 'dedicated Staff host');
expectExcludes(vercelConfig, 'sentinel-link-system.vercel.app', 'retired IT Admin host');
for (const host of ['https://a.tile.openstreetmap.org', 'https://b.tile.openstreetmap.org', 'https://c.tile.openstreetmap.org']) {
  expectIncludes(vercelConfig, host, `OpenStreetMap tile CSP host ${host}`);
}

for (const panel of ['admin', 'inspector']) {
  const incidents = read(panel, 'incidents.html');
  expectIncludes(incidents, 'photoData.length % 4 === 0', `${panel} image payload validation`);
  expectIncludes(incidents, 'escapeHtml(src)', `${panel} thumbnail source escaping`);
  expectExcludes(incidents, "if (inc.photoData) return 'data:image/jpeg;base64,' + inc.photoData", `${panel} raw image payload interpolation`);
  expectIncludes(incidents, 'incidentReportView.render', `${panel} shared detailed incident report`);
  expectIncludes(incidents, 'incidentReportView.loadVideo', `${panel} private evidence-video playback`);
  expectIncludes(incidents, "nextStatus === 'resolved' && statusNote.length < 5", `${panel} resolution-note validation`);
  expectIncludes(incidents, 'appDialog.toast', `${panel} modal/toast incident feedback`);
  assertInlineScriptsParse(incidents, `${panel}/incidents.html`);
}
const adminIncidents = read('admin', 'incidents.html');
expectIncludes(adminIncidents, "rpc('archive_incident_report'", 'server-authorized incident archiving');
expectIncludes(adminIncidents, 'Archive emergency report?', 'archiving confirmation');
expectExcludes(read('inspector', 'incidents.html'), 'archiveIncidentBtn', 'Inspector incident archiving action');

const incidentReportView = read('js', 'incident-report-view.js');
expectIncludes(incidentReportView, 'incident.detailedNarrative || incident.description', 'shared detailed incident narrative');
expectIncludes(incidentReportView, 'escapeHtml(photoSrc)', 'escaped detailed incident photo source');
expectIncludes(incidentReportView, ".from(VIDEO_BUCKET)", 'private incident video bucket access');
expectIncludes(incidentReportView, '.createSignedUrl(path, 900)', 'time-limited incident video URL');
expectIncludes(incidentReportView, 'safeSignedVideoUrl', 'signed incident video URL validation');
expectIncludes(incidentReportView, 'id="incidentEvidenceVideo"', 'incident video player');
expectExcludes(incidentReportView, '.getPublicUrl(', 'public incident evidence URL');
assertJavaScriptParses(incidentReportView, 'js/incident-report-view.js');

const compatibilityBridge = read('js', 'supabase-firebase-bridge.js');
expectIncludes(compatibilityBridge, 'window.supabase.createClient', 'official Supabase browser client');
expectIncludes(compatibilityBridge, 'client.auth.onAuthStateChange', 'official Supabase auth listener');
expectIncludes(compatibilityBridge, "rpc('update_incident_status'", 'server-side incident status update');
expectIncludes(compatibilityBridge, "status_note: 'statusNote'", 'incident review-note mapping');
expectIncludes(compatibilityBridge, "captured_at: 'capturedAt'", 'incident capture-time mapping');
expectIncludes(compatibilityBridge, "'deletion_requested_at'", 'incident deletion retry state');
expectIncludes(compatibilityBridge, "inspector_id: 'inspectorId'", 'Inspector-assignment mapping');
const platformConfiguration = read('js', 'platform-configuration.js');
expectIncludes(platformConfiguration, "rpc('current_platform_announcement')", 'portal-wide configuration announcement');
expectIncludes(platformConfiguration, "rpc('current_platform_support_email')", 'public support contact getter');
expectExcludes(platformConfiguration, "from('platform_settings')", 'protected platform settings in public renderer');
expectIncludes(platformConfiguration, 'encodeURIComponent(email)', 'encoded support mail address');
assertJavaScriptParses(platformConfiguration, 'js/platform-configuration.js');
expectExcludes(compatibilityBridge, '/rest/v1/', 'hand-written REST transport');
expectExcludes(compatibilityBridge, 'document.write', 'dynamic SDK injection');

const itDashboard = read('it-admin', 'dashboard.html');
expectIncludes(itDashboard, 'Platform maintenance', 'IT Admin maintenance boundary');
expectExcludes(itDashboard, 'Client organizations', 'retired multi-client IT Admin copy');
expectExcludes(itDashboard, 'is maintained by your IT team', 'retired IT Admin overview description');
assertInlineScriptsParse(itDashboard, 'it-admin/dashboard.html');

const itControls = read('it-admin', 'clients.html');
expectIncludes(itControls, 'Single-beneficiary operations', 'single beneficiary system mode');
expectExcludes(itControls, 'it-provision-client', 'retired client-provisioning call');
expectIncludes(itControls, 'id="refreshSystemCheck"', 'System Controls refresh action');
expectIncludes(itControls, 'async function runSystemCheck', 'live System Controls check');
expectIncludes(itControls, "appSupabase.from('profiles').select('role,active')", 'System Controls account-directory check');
expectIncludes(itControls, 'id="workspaceHealth"', 'System Controls health status');
expectIncludes(itControls, 'id="platformSettingsForm"', 'Super Operations Head platform configuration form');
expectExcludes(itControls, 'onsubmit="savePlatformSettings(event)"', 'shadowed platform settings inline handler');
expectIncludes(itControls, "addEventListener('submit', handlePlatformSettingsSubmit)", 'explicit platform settings submit listener');
expectIncludes(itControls, "rpc('update_platform_settings'", 'secured platform configuration save');
expectIncludes(itControls, "from('platform_settings_audit')", 'platform configuration audit list');
assertInlineScriptsParse(itControls, 'it-admin/clients.html');

const itAdminUi = read('it-admin', 'it-admin-ui.js');
expectIncludes(itAdminUi, "getElementById('itSidebar')", 'responsive IT navigation');
expectIncludes(itAdminUi, "event.key === 'Escape'", 'IT navigation escape handling');
assertJavaScriptParses(itAdminUi, 'it-admin/it-admin-ui.js');

const sharedDialogs = read('js', 'app-dialogs.js');
expectIncludes(sharedDialogs, "event.key === 'Tab'", 'dialog keyboard focus trap');
expectIncludes(sharedDialogs, 'sl-skip-link', 'keyboard skip link');
expectIncludes(sharedDialogs, 'sl-toast-close', 'dismissible notifications');
expectIncludes(sharedDialogs, 'function setBusy', 'shared action loading state');
expectIncludes(sharedDialogs, 'async function runBusy', 'shared async action wrapper');
expectIncludes(sharedDialogs, "setAttribute('aria-busy', 'true')", 'accessible busy-state announcement');
assertJavaScriptParses(sharedDialogs, 'js/app-dialogs.js');

const notificationCenter = read('js', 'notification-center.js');
expectIncludes(notificationCenter, "from('user_notifications')", 'shared notification inbox query');
expectIncludes(notificationCenter, "table: 'user_notifications'", 'realtime notification subscription');
expectIncludes(notificationCenter, "rpc('acknowledge_notification'", 'critical notification acknowledgement');
expectIncludes(notificationCenter, "rpc('send_broadcast_notification'", 'role-controlled notification broadcast');
expectIncludes(notificationCenter, 'Notification.requestPermission()', 'user-initiated browser alert permission');
expectIncludes(notificationCenter, "requireInteraction: item.priority === 'critical'", 'persistent critical desktop alert');
expectIncludes(notificationCenter, "item.priority === 'critical'", 'critical notification presentation');
expectMatches(notificationCenter, /state\.bell\.setAttribute\(\s*'aria-label'/, 'accessible unread notification count');
assertJavaScriptParses(notificationCenter, 'js/notification-center.js');

const adminShell = read('admin', 'js', 'admin-shell.js');
expectIncludes(adminShell, 'ax-sidebar-backdrop', 'responsive Operations Head navigation backdrop');
expectIncludes(adminShell, "event.key === 'Escape'", 'Operations Head navigation escape handling');
assertJavaScriptParses(adminShell, 'admin/js/admin-shell.js');

const inspectorShell = read('inspector', 'js', 'inspector-shell.js');
expectIncludes(inspectorShell, "event.key === 'Escape'", 'Inspector navigation escape handling');
assertJavaScriptParses(inspectorShell, 'inspector/js/inspector-shell.js');

const itUsers = read('it-admin', 'users.html');
expectIncludes(itUsers, "const platformRoles = ['admin', 'it_admin'];", 'restricted IT account roles');
expectIncludes(itUsers, 'IT Admin and Operations Head accounts only.', 'restricted IT account scope');
expectExcludes(itUsers, 'id="organizationId"', 'client organization selector');
expectExcludes(itUsers, 'resetDevice(', 'IT Admin device-reset action');
expectExcludes(itUsers, 'resetDevice: true', 'IT Admin device-reset request');
expectExcludes(itUsers, '<th>Device</th>', 'irrelevant IT Admin device column');
expectExcludes(itUsers, 'device_locked', 'irrelevant IT Admin device-state query');
expectIncludes(read('admin', 'users.html'), 'resetDevice(', 'Operations Head guard-device reset remains available');
assertInlineScriptsParse(itUsers, 'it-admin/users.html');

const adminLocations = read('admin', 'locations.html');
expectIncludes(adminLocations, 'Deployment Sites', 'HR deployment-site terminology');
expectIncludes(adminLocations, "rpc('default_geofence_radius')", 'IT-configured default geofence radius');

for (const [panel, page] of [
  ['HR dashboard', ['admin', 'dashboard.html']],
  ['Inspector dashboard', ['inspector', 'dashboard.html']],
  ['IT Admin dashboard', ['it-admin', 'dashboard.html']],
]) {
  expectExcludes(read(...page), 'page-desc', `${panel} explanatory dashboard copy`);
}

const portalPages = [
  'system-access-7d92a4/login.html',
  'staff/login.html',
  ...['admin', 'inspector'].flatMap((panel) => [
    `${panel}/dashboard.html`, `${panel}/users.html`, `${panel}/locations.html`,
    `${panel}/incidents.html`, `${panel}/swaps.html`,
  ]),
  'admin/schedule.html',
  'it-admin/dashboard.html',
  'it-admin/users.html',
  'it-admin/clients.html',
];
for (const page of portalPages) {
  const source = fs.readFileSync(path.join(root, page), 'utf8');
  const sdkAt = source.indexOf('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.3');
  const bridgeAt = source.indexOf('supabase-firebase-bridge.js');
  if (sdkAt < 0 || bridgeAt < 0 || sdkAt > bridgeAt) {
    failures.push(`${page} must load the pinned Supabase SDK before the compatibility bridge`);
  }
  if (
    source.includes('const firebaseConfig =') ||
    source.includes('firebaseapp.com') ||
    source.includes('firebasestorage.app') ||
    source.includes('firebaseio.com')
  ) {
    failures.push(`${page} still contains unused Firebase configuration`);
  }
}

for (const page of [
  ...['admin', 'inspector'].flatMap((panel) => [
    `${panel}/dashboard.html`, `${panel}/users.html`, `${panel}/locations.html`,
    `${panel}/incidents.html`, `${panel}/swaps.html`,
  ]),
  'admin/schedule.html',
  'it-admin/dashboard.html',
  'it-admin/users.html',
  'it-admin/clients.html',
]) {
  const source = fs.readFileSync(path.join(root, page), 'utf8');
  const bridgeAt = source.indexOf('supabase-firebase-bridge.js');
  const notificationsAt = source.indexOf('notification-center.js');
  if (notificationsAt < 0 || notificationsAt < bridgeAt) {
    failures.push(`${page} must load the notification center after Supabase`);
  }
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log('Web rendering security checks passed.');
