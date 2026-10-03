const fs=require('node:fs');
for(const file of ['web/tests/schedule_lifecycle.spec.js','web/tests/responsive_shells.spec.js']){
  let s=fs.readFileSync(file,'utf8');
  s=s.replace("roster is the only editor and explains the actual DTR and overtime rules","roster is the only editor and the explanation panel is removed");
  s=s.replace("  await page.getByText('How does overtime work?', {exact:true}).click();\n  await expect(page.locator('.roster-dtr-guide')).toContainText('Verifying attendance does not approve overtime pay.');\n  await expect(page.locator('.roster-dtr-guide')).toContainText('stay blank for roster shifts');", "  await expect(page.locator('.roster-dtr-guide')).toHaveCount(0);\n  await expect(page.getByText('How the roster appears on the DTR')).toHaveCount(0);");
  s=s.replaceAll("toContainText('Morning OUT (+1)')","toContainText('6:00 AM (+1)')");
  s=s.replace("['—','6:00 AM (+1)','6:00 PM','—','—','—']","['6:00 PM','6:00 AM (+1)']");
  for(const [old,next] of [['Morning','Assigned shift / Site'],['Afternoon','Actual'],['Overtime','Worked']]) s=s.replace("toContainText('"+old+"')","toContainText('"+next+"')");
  fs.writeFileSync(file,s);
}
const file='web/tests/dtr_report_test.js';let s=fs.readFileSync(file,'utf8');
s=s.replace(/^assert.match\(preview, \/<th scope="colgroup".*\n/gm,'');
s+=`
assert.match(preview,/Assigned shift \\/ Site/);
assert.match(preview,/Actual<br>Time In/);
assert.match(preview,/Worked<br>Hours/);
assert.doesNotMatch(preview,/<th[^>]*>(Morning|Afternoon|Overtime)</);
const shiftReport=DtrReport.buildReport([genuineOvernight,verified,{...forgotten,status:'missed_timeout'}],firstCutoff);
const shiftRows=shiftReport.shiftRows.filter(r=>r.dutyDate==='2026-09-08');
assert.equal(shiftRows.length,3,'Distinct sessions on the same day must not be merged');
assert.match(shiftRows[0].actualIn,/8:00\\s*AM/);
assert.equal(shiftRows.filter(r=>r.status==='Verified').length,1);
assert.equal(shiftRows.filter(r=>r.status.includes('Missing Time Out'))[0].workedHours,'');
assert.equal(shiftRows.find(r=>r.actualOut.includes('(+1)')).workedHours,'12:00');
const archivedOvertime=DtrReport.buildReport([{...genuineOvernight,dtr_period:'overtime'}],firstCutoff);
assert.match(archivedOvertime.shiftRows.find(r=>r.actualIn).assignedShift,/Overtime assignment/);
console.log('Shift-format DTR rows preserve actual punches, multiple sessions, legacy overtime, and pending verification.');
`;
fs.writeFileSync(file,s);
