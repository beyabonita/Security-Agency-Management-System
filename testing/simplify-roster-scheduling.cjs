const fs = require('node:fs');
const file = 'web/admin/schedule.html';
let html = fs.readFileSync(file, 'utf8');
function removeBetween(start, end) {
  const first = html.indexOf(start), last = html.indexOf(end, first);
  if (first < 0 || last < 0) throw Error('Cannot locate section: ' + start);
  html = html.slice(0, first) + html.slice(last);
}
removeBetween('    <div class="section-title">Custom personnel duty plan</div>', '    <div class="section-title">Scheduled duty');
removeBetween('function applyScheduleDateLimits()', 'function setScheduleListPeriod(');
removeBetween('/** Returns an error message when the chosen duty day', 'function loadGuards()');
removeBetween('function onGuardSelected()', 'function loadLocations()');
removeBetween('// =====================================\n// ADD SCHEDULE', '// =====================================\n// RENDER SCHEDULES');
removeBetween('// =====================================\n// CLEAR FORM', 'function formatLocationCell(');
html = html.replace('let scheduleSaving = false;\n', '').replace('    setDefaultScheduleDates();\n', '');
html = html.replace('        const sel = document.getElementById("guardUser");\n        sel.innerHTML = \'<option value="">Select personnel</option>\';\n', '');
html = html.replace(/^.*if \(d.active !== false\) sel.innerHTML.*\n/m, '');
html = html.replace('        updateShiftPeriod();\n', '');
html = html.replace('        const sel = document.getElementById("scheduleLocation");\n        sel.innerHTML = \'<option value="">Select location</option>\';\n', '');
html = html.replace(/^.*const hint = address.*\n.*sel.innerHTML.*\n/m, '');
html = html.replace(/        if \(locations.length === 0\) \{[\s\S]*?        \}\n        onGuardSelected\(\);\n/, '');
html = html.replace('add a duty plan above.', 'assign a guard roster above.');
html = html.replace('Add one above to get started.', 'Assign a roster above to get started.');
html = html.replace('Periods &amp; actions', 'Shifts &amp; actions');
html = html.replace('        renderSchedules();\n        appDialog.toast("Schedule removed.', '        renderSchedules();\n        window.renderShiftRoster?.();\n        appDialog.toast("Schedule removed.');
const note = `    <section class="glass-card roster-dtr-guide mb-4" aria-labelledby="rosterDtrTitle">
      <h2 id="rosterDtrTitle">How the roster appears on the DTR</h2>
      <p>Each Guard records one Time In and one Time Out per shift. The shift's starting date owns the DTR row and cut-off, including when Time Out is the next morning. <strong>(+1)</strong> means the following day.</p>
      <p>The preview shows the DTR columns for each shift. The actual DTR uses recorded attendance, with no automatic lunch punches or meal deductions. Missing Time Out stays incomplete until the Operational Head verifies the actual end time.</p>
      <details>
        <summary>How does overtime work?</summary>
        <p>The roster schedules 12 hours per Guard with 2 Shifts, or 8 hours per Guard with 3 Shifts. Night duty is part of the assigned shift.</p>
        <p>This roster does not create separate overtime entries or approve overtime pay. The DTR's Overtime columns keep existing, separately scheduled overtime attendance; they stay blank for roster shifts. Total hours include all completed, recorded work.</p>
        <p>Staying past the scheduled end or forgetting Time Out does not automatically create overtime. The Operational Head must verify a missing Time Out. Verifying attendance does not approve overtime pay.</p>
      </details>
    </section>
`;
html = html.replace('    <div class="section-title">Scheduled duty', note + '    <div class="section-title">Scheduled duty');
fs.writeFileSync(file, html);
