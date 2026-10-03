(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.DtrReport = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const AGENCY = Object.freeze({
    name: 'TWENTY TWENTY SECURITY AGENCY, INC.',
    addressLine1: 'P. Hernaez Ext. (Fronting Villa Celia Subd.)',
    addressLine2: 'Brgy. Taculing, Bacolod City, Negros Occidental 6100',
    contact: 'Email: ttwenty2016@yahoo.com  |  Tel: (034) 466-5235  |  Mobile: 09056654294',
  });

  function pad(value) {
    return String(value).padStart(2, '0');
  }

  function toLocalDateString(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(date).reduce((result, part) => {
      result[part.type] = part.value;
      return result;
    }, {});
    return `${parts.year}-${parts.month}-${parts.day}`;
  }

  function asDate(value) {
    if (!value) return null;
    const date = typeof value.toDate === 'function' ? value.toDate() : new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function formatDate(value) {
    if (!value) return '-';
    const date = /^\d{4}-\d{2}-\d{2}$/.test(String(value))
      ? new Date(`${value}T00:00:00`)
      : asDate(value);
    return date && !Number.isNaN(date.getTime())
      ? date.toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
      : '-';
  }

  function formatTime(value) {
    const date = asDate(value);
    return date ? date.toLocaleTimeString('en-PH', {
      hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Manila',
    }) : '';
  }

  function dtrSectionForTime(value, isTimeOut) {
    const date = asDate(value);
    if (!date) return 'afternoon';
    const parts = new Intl.DateTimeFormat('en-US', {
      hour: '2-digit', minute: '2-digit', second: '2-digit',
      hourCycle: 'h23', timeZone: 'Asia/Manila',
    }).formatToParts(date).reduce((result, part) => {
      result[part.type] = part.value;
      return result;
    }, {});
    const seconds = Number(parts.hour) * 3600 + Number(parts.minute) * 60 + Number(parts.second);
    const morning = seconds < 12 * 3600 || (isTimeOut && seconds === 12 * 3600);
    return morning ? 'morning' : 'afternoon';
  }

  function needsTimeoutReview(session, now = new Date()) {
    if (asDate(session?.timeout_verified_at)) return false;
    const end = asDate(session?.scheduled_end_at);
    const timeOut = asDate(session?.clock_out_at);
    if (timeOut) return Boolean(end && timeOut > end);
    return Boolean(asDate(session?.clock_in_at) &&
      (session?.status === 'missed_timeout' || (end && end <= now)));
  }

  function sessionMinutes(session) {
    if (needsTimeoutReview(session)) return 0;
    const timeIn = asDate(session?.clock_in_at);
    const timeOut = asDate(session?.clock_out_at);
    if (!timeIn || !timeOut) return 0;
    const difference = timeOut - timeIn;
    return difference > 0 ? Math.floor(difference / 60000) : 0;
  }

  // Overtime is a subset of worked time, not an extra amount added to it.
  // Null means the attendance or scheduled end is insufficient to calculate it.
  function sessionOvertimeMinutes(session) {
    const timeIn=asDate(session?.clock_in_at), timeOut=asDate(session?.clock_out_at);
    const end=asDate(session?.scheduled_end_at);
    if (!timeIn || !timeOut || !end || needsTimeoutReview(session)) return null;
    const overtimeStart=Math.max(timeIn.getTime(),end.getTime());
    return Math.max(0,Math.floor((timeOut.getTime()-overtimeStart)/60000));
  }

  function formatDuration(minutes) {
    const safeMinutes = Math.max(0, Number(minutes) || 0);
    const hours = Math.floor(safeMinutes / 60);
    const remainder = safeMinutes % 60;
    if (!hours) return `${remainder} min`;
    if (!remainder) return hours === 1 ? '1 hr' : `${hours} hrs`;
    return `${hours}h ${remainder}m`;
  }

  function formatHours(minutes) {
    const safeMinutes = Math.max(0, Number(minutes) || 0);
    return `${Math.floor(safeMinutes / 60)}:${pad(safeMinutes % 60)}`;
  }

  function periodFromSelection(monthValue, cutoffValue) {
    const match = /^(\d{4})-(\d{2})$/.exec(String(monthValue || ''));
    if (!match || !['first', 'second'].includes(cutoffValue)) return null;
    const year = Number(match[1]);
    const month = Number(match[2]);
    if (month < 1 || month > 12) return null;
    const lastDay = new Date(year, month, 0).getDate();
    const startDay = cutoffValue === 'first' ? 1 : 16;
    const endDay = cutoffValue === 'first' ? 15 : lastDay;
    const prefix = `${year}-${pad(month)}`;
    const startDate = `${prefix}-${pad(startDay)}`;
    const endDate = `${prefix}-${pad(endDay)}`;
    return {
      month: prefix,
      cutoff: cutoffValue,
      startDate,
      endDate,
      label: `${formatDate(startDate)} - ${formatDate(endDate)}`,
    };
  }

  function selectionFromDate(value) {
    let dateString = '';
    if (/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) dateString = String(value);
    else dateString = toLocalDateString(value || new Date());
    if (!dateString) dateString = toLocalDateString(new Date());
    return {
      month: dateString.slice(0, 7),
      cutoff: Number(dateString.slice(8, 10)) <= 15 ? 'first' : 'second',
    };
  }

  function defaultSelection(sessions, fallbackDate) {
    const latestDutyDate = (Array.isArray(sessions) ? sessions : [])
      .map((session) => String(session?.duty_date || ''))
      .filter((value) => /^\d{4}-\d{2}-\d{2}$/.test(value))
      .sort()
      .pop();
    return selectionFromDate(latestDutyDate || fallbackDate || new Date());
  }

  function filterSessions(sessions, period) {
    if (!period) return [];
    return (Array.isArray(sessions) ? sessions : []).filter((session) => {
      const dutyDate = String(session?.duty_date || '');
      return dutyDate >= period.startDate && dutyDate <= period.endDate;
    });
  }

  function appendPunchCell(cells, key, value) {
    if (!value) return;
    // Keep every real punch if legacy or corrected sessions share a column.
    // A first-IN/last-OUT summary would hide the intervening recorded values.
    cells[key] = cells[key] ? `${cells[key]}\n${value}` : value;
  }

  function formatPunchTime(value, dutyDate) {
    const date = asDate(value);
    if (!date) return '';
    const actualDate = toLocalDateString(date);
    const dutyTime = Date.parse(`${dutyDate}T00:00:00Z`);
    const actualTime = Date.parse(`${actualDate}T00:00:00Z`);
    const dayOffset = Math.round((actualTime - dutyTime) / 86400000);
    const suffix = dayOffset === 1 ? ' (next day)' : dayOffset > 1 ? ` (${dayOffset} days later)` : dayOffset === -1 ? ' (previous day)' : dayOffset < -1 ? ` (${-dayOffset} days earlier)` : '';
    return `${formatTime(date)}${suffix}`;
  }

  function buildDayRow(dutyDate, sessions) {
    const cells = {
      morningIn: '', morningOut: '', afternoonIn: '', afternoonOut: '', overtimeIn: '', overtimeOut: '',
    };
    const ordered = [...sessions].sort((left, right) => {
      const leftDate = asDate(left.clock_in_at) || asDate(left.scheduled_start_at) || new Date(0);
      const rightDate = asDate(right.clock_in_at) || asDate(right.scheduled_start_at) || new Date(0);
      return leftDate - rightDate;
    });

    ordered.forEach((session) => {
      const timeIn = asDate(session.clock_in_at);
      const timeOut = asDate(session.clock_out_at);
      const declaredPeriod = String(session.dtr_period || 'auto').toLowerCase();
      const explicitPeriod = ['morning', 'afternoon', 'overtime'].includes(declaredPeriod)
        ? declaredPeriod : null;
      if (timeIn) {
        // An explicit schedule period owns both columns of its IN/OUT pair.
        // Existing continuous shifts keep their original AM/PM placement.
        // The values are always real attendance, never planned/lunch punches.
        const scheduledStart = asDate(session.scheduled_start_at);
        const section = explicitPeriod || dtrSectionForTime(scheduledStart || timeIn, false);
        const key = `${section}In`;
        appendPunchCell(cells, key, formatPunchTime(timeIn, dutyDate));
      }
      if (timeOut) {
        const scheduledEnd = asDate(session.scheduled_end_at);
        const section = explicitPeriod || dtrSectionForTime(scheduledEnd || timeOut, true);
        const key = `${section}Out`;
        appendPunchCell(cells, key, formatPunchTime(timeOut, dutyDate));
      }
    });

    const totalMinutes = ordered.reduce((total, session) => total + sessionMinutes(session), 0);
    return {
      dutyDate,
      day: String(Number(dutyDate.slice(8, 10))),
      ...cells,
      totalMinutes,
      totalHours: totalMinutes ? formatHours(totalMinutes) : '',
      completed: ordered.length > 0 && ordered.every((session) => Boolean(session.clock_out_at) && !needsTimeoutReview(session)),
      sessionCount: ordered.length,
    };
  }

  function enumerateDates(startDate, endDate) {
    const dates = [];
    const cursor = new Date(`${startDate}T00:00:00Z`);
    const last = new Date(`${endDate}T00:00:00Z`);
    while (!Number.isNaN(cursor.getTime()) && cursor <= last) {
      dates.push(cursor.toISOString().slice(0, 10));
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    return dates;
  }

  function shiftEntry(dutyDate, session) {
    const base = { dutyDate, day: String(Number(dutyDate.slice(8, 10))),
      assignedShift: '', actualIn: '', actualOut: '', overtimeHours: '', workedHours: '', status: '' };
    if (!session) return base;
    const start=asDate(session.scheduled_start_at), end=asDate(session.scheduled_end_at);
    const timeIn=asDate(session.clock_in_at), timeOut=asDate(session.clock_out_at);
    const review=needsTimeoutReview(session);
    let status=review ? (timeOut?'Late Time Out · verification pending':'Missing Time Out · verification pending')
      : timeIn && timeOut ? (session.timeout_verified_at?'Verified':'Completed')
      : timeIn ? 'On duty' : 'No punches recorded';
    if (!review && session.clock_out_location_status==='unavailable') status+=' · GPS unavailable';
    if (!review && session.clock_out_location_status==='outside_post') status+=' · Outside post';
    const planned=start&&end ? `${formatPunchTime(start,dutyDate)} – ${formatPunchTime(end,dutyDate)}\n${formatDuration(Math.max(0,Math.round((end-start)/60000)))} scheduled` : 'Schedule unavailable';
    const location=String(session.location_label||session.locationLabel||'').trim();
    return { ...base,
      assignedShift: planned+(session.dtr_period==='overtime'?'\nOvertime assignment':'')+(location?'\n'+location:''),
      actualIn: timeIn?formatPunchTime(timeIn,dutyDate):'',
      actualOut: timeOut && !(session.overtime_requested === true && review)?formatPunchTime(timeOut,dutyDate):'',
      overtimeHours: sessionOvertimeMinutes(session)===null?'':formatHours(sessionOvertimeMinutes(session)),
      workedHours: timeIn&&timeOut&&!review?formatHours(sessionMinutes(session)):'',
      status,
    };
  }

  function buildReport(sessions, period, fallbackDetachment) {
    if (!period) throw new Error('A valid DTR cutoff period is required.');
    const included = filterSessions(sessions, period);
    const byDate = included.reduce((groups, session) => {
      const dutyDate = String(session.duty_date || '');
      if (!groups[dutyDate]) groups[dutyDate] = [];
      groups[dutyDate].push(session);
      return groups;
    }, {});
    const rows = enumerateDates(period.startDate, period.endDate)
      .map((dutyDate) => buildDayRow(dutyDate, byDate[dutyDate] || []));
    const locations = [...new Set(included
      .map((session) => String(session.location_label || session.locationLabel || '').trim())
      .filter(Boolean))];
    return {
      period,
      sessions: included,
      rows,
      shiftRows: enumerateDates(period.startDate,period.endDate).flatMap(dutyDate => {
        const sessions=[...(byDate[dutyDate]||[])].sort((a,b)=>(asDate(a.scheduled_start_at)||asDate(a.clock_in_at)||0)-(asDate(b.scheduled_start_at)||asDate(b.clock_in_at)||0));
        return sessions.length?sessions.map(session=>shiftEntry(dutyDate,session)):[shiftEntry(dutyDate,null)];
      }),
      completedDays: rows.filter((row) => row.completed).length,
      totalMinutes: rows.reduce((total, row) => total + row.totalMinutes, 0),
      totalOvertimeMinutes: included.reduce((total,session)=>total+(sessionOvertimeMinutes(session)||0),0),
      reviewNotes: included.flatMap((session) => {
        const status = session.overtime_requested === true && needsTimeoutReview(session)
          ? 'Overtime Time Out awaiting Operations Head approval; hours excluded.'
          : needsTimeoutReview(session)
          ? session.clock_out_at ? 'Late Time Out - awaiting Operations Head verification; hours excluded.'
            : 'Missing Time Out - awaiting Operations Head verification; hours excluded.'
          : session.timeout_verified_at ? 'Time Out verified by Operations Head.'
          : session.clock_out_location_status === 'unavailable' ? 'Time Out recorded; GPS unavailable.'
          : session.clock_out_location_status === 'outside_post' ? 'Time Out recorded outside the assigned post; review location.' : '';
        return status ? [{ dutyDate: session.duty_date, status }] : [];
      }),
      detachment: locations.length === 1
        ? locations[0]
        : locations.length > 1 ? 'Multiple deployment sites' : (fallbackDetachment || '-'),
    };
  }

  function accountName(account) {
    const firstName = account?.firstName || account?.first_name || '';
    const middle = account?.middleInitial || account?.middle_initial || '';
    const lastName = account?.lastName || account?.last_name || '';
    return [firstName, middle ? `${middle}.` : '', lastName].filter(Boolean).join(' ').trim()
      || account?.name || account?.username || 'Guard';
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function previewCell(value) {
    const text = String(value ?? '').trim();
    return text ? escapeHtml(text).replace(/\n/g, '<br>') : '<span class="dtr-sheet-blank" aria-hidden="true">&nbsp;</span>';
  }

  function renderPreview(options) {
    const report = buildReport(options?.sessions, options?.period, options?.detachment);
    const logoUrl = String(options?.logoUrl || '').trim();
    const rows = report.shiftRows.map((row) => `<tr>
      <th scope="row">${previewCell(row.day)}</th>
      <td>${previewCell(row.assignedShift)}</td>
      <td>${previewCell(row.actualIn)}</td>
      <td>${previewCell(row.actualOut)}</td>
      <td class="dtr-sheet-total-cell">${previewCell(row.overtimeHours)}</td>
      <td class="dtr-sheet-total-cell">${previewCell(row.workedHours)}</td>
    </tr>`).join('');

    return `<article class="dtr-sheet-preview" aria-label="Daily Time Record preview">
      <header class="dtr-sheet-header">
        <div class="dtr-sheet-logo-cell">
          ${logoUrl ? `<img class="dtr-sheet-logo" src="${escapeHtml(logoUrl)}" alt="Twenty Twenty Security Agency logo">` : ''}
        </div>
        <div class="dtr-sheet-agency">
          <h2>${escapeHtml(AGENCY.name)}</h2>
          <p>${escapeHtml(AGENCY.addressLine1)}</p>
          <p>${escapeHtml(AGENCY.addressLine2)}</p>
          <p>${escapeHtml(AGENCY.contact)}</p>
        </div>
        <div class="dtr-sheet-logo-spacer" aria-hidden="true"></div>
        <h3>DAILY TIME RECORD · GUARD SHIFTS</h3>
      </header>

      <div class="dtr-sheet-meta">
        <div><strong>Guard Name:</strong><span>${escapeHtml(accountName(options?.account))}</span></div>
        <div><strong>Detachment:</strong><span>${escapeHtml(report.detachment)}</span></div>
        <div><strong>Period Covered:</strong><span>${escapeHtml(report.period.label)}</span></div>
      </div>

      <div class="dtr-sheet-table-scroll" tabindex="0" aria-label="Scrollable Daily Time Record table">
        <table class="dtr-sheet-table">
          <caption class="visually-hidden">Attendance entries for ${escapeHtml(report.period.label)}</caption>
          <thead>
            <tr>
              <th scope="col">Duty<br>Date</th>
              <th scope="col">Assigned shift / Site</th>
              <th scope="col">Actual<br>Time In</th>
              <th scope="col">Actual<br>Time Out</th>
              <th scope="col">Total Overtime<br>Hours</th>
              <th scope="col">Total Worked<br>Hours</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      </div>

      ${report.reviewNotes.length ? `<div class="dtr-sheet-footnote" aria-label="Attendance verification notes">${report.reviewNotes.map(note => `<p>${escapeHtml(formatDate(note.dutyDate))}: ${escapeHtml(note.status)}</p>`).join('')}</div>` : ''}
      <p class="dtr-sheet-certification">I hereby certify that the above record is true and correct.</p>
      <div class="dtr-sheet-totals">
        <p><strong>NO. OF DAYS</strong><span>${report.completedDays}</span></p>
        <p><strong>TOTAL OVERTIME HOURS</strong><span>${escapeHtml(formatHours(report.totalOvertimeMinutes))}</span></p>
        <p><strong>TOTAL WORKED HOURS</strong><span>${escapeHtml(formatHours(report.totalMinutes))}</span></p>
      </div>
      <div class="dtr-sheet-signatures">
        <div><span></span><p>Approved By</p></div>
        <div><span></span><p>Guard Signature</p></div>
      </div>
      <footer class="dtr-sheet-footnote">
        Entries are recorded or Operations Head-verified Time In/Out values. Overnight times are marked “next day”.<br>
        Overtime is verified time worked after the scheduled end and is already included in Total Worked Hours. Values use H:MM.<br>
        Blank overtime means attendance or the scheduled end is unavailable. Recorded hours do not calculate overtime pay.
      </footer>
    </article>`;
  }

  async function imageDataUrl(url) {
    if (!url || typeof fetch !== 'function' || typeof FileReader === 'undefined') return null;
    try {
      const response = await fetch(url);
      if (!response.ok) return null;
      const blob = await response.blob();
      return await new Promise((resolve) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => resolve(null);
        reader.readAsDataURL(blob);
      });
    } catch (_) {
      return null;
    }
  }

  async function generatePdf(options) {
    const JsPDF = options?.jsPDF;
    if (typeof JsPDF !== 'function') throw new Error('The PDF library is unavailable.');
    const report = buildReport(options.sessions, options.period, options.detachment);
    const doc = new JsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
    if (typeof doc.autoTable !== 'function') throw new Error('The DTR table library is unavailable.');

    const pageWidth = doc.internal.pageSize.getWidth();
    const center = pageWidth / 2;
    const logo = await imageDataUrl(options.logoUrl);
    if (logo) {
      try { doc.addImage(logo, 'PNG', 14, 9, 22, 22, undefined, 'FAST'); } catch (_) { /* Header remains usable without a logo. */ }
    }

    doc.setTextColor(25, 25, 25);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(12);
    doc.text(AGENCY.name, center, 12, { align: 'center' });
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.text(AGENCY.addressLine1, center, 17, { align: 'center' });
    doc.text(AGENCY.addressLine2, center, 21, { align: 'center' });
    doc.text(AGENCY.contact, center, 25, { align: 'center' });
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.text('DAILY TIME RECORD - GUARD SHIFTS', center, 34, { align: 'center' });

    doc.setFontSize(8.5);
    doc.setFont('helvetica', 'bold');
    doc.text('Guard Name:', 14, 43);
    doc.text('Detachment:', 14, 49);
    doc.text('Period Covered:', 14, 55);
    doc.setFont('helvetica', 'normal');
    doc.text(accountName(options.account), 39, 43);
    doc.text(report.detachment, 39, 49);
    doc.text(report.period.label, 39, 55);

    const body = report.shiftRows.map((row) => [
      row.day,
      row.assignedShift,
      row.actualIn,
      row.actualOut,
      row.overtimeHours,
      row.workedHours,
    ]);
    doc.autoTable({
      startY: 60,
      theme: 'grid',
      head: [['Duty\ndate','Assigned shift / Site','Actual\nTime In','Actual\nTime Out','Total overtime\nhours','Total worked\nhours']],
      body,
      styles: {
        font: 'helvetica', fontSize: 7.2, cellPadding: 1.7,
        textColor: [25, 25, 25], lineColor: [90, 90, 90], lineWidth: 0.15,
        halign: 'center', valign: 'middle', minCellHeight: 6.5,
      },
      headStyles: { fillColor: [236, 236, 236], textColor: [20, 20, 20], fontStyle: 'bold' },
      alternateRowStyles: { fillColor: [250, 250, 250] },
      columnStyles: { 0:{cellWidth:12},1:{cellWidth:58,halign:'left'},2:{cellWidth:28},3:{cellWidth:28},4:{cellWidth:28},5:{cellWidth:28} },
      rowPageBreak: 'avoid',
      margin: { left: 14, right: 14 },
    });

    if (report.reviewNotes.length) {
      doc.autoTable({
        startY: (doc.lastAutoTable?.finalY || 170) + 4,
        head: [['Duty date', 'Attendance verification']],
        body: report.reviewNotes.map(note => [formatDate(note.dutyDate), note.status]),
        theme: 'plain', margin: { left: 14, right: 14 },
        styles: { font: 'helvetica', fontSize: 7, cellPadding: 1.2 },
      });
    }
    let footerY = (doc.lastAutoTable?.finalY || 170) + 9;
    if (footerY > 224) {
      doc.addPage();
      footerY = 20;
    }
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.text('I hereby certify that the above record is true and correct.', 14, footerY);
    doc.setFont('helvetica', 'bold');
    doc.text(`NO. OF DAYS: ${report.completedDays}`, 14, footerY + 10);
    doc.text(`TOTAL OVERTIME HOURS: ${formatHours(report.totalOvertimeMinutes)}`, 14, footerY + 16);
    doc.text(`TOTAL WORKED HOURS: ${formatHours(report.totalMinutes)}`, 112, footerY + 16);
    doc.setDrawColor(70, 70, 70);
    doc.line(20, footerY + 28, 80, footerY + 28);
    doc.line(125, footerY + 28, 188, footerY + 28);
    doc.setFont('helvetica', 'normal');
    doc.text('Approved By', 50, footerY + 33, { align: 'center' });
    doc.text('Guard Signature', 156.5, footerY + 33, { align: 'center' });
    doc.setFontSize(6.5);
    doc.setTextColor(100, 100, 100);
    doc.text('Entries are recorded or Operations Head-verified Time In/Out values; overnight times are marked "next day".', 14, footerY + 42);
    doc.text('Overtime is verified time after the scheduled end, already included in Total Worked Hours. Values use H:MM.', 14, footerY + 46);
    doc.text('Blank overtime means attendance or scheduled end is unavailable. Recorded hours do not calculate overtime pay.', 14, footerY + 50);
    doc.text(`Generated ${new Date().toLocaleString('en-PH')}`, 14, footerY + 55);

    const safeName = accountName(options.account).replace(/[^a-z0-9_-]+/gi, '_') || 'Guard';
    const filename = `DTR_${safeName}_${report.period.startDate}_${report.period.endDate}.pdf`;
    doc.save(filename);
    return { filename, report };
  }

  return Object.freeze({
    AGENCY,
    accountName,
    buildReport,
    defaultSelection,
    filterSessions,
    formatDate,
    formatDuration,
    formatHours,
    formatTime,
    generatePdf,
    needsTimeoutReview,
    periodFromSelection,
    renderPreview,
    selectionFromDate,
    sessionMinutes,
    sessionOvertimeMinutes,
  });
});
