const fs=require('node:fs');
const file='web/admin/schedule.html';let html=fs.readFileSync(file,'utf8');
const first=html.indexOf('    <section class="glass-card roster-dtr-guide'),last=html.indexOf('    <div class="section-title">Scheduled duty',first);
if(first<0||last<0)throw Error('Missing guide');
html=html.slice(0,first)+html.slice(last);
html=html.replace('Scheduled duty · DTR layout','Scheduled guard shifts').replace('Scheduled duty in DTR columns','Scheduled guard shifts');
const headStart=html.indexOf('                <thead>'),headEnd=html.indexOf('                <tbody id="scheduleTable">',headStart);
html=html.slice(0,headStart)+`                <thead><tr>
                    <th scope="col">Personnel</th><th scope="col">Duty date</th>
                    <th scope="col">Scheduled IN</th><th scope="col">Scheduled OUT</th>
                    <th scope="col">Planned hours</th><th scope="col">Deployment site</th>
                    <th scope="col">Status &amp; actions</th>
                </tr></thead>
`+html.slice(headEnd);
html=html.replaceAll('colspan="11"','colspan="7"');
const groupStart=html.indexOf('    const groups = new Map();'),groupEnd=html.indexOf('\nfunction renderPeriodAction',groupStart);
html=html.slice(0,groupStart)+`    tbody.innerHTML = [...filtered].sort((left,right) =>
        left.date.localeCompare(right.date) || toDate(left.startAt)-toDate(right.startAt)
    ).map(schedule => {
        const person=guards.find(guard=>guard.id===schedule.userId);
        const start=toDate(schedule.startAt),end=toDate(schedule.endAt);
        const punch=time=>{
            if(!time)return '—';
            const dayOffset=Math.round((Date.parse(SchedulePeriod.toLocalDateString(time)+'T00:00:00Z')-Date.parse(schedule.date+'T00:00:00Z'))/86400000);
            return formatTime(time)+(dayOffset>0?' (+'+dayOffset+')':'');
        };
        const cancelled=schedule.approval_status==='cancelled';
        return \`<tr>
            <td><strong>\${escapeHtml(person?.name||schedule.guardName||'Personnel unavailable')}</strong>\${person?.role==='inspector'?'<div class="loc-cell-address">Inspector assignment · No attendance DTR</div>':''}</td>
            <td>\${escapeHtml(formatDate(schedule.date))}</td>
            <td class="schedule-dtr-time">\${escapeHtml(punch(start))}</td>
            <td class="schedule-dtr-time">\${escapeHtml(punch(end))}</td>
            <td>\${cancelled?'—':escapeHtml(formatDurationBetween(start,end))}</td>
            <td>\${formatLocationCell(schedule)}</td>
            <td class="schedule-period-actions">\${renderPeriodAction(schedule)}</td>
        </tr>\`;
    }).join('');
}
`+html.slice(groupEnd);
fs.writeFileSync(file,html);
const rosterFile='web/admin/js/shift-roster.js';let roster=fs.readFileSync(rosterFile,'utf8');
roster=roster.replace('Selected schedule · DTR preview','Selected guard shifts').replace('Planned shift and DTR columns','Planned guard shifts');
roster=roster.replace('DTR Time In','Scheduled IN').replace('DTR Time Out','Scheduled OUT');
roster=roster.replace('        const placement=SchedulePeriod.dtrPlacement(date.value,p[0],p[1]);\n','');
roster=roster.replace("const cell=(label,time)=>label ? `${escapeHtml(label)}<br><strong>${escapeHtml(formatTime(time))}</strong>` : '—';", "const cell=(time,nextDay=false)=>time ? `<strong>${escapeHtml(formatTime(time))}${nextDay?' (+1)':''}</strong>` : '—';");
roster=roster.replace('cell(placement?.timeIn.label,shift?.startAt)','cell(shift?.startAt)').replace('cell(placement?.timeOut.label,shift?.endAt)','cell(shift?.endAt,shift?.overnight)');
roster=roster.replace('Planned times only. Overtime columns stay blank for these roster shifts.','Planned times only. Actual Time In and Time Out appear on the Guard’s DTR.');
fs.writeFileSync(rosterFile,roster);
const cssFile='web/admin/css/dtr-scheduling.css';let css=fs.readFileSync(cssFile,'utf8').replace(/^.*\.roster-dtr-guide.*\n/gm,'').replace('min-width: 1150px','min-width: 900px');fs.writeFileSync(cssFile,css);
