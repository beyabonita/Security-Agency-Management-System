(() => {
  'use strict';
  // Purge any stale contract notice or override elements
  document.getElementById('contractShiftNotice')?.remove();
  document.getElementById('overrideContractShiftsBtn')?.remove();

  const setup=document.getElementById('rosterSetup'), date=document.getElementById('rosterDate');
  const site=document.getElementById('rosterSite'), slots=document.getElementById('rosterGuards');
  const siteFilter=document.getElementById('rosterSiteFilter'), siteFilterClear=document.getElementById('rosterSiteFilterClear');
  const combobox=document.getElementById('rosterCombobox'), siteMenu=document.getElementById('rosterSiteMenu'), comboboxToggle=document.getElementById('rosterComboboxToggle');
  const preview=document.getElementById('rosterPreview'), assigned=document.getElementById('assignedRoster');
  const button=document.getElementById('saveRoster');
  const weeklyButton=document.getElementById('saveWeeklyRoster');

  function parseLocalDate(str) {
    if (!str) return new Date();
    const parts = str.split('-').map(Number);
    return new Date(parts[0], parts[1] - 1, parts[2]);
  }
  function formatDateISO(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + day;
  }
  function getWeekRange(dateStr) {
    const d = parseLocalDate(dateStr || todayDateString());
    const day = d.getDay();
    const diffToMonday = day === 0 ? -6 : 1 - day;
    const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() + diffToMonday);
    const days = [];
    for (let i = 0; i < 7; i++) {
      const cur = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
      days.push(formatDateISO(cur));
    }
    return {
      start: days[0],
      end: days[6],
      days: days
    };
  }
  function updateWeekRangePill() {
    const pill = document.getElementById('rosterWeekRangePill');
    if (!pill || !date) return;
    const range = getWeekRange(date.value);
    pill.textContent = `📅 Target Week: ${formatDate(range.start)} – ${formatDate(range.end)} (Mon–Sun · 7 Days)`;
  }
  function updateStationedGuardsNotice() {
    const noticeEl = document.getElementById('stationedGuardsNotice');
    if (!noticeEl) return;
    if (!site || !site.value) {
      noticeEl.textContent = '';
      return;
    }
    const activeUserGuards = (window.guards || guards || []).filter(g => g.active && g.role === 'user');
    const stationed = activeUserGuards.filter(g => (g.assignedLocationId || g.assigned_location_id) === site.value);
    const locObj = (window.locations || locations || []).find(l => l.id === site.value);
    const siteName = locObj?.label || 'this client';
    if (stationed.length === 0) {
      noticeEl.textContent = '';
    } else {
      noticeEl.textContent = `${stationed.length} ${stationed.length === 1 ? 'guard is' : 'guards are'} stationed at ${siteName}.`;
    }
  }
  function updateCutoffNotice() {
    const pill = document.getElementById('rosterDateCutoffPill');
    if (!pill || !date || !date.value) return;
    const cutoff = SchedulePeriod.dtrPeriodForDate(date.value);
    if (!cutoff) {
      pill.textContent = '';
      return;
    }
    const dStart = new Date(date.value + 'T00:00:00');
    const dEnd = new Date(cutoff.endDate + 'T00:00:00');
    const startMonth = dStart.toLocaleDateString("en-US", { month: "short" });
    const endMonth = dEnd.toLocaleDateString("en-US", { month: "short" });
    const startDay = dStart.getDate();
    const endDay = dEnd.getDate();
    const endYear = dEnd.getFullYear();
    pill.textContent = `${startMonth} ${startDay} – ${endMonth} ${endDay}, ${endYear}`;
  }
  let saving=false,setupSaving=false,setupLoading=false;
  let savedSetups=[];
  let editingSetup=null,setupRevision=0,setupsLoaded=false;
  let customRosterShifts=null;
  const customSetup=()=>savedSetups.find(item=>item.id===setup.value);
  const periods=()=>customRosterShifts ? RosterSetup.periods(customRosterShifts) : (customSetup()?RosterSetup.periods(customSetup().shifts):[]);
  const selected=()=>[...slots.querySelectorAll('select')].map(s=>s.value);
  const available=(day,p,now=new Date())=>SchedulePeriod.calculate(day,p[0],p[1])?.endAt>now;
  function availability(){
    const shifts=periods(),now=new Date();let remaining=0;
    slots.querySelectorAll('select').forEach((select,i)=>{
      const ended=!available(date.value,shifts[i],now);
      select.disabled=saving||ended;
      const statusEl=select.parentElement.querySelector('.roster-slot-status');
      if (ended) {
        statusEl.textContent='Shift ended';
        statusEl.style.color='';
      } else if (statusEl && !statusEl.textContent.includes('Double shift')) {
        statusEl.textContent='';
        statusEl.style.color='';
      }
      if(!ended)remaining++;
    });
    button.textContent=remaining===shifts.length?'Assign this day only':'Assign remaining shifts today';
    if (weeklyButton) {
      weeklyButton.disabled = saving || !site.value;
    }
  }
  const currentName=id=>guards.find(g=>g.id===id)?.name || 'Select a Guard';
  function summary(){
    updateStationedGuardsNotice();
    updateCutoffNotice();
    availability();
    managementControls();
    syncGuardSelections();
    if(!site.value){
      preview.innerHTML='';
      assigned.innerHTML='';
      return;
    }
    if(!customSetup() && !customRosterShifts){
      preview.textContent=setupsLoaded?'No shifting schedule available for this site.':'Loading schedule…';
      assigned.textContent='';return;
    }
    const ids=selected();
    const cutoff=SchedulePeriod.dtrPeriodForDate(date.value);
    const week=getWeekRange(date.value);
    preview.innerHTML='<div class="roster-preview-header d-flex justify-content-between align-items-center flex-wrap gap-2 mb-1">'+
      '<p class="mb-0"><strong>Selected guard shifts (Weekly / Daily)</strong></p>'+
      '</div>'+
      `<p class="mb-2 text-muted small">${cutoff ? `Target Week: <strong>${escapeHtml(formatDate(week.start))} – ${escapeHtml(formatDate(week.end))}</strong> (7 Days: Mon–Sun) · Selected Date: ${escapeHtml(formatDate(date.value))} · DTR cut-off: ${escapeHtml(cutoff.label)}` : 'Choose a valid schedule date.'}</p>`+
      '<div class="roster-dtr-scroll" tabindex="0" aria-label="Planned guard shifts"><table class="roster-dtr-preview"><thead><tr><th scope="col">Shift and Guard</th><th scope="col">Scheduled IN</th><th scope="col">Scheduled OUT</th><th scope="col">Planned hours</th></tr></thead><tbody>'+
      periods().map((p,i)=>{
        const shift=SchedulePeriod.calculate(date.value,p[0],p[1]);
        const cell=(time,nextDay=false)=>time ? `<strong>${escapeHtml(formatTime(time))}${nextDay?' <span class="badge-next-day">(next day)</span>':''}</strong>` : '—';
        return `<tr><td>${p[2]} — ${available(date.value,p)?escapeHtml(currentName(ids[i])):'Shift ended (not assigned)'}</td><td>${cell(shift?.startAt)}</td><td>${cell(shift?.endAt,shift?.overnight)}</td><td>${shift ? escapeHtml(SchedulePeriod.formatDuration(shift.durationMinutes)) : '—'}</td></tr>`;
      }).join('')+'</tbody></table></div>';
    const rows=schedules.filter(s=>(s.locationId||s.location_id)===site.value && s.date===date.value && s.approval_status!=='cancelled');
    assigned.innerHTML='<h3 class="h6 mt-3">Guards already assigned to this schedule</h3>'+periods().map(p=>{
      const plan=SchedulePeriod.buildDutyPlan(date.value,[{period:'auto',start_time:p[0],end_time:p[1],next_day:false}]);
      const names=plan.error ? [] : rows.filter(s=>new Date(s.startAt).getTime()===plan.periods[0].startAt.getTime() && new Date(s.endAt).getTime()===plan.periods[0].endAt.getTime())
        .map(s=>guards.find(g=>g.id===s.userId)?.name||s.guardName||'Guard');
      return `<p>${p[2]} — ${names.length ? names.map(escapeHtml).join(', ') : 'Unassigned'}</p>`;
    }).join('');
  }
  function updateSiteOptions(selectedId){
    const current = selectedId !== undefined ? selectedId : site.value;
    let html = '<option value="">Select location</option>';
    html += locations.map(l => `<option value="${escapeHtml(l.id)}">${escapeHtml(l.label)}</option>`).join('');
    if (current && !locations.some(l => l.id === current)) {
      html += `<option value="${escapeHtml(current)}" selected>${escapeHtml(current)}</option>`;
    }
    site.innerHTML = html;
    site.value = current;

    const activeObj = locations.find(l => l.id === current);
    if (siteFilter) {
      siteFilter.value = activeObj ? activeObj.label : '';
    }
    if (siteFilterClear) {
      siteFilterClear.hidden = !current;
    }
    if (siteMenu && !siteMenu.hidden) {
      renderSiteMenuItems();
    }
  }

  function openSiteMenu(){
    if (!siteMenu) return;
    siteMenu.hidden = false;
    combobox?.classList.add('is-open');
    siteFilter?.setAttribute('aria-expanded', 'true');
    renderSiteMenuItems();
  }

  function closeSiteMenu(){
    if (!siteMenu) return;
    siteMenu.hidden = true;
    combobox?.classList.remove('is-open');
    siteFilter?.setAttribute('aria-expanded', 'false');
    const activeObj = locations.find(l => l.id === site.value);
    if (siteFilter) {
      siteFilter.value = activeObj ? activeObj.label : '';
    }
    if (siteFilterClear) {
      siteFilterClear.hidden = !site.value;
    }
  }

  function renderSiteMenuItems(){
    if (!siteMenu) return;
    const term = siteFilter ? siteFilter.value.trim().toLowerCase() : '';
    const current = site.value;
    const activeObj = locations.find(l => l.id === current);
    const isExactMatch = activeObj && activeObj.label.toLowerCase() === term;
    const filtered = (!term || isExactMatch)
      ? locations
      : locations.filter(l => (l.label || '').toLowerCase().includes(term) || (l.address || '').toLowerCase().includes(term));

    if (!filtered.length) {
      siteMenu.innerHTML = '<div class="roster-combobox-empty">No deployment sites match</div>';
      return;
    }

    siteMenu.innerHTML = filtered.map(l => {
      const isSel = l.id === current;
      return `<div class="roster-combobox-item${isSel ? ' is-selected' : ''}" data-id="${escapeHtml(l.id)}" data-label="${escapeHtml(l.label)}" role="option" aria-selected="${isSel}">` +
        `<span class="roster-combobox-item-label">${escapeHtml(l.label)}</span>` +
        (l.address ? `<span class="roster-combobox-item-address">${escapeHtml(l.address)}</span>` : '') +
        `</div>`;
    }).join('');
  }

  function syncGuardSelections(){
    const selects = [...slots.querySelectorAll('select')];
    const currentValues = selects.map(s => s.value);
    const dateRows = schedules.filter(s => s.date === date.value && s.approval_status !== 'cancelled');
    const scheduledGuardMap = new Map();
    dateRows.forEach(s => {
      const gId = s.userId;
      if (gId) scheduledGuardMap.set(gId, s.locationLabel || 'another deployment');
    });
    const siteRows = schedules.filter(s => (s.locationId || s.location_id) === site.value && s.date === date.value && s.approval_status !== 'cancelled');
    const assignedAtSiteGuards = new Set(siteRows.map(s => s.userId));

    selects.forEach((select, slotIdx) => {
      [...select.options].forEach(opt => {
        if (!opt.value) return;
        const origName = guards.find(g => g.id === opt.value)?.name || opt.value;
        const otherSlotIdx = currentValues.findIndex((val, i) => i !== slotIdx && val === opt.value);
        if (otherSlotIdx !== -1) {
          opt.textContent = `${origName} — (Selected in Shift ${otherSlotIdx + 1})`;
        } else if (site.value && assignedAtSiteGuards.has(opt.value)) {
          opt.textContent = `${origName} — (Already assigned at this site)`;
        } else if (scheduledGuardMap.has(opt.value)) {
          opt.textContent = `${origName} — (Already on duty today)`;
        } else {
          opt.textContent = origName;
        }
      });
    });
  }

  window.renderShiftRoster=()=>{
    const ids=selected(),oldSite=site.value;
    updateSiteOptions(oldSite);
    if (!site.value) {
      slots.innerHTML = '<div class="text-muted p-4 text-center w-100" style="grid-column: 1 / -1; background:var(--sl-surface-muted, #f8fafc); border:1px dashed var(--sl-line, #cbd5e1); border-radius:8px; font-size:0.875rem;"><span class="material-symbols-rounded align-middle me-1 text-danger" style="font-size:20px;">business</span> Please select a <strong>Deployment site</strong> above to load its contracted shift schedule.</div>';
      summary();
      return;
    }
    const activeUserGuards = guards.filter(g => g.active && g.role === 'user');
    const stationedGuards = activeUserGuards.filter(g => (g.assignedLocationId || g.assigned_location_id) === site.value);
    const candidateGuards = stationedGuards.length ? stationedGuards : activeUserGuards;
    const sortedGuards = [...candidateGuards].sort((a, b) => (a.name || '').localeCompare(b.name || ''));
    const optionsHtml = sortedGuards.map(g => `<option value="${escapeHtml(g.id)}">${escapeHtml(g.name)}</option>`).join('');

    slots.innerHTML = periods().map((p, i) => {
      let shiftPrefix = '';
      if (periods().length === 2) {
        shiftPrefix = i === 0 ? 'Day shift · ' : 'Night shift · ';
      } else if (periods().length === 3) {
        shiftPrefix = i === 0 ? 'First shift · ' : i === 1 ? 'Second shift · ' : 'Third shift · ';
      }
      const labelText = `${shiftPrefix}${p[2]}`;
      return `
      <div class="schedule-field">
        <label class="form-label fw-semibold" for="rosterGuard${i}">${escapeHtml(labelText)} <span class="req-star" aria-hidden="true">*</span></label>
        <select id="rosterGuard${i}" class="form-select" aria-required="true" aria-describedby="rosterStatus${i}">
          <option value="">Select guard</option>
          ${optionsHtml}
        </select>
        <p id="rosterStatus${i}" class="form-hint roster-slot-status"></p>
      </div>
    `;
    }).join('');
    slots.querySelectorAll('select').forEach((s,i)=>{
      s.value=ids[i]||'';
      s.disabled=saving;
      s.addEventListener('change',()=>{
        const statusEl = s.parentElement?.querySelector('.roster-slot-status');
        if (s.value) {
          const allSelects = [...slots.querySelectorAll('select')];
          const otherSelect = allSelects.find((other, otherIdx) => otherIdx !== i && other.value === s.value);
          const siteRows = schedules.filter(row => (row.locationId || row.location_id) === site.value && row.date === date.value && row.approval_status !== 'cancelled');
          const isAssignedAtSite = site.value && siteRows.some(row => row.userId === s.value);

          if (otherSelect) {
            const otherIdx = allSelects.indexOf(otherSelect);
            const guardName = currentName(s.value);
            appDialog.toast(`${guardName} is already assigned to Shift ${otherIdx + 1}. A guard cannot be put on double shifts.`, { tone: 'warning' });
            s.value = '';
            if (statusEl) {
              statusEl.textContent = `Double shift prevented: already in Shift ${otherIdx + 1}`;
              statusEl.style.color = 'var(--sl-danger, #b02a37)';
            }
          } else if (isAssignedAtSite) {
            const guardName = currentName(s.value);
            appDialog.toast(`${guardName} is already assigned to duty at this site on this date. Double shifts are not allowed.`, { tone: 'warning' });
            s.value = '';
            if (statusEl) {
              statusEl.textContent = 'Double shift prevented: already assigned at this site';
              statusEl.style.color = 'var(--sl-danger, #b02a37)';
            }
          } else if (statusEl && statusEl.textContent.includes('Double shift')) {
            statusEl.textContent = '';
            statusEl.style.color = '';
          }
        } else if (statusEl && statusEl.textContent.includes('Double shift')) {
          statusEl.textContent = '';
          statusEl.style.color = '';
        }
        summary();
      });
    });
    summary();
  };
  date.min=todayDateString();
  const initNow = new Date();
  if (initNow.getDay() === 0) {
    const nextMon = new Date(initNow.getFullYear(), initNow.getMonth(), initNow.getDate() + 1);
    date.value = formatDateISO(nextMon);
  } else {
    date.value = todayDateString();
  }
  updateWeekRangePill();

  setup.addEventListener('change',()=>{
    if(editingSetup)resetEditor();
    customRosterShifts=null;
    window.renderShiftRoster();
  });
  date.addEventListener('change', () => {
    updateWeekRangePill();
    summary();
  });
  date.addEventListener('input', () => {
    updateWeekRangePill();
    summary();
  });
  document.getElementById('weeklyRestDay')?.addEventListener('change', summary);

  const thisWeekBtn = document.getElementById('rosterThisWeekBtn');
  if (thisWeekBtn) {
    thisWeekBtn.addEventListener('click', () => {
      const n = new Date();
      const currentMon = new Date(n.getFullYear(), n.getMonth(), n.getDate() + (n.getDay() === 0 ? -6 : 1 - n.getDay()));
      date.value = formatDateISO(currentMon);
      updateWeekRangePill();
      summary();
    });
  }

  const nextWeekBtn = document.getElementById('rosterNextWeekBtn');
  if (nextWeekBtn) {
    nextWeekBtn.addEventListener('click', () => {
      const n = new Date();
      const currentMon = new Date(n.getFullYear(), n.getMonth(), n.getDate() + (n.getDay() === 0 ? -6 : 1 - n.getDay()));
      const nextMon = new Date(currentMon.getFullYear(), currentMon.getMonth(), currentMon.getDate() + 7);
      date.value = formatDateISO(nextMon);
      updateWeekRangePill();
      summary();
      appDialog.toast(`Selected next week (${formatDate(formatDateISO(nextMon))}). Auto-assign guards and click "Assign for whole week".`, { tone: 'info' });
    });
  }

  let activeContractInfo = null;

  function updateContractNotice(info) {
    activeContractInfo = info;
    document.getElementById('contractShiftNotice')?.remove();
    document.getElementById('overrideContractShiftsBtn')?.remove();
  }

  function formatTime12Hour(val) {
    if (!val) return "";
    const parts = String(val).split(":");
    let h = parseInt(parts[0], 10);
    const m = parts[1] || "00";
    if (isNaN(h)) return val;
    const suffix = h >= 12 ? "PM" : "AM";
    const hour12 = h % 12 || 12;
    return `${hour12}:${m} ${suffix}`;
  }

  function applySiteContractShifts(siteId) {
    if (!siteId) {
      updateContractNotice(null);
      return;
    }
    const loc = locations.find(l => l.id === siteId);
    if (!loc) {
      updateContractNotice(null);
      return;
    }

    let model = loc.shift_model || loc.shiftModel || '2_shifts_12h';
    if (model === '2_shifts_12h_07') model = '2_shifts_12h';
    let customHours = loc.custom_shift_hours || loc.customShiftHours;

    // If customHours was previously sliced to 2 shifts of 8 hours (06:00-14:00 & 14:00-22:00), restore the 3rd shift (22:00-06:00)
    if (Array.isArray(customHours) && customHours.length === 2) {
      const s0 = customHours[0];
      const s1 = customHours[1];
      if (s0?.start_time === '06:00' && s0?.end_time === '14:00' && s1?.start_time === '14:00' && s1?.end_time === '22:00') {
        model = '3_shifts_8h';
        loc.shift_model = '3_shifts_8h';
        loc.shiftModel = '3_shifts_8h';
        customHours = [
          { start_time: '06:00', end_time: '14:00', label: s0.label || 'First Shift' },
          { start_time: '14:00', end_time: '22:00', label: s1.label || 'Second Shift' },
          { start_time: '22:00', end_time: '06:00', label: 'Third Shift' }
        ];
        loc.custom_shift_hours = customHours;
        loc.customShiftHours = customHours;
      }
    }

    // Auto-detect 3 shifts or 1 shift if customHours array has 3 or 1 items
    if (Array.isArray(customHours)) {
      if (customHours.length === 3) {
        model = '3_shifts_8h';
      } else if (customHours.length === 1) {
        model = '1_shift_8h';
      }
    }

    let targetShifts = null;
    let modelLabel = '';

    if (model === '1_shift_8h') {
      const s0 = (Array.isArray(customHours) && customHours.length) ? customHours[0] : null;
      if (s0 && s0.start_time && s0.end_time) {
        targetShifts = [{ start_time: s0.start_time, end_time: s0.end_time, label: s0.label || 'Day Shift' }];
        modelLabel = '1 Day Shift (' + formatTime12Hour(s0.start_time) + '–' + formatTime12Hour(s0.end_time) + ')';
      } else {
        targetShifts = [{ start_time: '08:00', end_time: '17:00', label: 'Day Shift' }];
        modelLabel = '1 Day Shift (8:00 AM–5:00 PM)';
      }
    } else if (model === '3_shifts_8h') {
      if (Array.isArray(customHours) && customHours.length >= 3 && customHours.slice(0, 3).every(s => s.start_time && s.end_time)) {
        targetShifts = customHours.slice(0, 3).map((s, idx) => ({ start_time: s.start_time, end_time: s.end_time, label: s.label || ('Shift ' + (idx + 1)) }));
        modelLabel = '3 Shifts (8h: ' + targetShifts.map(s => formatTime12Hour(s.start_time)).join(' / ') + ')';
      } else {
        targetShifts = [
          { start_time: '06:00', end_time: '14:00', label: 'First Shift' },
          { start_time: '14:00', end_time: '22:00', label: 'Second Shift' },
          { start_time: '22:00', end_time: '06:00', label: 'Third Shift' }
        ];
        modelLabel = '3 Shifts (8h: 6:00 AM / 2:00 PM / 10:00 PM)';
      }
    } else {
      // Default: 2_shifts_12h
      if (Array.isArray(customHours) && customHours.length >= 2 && customHours.slice(0, 2).every(s => s.start_time && s.end_time)) {
        targetShifts = customHours.slice(0, 2).map((s, idx) => ({ start_time: s.start_time, end_time: s.end_time, label: s.label || ('Shift ' + (idx + 1)) }));
        modelLabel = '2 Shifts (12h: ' + formatTime12Hour(targetShifts[0].start_time) + '–' + formatTime12Hour(targetShifts[0].end_time) + ')';
      } else {
        targetShifts = [
          { start_time: '06:00', end_time: '18:00', label: 'Day Shift' },
          { start_time: '18:00', end_time: '06:00', label: 'Night Shift' }
        ];
        modelLabel = '2 Shifts (12h: 6:00 AM–6:00 PM)';
      }
    }

    const sig = RosterSetup.signature(targetShifts);
    const matchingSetup = savedSetups.find(s => RosterSetup.signature(s.shifts) === sig);

    if (matchingSetup) {
      setup.value = matchingSetup.id;
      customRosterShifts = null;
    } else {
      customRosterShifts = targetShifts;
    }

    updateContractNotice({ label: modelLabel, siteName: loc.label });
    window.renderShiftRoster();
  }

  site.addEventListener('change', () => {
    const activeObj = locations.find(l => l.id === site.value);
    if (siteFilter) {
      siteFilter.value = activeObj ? activeObj.label : '';
    }
    if (siteFilterClear) {
      siteFilterClear.hidden = !site.value;
    }
    applySiteContractShifts(site.value);
    summary();
  });

  if (siteMenu) {
    siteMenu.addEventListener('click', (e) => {
      const item = e.target.closest('.roster-combobox-item');
      if (!item) return;
      site.value = item.dataset.id;
      if (siteFilter) siteFilter.value = item.dataset.label;
      if (siteFilterClear) siteFilterClear.hidden = false;
      closeSiteMenu();
      site.dispatchEvent(new Event('change'));
    });
  }

  if (siteFilter) {
    siteFilter.addEventListener('focus', () => {
      openSiteMenu();
      siteFilter.select();
    });
    siteFilter.addEventListener('click', () => {
      if (siteMenu && siteMenu.hidden) {
        openSiteMenu();
        siteFilter.select();
      }
    });
    siteFilter.addEventListener('input', () => {
      openSiteMenu();
      if (siteFilterClear) siteFilterClear.hidden = !siteFilter.value;
    });
    siteFilter.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeSiteMenu();
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (siteMenu && siteMenu.hidden) openSiteMenu();
        const items = [...siteMenu.querySelectorAll('.roster-combobox-item')];
        if (!items.length) return;
        const focused = siteMenu.querySelector('.roster-combobox-item.is-focused');
        const idx = focused ? items.indexOf(focused) : -1;
        const next = items[Math.min(idx + 1, items.length - 1)];
        items.forEach(it => it.classList.remove('is-focused'));
        next.classList.add('is-focused');
        next.scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const items = [...siteMenu.querySelectorAll('.roster-combobox-item')];
        if (!items.length) return;
        const focused = siteMenu.querySelector('.roster-combobox-item.is-focused');
        const idx = focused ? items.indexOf(focused) : items.length;
        const prev = items[Math.max(idx - 1, 0)];
        items.forEach(it => it.classList.remove('is-focused'));
        prev.classList.add('is-focused');
        prev.scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'Enter') {
        const focused = siteMenu?.querySelector('.roster-combobox-item.is-focused');
        if (focused && !siteMenu.hidden) {
          e.preventDefault();
          focused.click();
        }
      }
    });
  }

  if (comboboxToggle) {
    comboboxToggle.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (siteMenu && siteMenu.hidden) {
        siteFilter?.focus();
        openSiteMenu();
      } else {
        closeSiteMenu();
      }
    });
  }

  if (siteFilterClear) {
    siteFilterClear.addEventListener('click', (e) => {
      e.stopPropagation();
      site.value = '';
      if (siteFilter) siteFilter.value = '';
      siteFilterClear.hidden = true;
      closeSiteMenu();
      site.dispatchEvent(new Event('change'));
      siteFilter?.focus();
    });
  }

  document.addEventListener('click', (e) => {
    if (combobox && !combobox.contains(e.target)) {
      closeSiteMenu();
    }
  });
  if (weeklyButton) {
    weeklyButton.addEventListener('click', async () => {
      if (saving || setupSaving) return;
      summary();
      const chosenSetup = customSetup(), targetDay = date.value, location = site.value, now = new Date();
      if (!location) {
        appDialog.toast('Please select a Deployment site first.', { tone: 'warning' });
        return;
      }
      if (!chosenSetup && !customRosterShifts) {
        appDialog.toast('Please wait for the site shifting setup to load.', { tone: 'warning' });
        return;
      }
      const shifts = periods();
      const ids = selected();
      const expected = shifts.length;

      for (let i = 0; i < expected; i++) {
        if (!ids[i]) {
          appDialog.toast(`Please select a Guard for ${shifts[i][2]}.`, { tone: 'warning' });
          return;
        }
      }
      const uniqueSelected = new Set(ids);
      if (uniqueSelected.size !== expected) {
        appDialog.toast('Choose a different Guard for each shift slot.', { tone: 'warning' });
        return;
      }

      const week = getWeekRange(targetDay);
      const locObj = (window.locations || locations || []).find(l => l.id === location);
      const siteName = locObj?.label || 'this site';

      const restDayEl = document.getElementById('weeklyRestDay');
      const restDayValue = Number(restDayEl ? restDayEl.value : -1);
      const restDayNames = { 0: 'Sunday', 1: 'Monday', 2: 'Tuesday', 3: 'Wednesday', 4: 'Thursday', 5: 'Friday', 6: 'Saturday' };
      const restDayText = restDayValue !== -1 ? `\n• Weekly Rest Day: Every ${restDayNames[restDayValue]} (skipped in schedule & shows as REST in DTR)` : '\n• Weekly Rest Day: None (7 days straight)';

      const guardNamesList = ids.map((id, i) => `• ${shifts[i][2]}: ${currentName(id)}`).join('\n');
      const confirmMsg = `Assign weekly schedule for ${siteName}?\n\nTarget Week: ${formatDate(week.start)} – ${formatDate(week.end)}\n${guardNamesList}${restDayText}\n\nThis will assign these guards for the week.`;
      const confirmed = await appDialog.confirm(confirmMsg, {
        title: 'Confirm Schedule Assignment',
        confirmText: 'Assign Schedule',
        icon: 'calendar_month'
      });
      if (!confirmed) return;

      saving = true;
      [setup, date, site, ...slots.querySelectorAll('select')].forEach(el => el.disabled = true);
      if (siteFilter) siteFilter.disabled = true;
      if (comboboxToggle) comboboxToggle.disabled = true;

      try {
        await appDialog.runBusy(weeklyButton, async () => {
          let totalAssigned = 0;
          let daysCompleted = 0;
          let skippedDays = [];
          let restDaysSkipped = 0;

          for (const day of week.days) {
            const curDate = parseLocalDate(day);
            const curDayOfWeek = curDate.getDay();
            if (restDayValue !== -1 && curDayOfWeek === restDayValue) {
              restDaysSkipped++;
              skippedDays.push(`${formatDate(day)}: Scheduled Rest Day (${restDayNames[curDayOfWeek]}) — REST`);
              continue;
            }
            try {
              let assignedData = null;
              if (customRosterShifts) {
                try {
                  const { data, error } = await appSupabase.rpc('assign_custom_shift_roster', {
                    p_location_id: location,
                    p_duty_date: day,
                    p_guard_ids: ids,
                    p_shifts: customRosterShifts
                  });
                  if (!error && Array.isArray(data)) assignedData = data;
                } catch (_) {}

                if (!assignedData) {
                  assignedData = [];
                  for (let i = 0; i < ids.length; i++) {
                    if (!available(day, shifts[i], now)) continue;
                    const { data: dtrData, error: dtrErr } = await appSupabase.rpc('create_dtr_schedule', {
                      p_user_id: ids[i],
                      p_location_id: location,
                      p_duty_date: day,
                      p_periods: [{ period: 'auto', start_time: shifts[i][0], end_time: shifts[i][1], next_day: false }]
                    });
                    if (dtrErr) throw dtrErr;
                    if (Array.isArray(dtrData)) assignedData.push(...dtrData);
                    else if (dtrData) assignedData.push(dtrData);
                  }
                }
              } else {
                const args = {
                  p_location_id: location,
                  p_duty_date: day,
                  p_guard_ids: ids,
                  p_setup_id: chosenSetup.id,
                  p_expected_version: chosenSetup.version
                };
                const { data, error } = await appSupabase.rpc('assign_saved_shift_roster', args);
                if (error) throw error;
                assignedData = data;
              }

              if (Array.isArray(assignedData) && assignedData.length) {
                totalAssigned += assignedData.length;
                daysCompleted++;
              }
            } catch (dayErr) {
              skippedDays.push(`${formatDate(day)}: ${dayErr.message || 'skipped'}`);
            }
          }

          if (chosenSetup) {
            chosenSetup.in_use = true;
            setupRevision++;
            managementControls();
          }

          setScheduleListPeriod(week.start);
          await refreshSchedules();

          if (daysCompleted > 0) {
            const restNote = restDaysSkipped > 0 ? ` (with weekly rest day on ${restDayNames[restDayValue]})` : '';
            appDialog.toast(`Schedule assigned: ${totalAssigned} shifts created across ${daysCompleted} duty days${restNote}.`, { tone: 'success' });
          } else {
            throw Error(skippedDays[0] || 'Could not assign weekly shifts. Please check for existing schedules.');
          }
        }, { label: 'Assigning schedule…' });
      } catch (err) {
        appDialog.toast(err.message || 'Could not complete weekly assignment.', { tone: 'danger' });
      } finally {
        saving = false;
        [setup, date, site].forEach(el => el.disabled = false);
        if (siteFilter) siteFilter.disabled = false;
        if (comboboxToggle) comboboxToggle.disabled = false;
        summary();
      }
    });
  }

  button.addEventListener('click',async()=>{
    if(saving||setupSaving)return;
    summary();
    const chosenSetup=customSetup(),day=date.value,location=site.value,now=new Date();
    if(!chosenSetup && !customRosterShifts)return;
    const shifts=periods(),ids=selected().map((id,i)=>available(day,shifts[i],now)?id:null);
    const active=ids.filter((_,i)=>available(day,shifts[i],now)),expected=active.length;
    if(!location||!day||day<todayDateString()||active.some(id=>!id)||new Set(active).size!==expected){
      appDialog.toast('Choose a site, today or a future date, and a different Guard for every shift.',{tone:'warning'});return;
    }
    if(!expected){appDialog.toast('No ongoing or upcoming shifts remain on this date. Choose today or a future date.',{tone:'warning'});return;}
    for(const [i,p] of periods().entries()){
      if(!available(day,p,now))continue;
      const plan=SchedulePeriod.buildDutyPlan(day,[{period:'auto',start_time:p[0],end_time:p[1],next_day:false}]);
      const guard=guards.find(g=>g.id===ids[i]);
      const error=plan.error || (!guard?.active?'Choose active Guards.':ContractPeriod.dutyError(guard,plan.periods[0].startAt,plan.periods[0].endAt));
      if(error){appDialog.toast(error,{tone:'warning'});return;}
    }
    saving=true;[setup,date,site,...slots.querySelectorAll('select')].forEach(el=>el.disabled=true);
    if(siteFilter)siteFilter.disabled=true;
    if(comboboxToggle)comboboxToggle.disabled=true;
    const saveSetupBtn = document.getElementById('saveRosterSetup');
    if (saveSetupBtn) saveSetupBtn.disabled = true;
    try{
      await appDialog.runBusy(button,async()=>{
        let assignedData = null;
        if (customRosterShifts) {
          try {
            const { data, error } = await appSupabase.rpc('assign_custom_shift_roster', {
              p_location_id: location,
              p_duty_date: day,
              p_guard_ids: ids,
              p_shifts: customRosterShifts
            });
            if (!error && Array.isArray(data)) {
              assignedData = data;
            } else if (error && error.code !== 'PGRST202' && !error.message?.includes('assign_custom_shift_roster')) {
              throw error;
            }
          } catch (rpcErr) {
            if (rpcErr.code !== 'PGRST202' && !rpcErr.message?.includes('assign_custom_shift_roster')) {
              throw rpcErr;
            }
          }

          if (!assignedData) {
            assignedData = [];
            for (let i = 0; i < ids.length; i++) {
              if (!available(day, shifts[i], now)) continue;
              const { data: dtrData, error: dtrErr } = await appSupabase.rpc('create_dtr_schedule', {
                p_user_id: ids[i],
                p_location_id: location,
                p_duty_date: day,
                p_periods: [{ period: 'auto', start_time: shifts[i][0], end_time: shifts[i][1], next_day: false }]
              });
              if (dtrErr) throw dtrErr;
              if (Array.isArray(dtrData)) assignedData.push(...dtrData);
              else if (dtrData) assignedData.push(dtrData);
            }
          }

          if (!Array.isArray(assignedData) || assignedData.length !== expected) {
            throw Error('Could not confirm all assignments. Refresh the schedule before retrying.');
          }
          customRosterShifts = null;
        } else {
          const args={p_location_id:location,p_duty_date:day,p_guard_ids:ids};
          args.p_setup_id=chosenSetup.id;args.p_expected_version=chosenSetup.version;
          const {data,error}=await appSupabase.rpc('assign_saved_shift_roster',args);
          if(error)throw error;
          if(!Array.isArray(data)||data.length!==expected)throw Error('Could not confirm all assignments. Refresh the schedule before retrying.');
          chosenSetup.in_use=true;setupRevision++;managementControls();
          assignedData = data;
        }

        setScheduleListPeriod(day);await refreshSchedules();
        appDialog.toast(`${assignedData.length} ${assignedData.length===1?'shift':'shifts'} assigned successfully.`,{tone:'success'});
      },{label:'Assigning shifts…'});
    }catch(error){appDialog.toast(error.message||'Could not confirm the roster. Refresh before retrying.',{tone:'danger'});}
    finally{saving=false;[setup,date,site].forEach(el=>el.disabled=false);if(siteFilter)siteFilter.disabled=false;if(comboboxToggle)comboboxToggle.disabled=false;const sBtn=document.getElementById('saveRosterSetup');if(sBtn)sBtn.disabled=setupSaving;summary();}
  });
  // Setups are saved per agency. Assigned schedules already contain their own
  // start/end timestamps, so saving another setup cannot rewrite old duty/DTR.
  const editor=document.getElementById('newRosterSetup'),form=document.getElementById('rosterSetupForm');
  const setupName=document.getElementById('rosterSetupName'),setupCount=document.getElementById('rosterSetupCount');
  const timeFields=document.getElementById('rosterSetupTimes'),setupError=document.getElementById('rosterSetupError');
  const setupStatus=document.getElementById('rosterSetupsStatus'),retry=document.getElementById('retryRosterSetups');
  const editButton=document.getElementById('editRosterSetup'),removeButton=document.getElementById('removeRosterSetup');
  const saveSetupButton=document.getElementById('saveRosterSetup'),cancelEdit=document.getElementById('cancelRosterSetup');
  const editorTitle=editor?.querySelector('summary');
  function managementControls(){
    const manageEl=document.getElementById('manageRosterSetup');
    if(manageEl) manageEl.hidden=!customSetup();
    const item=customSetup(),locked=item?.in_use!==false;
    if(editButton) editButton.disabled=saving||setupSaving||setupLoading||locked;
    if(removeButton) removeButton.disabled=saving||setupSaving||setupLoading||locked;
    const lockStatus=document.getElementById('rosterSetupLock');
    if(lockStatus){
      lockStatus.textContent=item?.in_use===true?'In use — editing and removal locked.':locked?'Checking setup availability…':'';
      lockStatus.hidden=!lockStatus.textContent;
    }
    if(saveSetupButton) saveSetupButton.disabled=setupSaving||saving||Boolean(editingSetup&&(locked||setupLoading));
    if(retry) retry.disabled=saving||setupSaving||setupLoading;
    button.disabled=saving||setupSaving||!site.value||(!customSetup()&&!customRosterShifts);
    setup.disabled=saving||setupSaving||!savedSetups.length;
  }
  function uniqueSetups(items){
    const signatures=new Set();
    return items.filter(item=>{const key=RosterSetup.signature(item.shifts);if(signatures.has(key))return false;signatures.add(key);return true;});
  }
  function options(selectedId=setup.value){
    setup.innerHTML=savedSetups.length?savedSetups.map(item=>`<option value="${escapeHtml(item.id)}">${escapeHtml(item.name)}${item.name.toLowerCase()===`${item.shifts.length} shifts`?'':` (${item.shifts.length} shifts)`}</option>`).join(''):'<option value="">No shifting setups</option>';
    setup.value=savedSetups.some(item=>item.id===selectedId)?selectedId:(savedSetups[0]?.id||'');
    if (site.value) {
      applySiteContractShifts(site.value);
    } else {
      window.renderShiftRoster();
    }
  }
  window.loadRosterSetups=async({silent=false}={})=>{
    if(setupLoading||setupSaving||saving)return;
    setupLoading=true;managementControls();const revision=setupRevision;if(!silent&&setupStatus)setupStatus.textContent='Loading saved shifting setups…';
    try{
      const {data,error}=await appSupabase.rpc('list_shift_roster_setups');
      if(error)throw error;
      if(!Array.isArray(data)||data.some(item=>!item.id||typeof item.name!=='string'||typeof item.in_use!=='boolean'||RosterSetup.validate(item.shifts)))throw Error('Invalid saved setup response.');
      // A late read must never restore an item removed/edited during the request.
      if(revision!==setupRevision){if(setupStatus)setupStatus.textContent='';return;}
      const cleanData = data.filter(item => !/^\d+\s*Shifts\s*\(\d{1,2}(:\d{2})?\s*(AM|PM)/i.test(item.name));
      const next = uniqueSetups(cleanData);
      const definition=items=>JSON.stringify(items.map(({id,name,shifts,version})=>({id,name,shifts,version})));
      const changed=!setupsLoaded||definition(savedSetups)!==definition(next);
      savedSetups=next;setupsLoaded=true;
      if(editingSetup&&!savedSetups.some(item=>item.id===editingSetup.id&&item.version===editingSetup.version&&!item.in_use))resetEditor();
      if(changed)options();if(setupStatus)setupStatus.textContent='';
    }catch(error){savedSetups.forEach(item=>{item.in_use=undefined;});if(setupStatus)setupStatus.textContent='Could not check shifting setups. Reload to try again.';if(retry)retry.hidden=false;}
    finally{setupLoading=false;managementControls();}
  };
  retry?.addEventListener('click',window.loadRosterSetups);
  const draftShifts=()=>timeFields?[...timeFields.querySelectorAll('.roster-setup-time')].map(row=>({
    start_time:row.querySelector('[data-start]').value,end_time:row.querySelector('[data-end]').value,
  })):[];
  function validateDraft(){
    const error=RosterSetup.validate(draftShifts());
    const valEl=document.getElementById('rosterSetupValidation');
    if(valEl) valEl.textContent=error||'24-hour coverage complete.';
    return error;
  }
  function renderDraft(shifts=RosterSetup.defaults(Number(setupCount?.value||2))){
    if(!timeFields)return;
    timeFields.innerHTML=shifts.map((shift,i)=>`<div class="roster-setup-time"><strong>Shift ${i+1}</strong><div><label for="setupStart${i}">Start time</label><input id="setupStart${i}" data-start type="time" class="form-control" required value="${shift.start_time}"></div><div><label for="setupEnd${i}">End time</label><input id="setupEnd${i}" data-end type="time" class="form-control" required value="${shift.end_time}"></div></div>`).join('');
    validateDraft();
  }
  function resetEditor(){
    if(!editor||!form)return;
    editingSetup=null;form.reset();renderDraft();if(setupError)setupError.hidden=true;
    if(editorTitle)editorTitle.textContent='Create a new shifting setup';if(saveSetupButton)saveSetupButton.textContent='Save shifting setup';if(cancelEdit)cancelEdit.hidden=true;editor.open=false;
  }
  cancelEdit?.addEventListener('click',()=>{if(!setupSaving){resetEditor();setup.focus();}});
  editButton?.addEventListener('click',()=>{
    if(!editor||saving||setupSaving||setupLoading||customSetup()?.in_use!==false)return;
    editingSetup=structuredClone(customSetup());if(setupName)setupName.value=editingSetup.name;if(setupCount)setupCount.value=String(editingSetup.shifts.length);
    renderDraft(editingSetup.shifts);if(setupError)setupError.hidden=true;
    if(editorTitle)editorTitle.textContent='Edit shifting setup';if(saveSetupButton)saveSetupButton.textContent='Save changes';if(cancelEdit)cancelEdit.hidden=false;editor.open=true;setupName?.focus();
  });
  removeButton?.addEventListener('click',async()=>{
    const item=customSetup();if(saving||setupSaving||setupLoading||item?.in_use!==false)return;
    setupSaving=true;setup.disabled=true;button.disabled=true;if(saveSetupButton)saveSetupButton.disabled=true;managementControls();
    try{
      const confirmed=await appDialog.confirm(`Remove “${item.name}” from the shifting setups?`,{title:'Remove shifting setup',confirmText:'Remove setup',danger:true,icon:'delete'});
      if(!confirmed)return;
      const {data,error}=await appSupabase.rpc('remove_shift_roster_setup',{p_setup_id:item.id,p_expected_version:item.version});
      if(error)throw error;if(data!==item.id)throw Error('Could not confirm removal. Reload saved setups.');
      setupRevision++;savedSetups=savedSetups.filter(s=>s.id!==item.id);resetEditor();options();
      appDialog.toast('Shifting setup removed.',{tone:'success'});
    }catch(error){appDialog.toast(error.message||'Could not remove the setup. Try again.',{tone:'danger'});}
    finally{setupSaving=false;setup.disabled=false;button.disabled=false;if(saveSetupButton)saveSetupButton.disabled=false;managementControls();}
  });
  setupCount?.addEventListener('change',()=>renderDraft());timeFields?.addEventListener('input',validateDraft);
  form?.addEventListener('submit',async event=>{
    event.preventDefault();if(setupSaving||saving||(editingSetup&&(setupLoading||customSetup()?.in_use!==false)))return;
    if(setupError)setupError.hidden=true;
    const name=setupName?.value.trim()||'',shifts=draftShifts();
    const validation=RosterSetup.validate(shifts)||(!name?'Enter a name for this shifting setup.':null);
    if(validation){if(setupError){setupError.textContent=validation;setupError.hidden=false;}return;}
    const candidates=savedSetups;
    const duplicate=candidates.find(item=>item.id!==editingSetup?.id&&(RosterSetup.signature(item.shifts)===RosterSetup.signature(shifts)||item.name.trim().toLowerCase()===name.toLowerCase()));
    if(duplicate){if(setupError){setupError.textContent=`A setup with the same name or shift times already exists: ${duplicate.name}. Select or edit that setup instead.`;setupError.hidden=false;}return;}
    setupSaving=true;
    const fields=[...form.querySelectorAll('input,select,button')];fields.forEach(field=>field.disabled=true);
    let savedSuccessfully=false;
    // Avoid switching the roster in the middle of an assignment.
    button.disabled=true;setup.disabled=true;managementControls();
    try{
      const wasEditing=Boolean(editingSetup),args={p_name:name,p_shifts:shifts};
      if(editingSetup){args.p_setup_id=editingSetup.id;args.p_expected_version=editingSetup.version;}
      const {data,error}=await appSupabase.rpc(wasEditing?'update_shift_roster_setup':'save_shift_roster_setup',args);
      if(error)throw error;
      if(!data?.id||typeof data.name!=='string'||RosterSetup.validate(data.shifts))throw Error('Could not confirm the saved setup. Reload saved setups before retrying.');
      setupRevision++;savedSetups=savedSetups.filter(item=>item.id!==data.id);savedSetups.push({...data,in_use:undefined});setupsLoaded=true;
      savedSuccessfully=true;options(data.id);if(editor)editor.open=false;setup.focus();
      resetEditor();
      appDialog.toast(wasEditing?'Shifting setup updated.':'Shifting setup saved.',{tone:'success'});
    }catch(error){if(setupError){setupError.textContent=error.message||'Could not save the shifting setup. Please try again.';setupError.hidden=false;}}
    finally{setupSaving=false;fields.forEach(field=>field.disabled=false);button.disabled=false;setup.disabled=false;managementControls();if(savedSuccessfully)await window.loadRosterSetups();}
  });
  // --- Shift Times Editor Modal for Selected Guard Shifts ---
  const rosterTimesModalEl = document.getElementById('editRosterTimesModal');
  const rosterTimesForm = document.getElementById('editRosterTimesForm');
  const rosterTimesInputs = document.getElementById('rosterTimesInputs');
  const rosterTimesError = document.getElementById('editRosterTimesError');
  let rosterTimesModal = null;

  function showModal(modalEl) {
    if (!modalEl) return;
    if (window.bootstrap?.Modal) {
      rosterTimesModal = window.bootstrap.Modal.getOrCreateInstance(modalEl);
      rosterTimesModal.show();
    } else {
      modalEl.classList.add('show');
      modalEl.style.display = 'block';
      let backdrop = document.querySelector('.modal-backdrop');
      if (!backdrop) {
        backdrop = document.createElement('div');
        backdrop.className = 'modal-backdrop fade show';
        document.body.appendChild(backdrop);
      }
    }
  }

  function hideModal(modalEl) {
    if (!modalEl) return;
    if (window.bootstrap?.Modal) {
      window.bootstrap.Modal.getOrCreateInstance(modalEl).hide();
    } else {
      modalEl.classList.remove('show');
      modalEl.style.display = 'none';
      const backdrop = document.querySelector('.modal-backdrop');
      if (backdrop) backdrop.remove();
    }
  }

  rosterTimesModalEl?.querySelectorAll('[data-bs-dismiss="modal"]').forEach(btn => {
    btn.addEventListener('click', () => hideModal(rosterTimesModalEl));
  });

  function updateModalDurationBadges() {
    if (!rosterTimesInputs) return;
    const boxes = rosterTimesInputs.querySelectorAll('.roster-modal-shift-box');
    boxes.forEach(box => {
      const startVal = box.querySelector('[data-start]')?.value;
      const endVal = box.querySelector('[data-end]')?.value;
      const badge = box.querySelector('.shift-duration-badge');
      if (!badge) return;
      if (!startVal || !endVal || startVal === endVal) {
        badge.textContent = 'Invalid';
        badge.className = 'badge bg-danger-subtle text-danger small shift-duration-badge';
        return;
      }
      const calc = SchedulePeriod.calculate(date.value || '2026-01-01', startVal, endVal);
      if (calc) {
        badge.textContent = `${SchedulePeriod.formatDuration(calc.durationMinutes)}${calc.overnight ? ' (next day)' : ''}`;
        badge.className = 'badge bg-secondary-subtle text-secondary small shift-duration-badge';
      }
    });
  }

  function autoFixRosterGaps() {
    if (!rosterTimesInputs) return;
    const allStarts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
    const allEnds = [...rosterTimesInputs.querySelectorAll('[data-end]')];
    const n = allStarts.length;
    if (n < 2) return;

    for (let i = 0; i < n; i++) {
      const nextIdx = (i + 1) % n;
      if (allEnds[i] && allStarts[nextIdx]) {
        if (i < n - 1) {
          allStarts[nextIdx].value = allEnds[i].value;
        } else {
          allEnds[i].value = allStarts[0].value;
        }
      }
    }
    updateModalDurationBadges();
    if (rosterTimesError) {
      rosterTimesError.hidden = true;
      rosterTimesError.innerHTML = '';
    }
    appDialog.toast('Shift gaps automatically aligned to 24h continuous coverage.', { tone: 'info' });
  }

  function renderRosterTimesInputs(shifts) {
    if (!rosterTimesInputs) return;

    const presetsContainer = document.getElementById('rosterTimesPresets');
    if (presetsContainer) {
      let presetsHtml = '<span class="small text-muted me-1">Quick presets:</span>';
      if (shifts.length === 2) {
        presetsHtml += `
          <button type="button" class="btn btn-xs btn-outline-secondary roster-preset-btn" data-preset="06:00-18:00">6 AM – 6 PM</button>
          <button type="button" class="btn btn-xs btn-outline-secondary roster-preset-btn" data-preset="07:00-19:00">7 AM – 7 PM</button>
          <button type="button" class="btn btn-xs btn-outline-secondary roster-preset-btn" data-preset="08:00-20:00">8 AM – 8 PM</button>
        `;
      } else if (shifts.length === 3) {
        presetsHtml += `
          <button type="button" class="btn btn-xs btn-outline-secondary roster-preset-btn" data-preset="06:00-14:00-22:00">6 AM – 2 PM – 10 PM</button>
          <button type="button" class="btn btn-xs btn-outline-secondary roster-preset-btn" data-preset="07:00-15:00-23:00">7 AM – 3 PM – 11 PM</button>
          <button type="button" class="btn btn-xs btn-outline-secondary roster-preset-btn" data-preset="08:00-16:00-00:00">8 AM – 4 PM – 12 AM</button>
        `;
      }
      presetsHtml += '<button type="button" id="autoFixGapsBtn" class="btn btn-xs btn-outline-primary ms-auto" title="Align all shift boundaries to eliminate gaps and overlaps">Auto-fix gap</button>';
      presetsContainer.innerHTML = presetsHtml;
    }

    rosterTimesInputs.innerHTML = shifts.map((shift, i) => {
      const shiftTitle = shifts.length === 2
        ? (i === 0 ? 'Shift 1 (Day Shift)' : 'Shift 2 (Night Shift)')
        : `Shift ${i + 1}`;
      return `
        <div class="p-3 roster-modal-shift-box" data-shift-idx="${i}">
          <div class="d-flex justify-content-between align-items-center mb-2">
            <strong class="small">${escapeHtml(shiftTitle)}</strong>
            <span class="badge bg-secondary-subtle text-secondary small shift-duration-badge" id="shiftDurationBadge${i}"></span>
          </div>
          <div class="row g-2">
            <div class="col-6">
              <label class="form-label small fw-semibold" for="modalShiftStart${i}">Scheduled IN</label>
              <input type="time" id="modalShiftStart${i}" data-start class="form-control form-control-sm" required value="${shift.start_time}">
            </div>
            <div class="col-6">
              <label class="form-label small fw-semibold" for="modalShiftEnd${i}">Scheduled OUT</label>
              <input type="time" id="modalShiftEnd${i}" data-end class="form-control form-control-sm" required value="${shift.end_time}">
            </div>
          </div>
        </div>
      `;
    }).join('');

    updateModalDurationBadges();
  }

  function openRosterTimesModal(focusIndex = 0) {
    const cur = customSetup();
    const activeShifts = customRosterShifts || cur?.shifts;
    if (!activeShifts || !activeShifts.length) {
      appDialog.toast('No active shifting setup found to edit.', { tone: 'warning' });
      return;
    }
    if (rosterTimesError) {
      rosterTimesError.hidden = true;
      rosterTimesError.innerHTML = '';
    }

    renderRosterTimesInputs(activeShifts);
    showModal(rosterTimesModalEl);

    setTimeout(() => {
      const targetInput = document.getElementById(`modalShiftStart${focusIndex}`) || document.getElementById('modalShiftStart0');
      if (targetInput) targetInput.focus();
    }, 150);
  }

  // Delegated click handler on preview container for edit and reset buttons
  preview.addEventListener('click', e => {
    const editBtn = e.target.closest('#editRosterTimesBtn');
    if (editBtn) {
      e.preventDefault();
      openRosterTimesModal(0);
      return;
    }
    const resetBtn = e.target.closest('#resetRosterTimesBtn');
    if (resetBtn) {
      e.preventDefault();
      customRosterShifts = null;
      window.renderShiftRoster();
      summary();
      appDialog.toast('Reset back to template times.', { tone: 'info' });
      return;
    }
  });

  // Auto-sync continuous 24h coverage for all shift rosters (2, 3, or more shifts)
  if (rosterTimesInputs) {
    rosterTimesInputs.addEventListener('input', e => {
      const input = e.target;
      const isStart = input.hasAttribute('data-start');
      const box = input.closest('.roster-modal-shift-box');
      const idx = box ? Number(box.dataset.shiftIdx) : -1;
      const allStarts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
      const allEnds = [...rosterTimesInputs.querySelectorAll('[data-end]')];
      const n = allStarts.length;

      const flexEl = document.getElementById('flexibleClientHoursMode');
      if (!flexEl?.checked && n >= 2 && idx >= 0 && input.value) {
        if (isStart) {
          // Scheduled IN of Shift idx changed -> previous shift's Scheduled OUT automatically updates to match it!
          const prevIdx = (idx - 1 + n) % n;
          if (allEnds[prevIdx]) allEnds[prevIdx].value = input.value;
        } else {
          // Scheduled OUT of Shift idx changed -> next shift's Scheduled IN automatically updates to match it!
          const nextIdx = (idx + 1) % n;
          if (allStarts[nextIdx]) allStarts[nextIdx].value = input.value;
        }
      }

      updateModalDurationBadges();
      if (rosterTimesError) {
        rosterTimesError.hidden = true;
        rosterTimesError.innerHTML = '';
      }
    });
  }

  // Preset buttons and auto-fix gaps
  document.addEventListener('click', e => {
    const presetBtn = e.target.closest('.roster-preset-btn');
    if (presetBtn && rosterTimesInputs) {
      const preset = presetBtn.dataset.preset;
      if (!preset) return;
      const times = preset.split('-');
      const allStarts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
      const allEnds = [...rosterTimesInputs.querySelectorAll('[data-end]')];
      if (times.length === allStarts.length) {
        for (let i = 0; i < times.length; i++) {
          allStarts[i].value = times[i];
          allEnds[i].value = times[(i + 1) % times.length];
        }
        updateModalDurationBadges();
        if (rosterTimesError) {
          rosterTimesError.hidden = true;
          rosterTimesError.innerHTML = '';
        }
      }
      return;
    }

    const autoFixBtn = e.target.closest('#autoFixGapsBtn, #autoFixGapsInlineBtn');
    if (autoFixBtn) {
      e.preventDefault();
      autoFixRosterGaps();
    }
  });

  function formatTimeShort(val) {
    if (!val) return '';
    const [h, m] = val.split(':').map(Number);
    const suffix = h >= 12 ? 'PM' : 'AM';
    const hour12 = h % 12 || 12;
    return m === 0 ? `${hour12} ${suffix}` : `${hour12}:${String(m).padStart(2, '0')} ${suffix}`;
  }

  if (rosterTimesForm) {
    rosterTimesForm.addEventListener('submit', async event => {
      event.preventDefault();
      const cur = customSetup();
      if (!cur && !customRosterShifts) return;

      const starts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
      const ends = [...rosterTimesInputs.querySelectorAll('[data-end]')];
      const newShifts = starts.map((input, i) => ({
        start_time: input.value,
        end_time: ends[i].value
      }));

      const flexEl = document.getElementById('flexibleClientHoursMode');
      const validateCustomClientShifts = list => {
        if (!Array.isArray(list) || !list.length) return 'Enter at least one shift.';
        for (let i = 0; i < list.length; i++) {
          const s = list[i];
          if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(s?.start_time || '') || !/^([01]\d|2[0-3]):[0-5]\d$/.test(s?.end_time || '')) {
            return `Shift ${i + 1}: enter valid start and end times.`;
          }
          if (s.start_time === s.end_time) return `Shift ${i + 1}: start and end times must be different.`;
        }
        return null;
      };
      const validationError = flexEl?.checked ? validateCustomClientShifts(newShifts) : RosterSetup.validate(newShifts);
      if (validationError) {
        if (rosterTimesError) {
          rosterTimesError.innerHTML = `<div class="d-flex justify-content-between align-items-center w-100 flex-wrap gap-2"><span>${escapeHtml(validationError)}</span><button type="button" id="autoFixGapsInlineBtn" class="btn btn-xs btn-outline-danger">Auto-fix gap</button></div>`;
          rosterTimesError.hidden = false;
        }
        return;
      }

      // Apply custom shift times to current duty assignment only - do NOT save as a permanent template!
      customRosterShifts = newShifts;

      hideModal(rosterTimesModalEl);
      window.renderShiftRoster();
      summary();
      appDialog.toast('Shift times updated for this assignment.', { tone: 'success' });
    });
  }

  // --- ITEM #10: AUTOMATED PERSONNEL DEPLOYMENT (CLIENT-STATIONED MATCH) ---
  function pickEligibleGuardsForShifts(targetSiteId, targetDate, shiftsList, alreadyTakenGuardIds = new Set()) {
    const now = new Date();
    const activeGuards = (window.guards || guards || []).filter(g => g.active && g.role === 'user');
    const dateRows = (window.schedules || schedules || []).filter(s => s.date === targetDate && s.approval_status !== 'cancelled');
    const busyToday = new Set(dateRows.map(s => s.userId));
    const cutoff = SchedulePeriod.dtrPeriodForDate(targetDate);
    const shiftCounts = new Map();
    (window.schedules || schedules || []).forEach(s => {
      if (s.approval_status === 'cancelled') return;
      if (cutoff && s.date >= cutoff.start && s.date <= cutoff.end) {
        shiftCounts.set(s.userId, (shiftCounts.get(s.userId) || 0) + 1);
      }
    });

    // Guards specifically stationed/deployed at targetSiteId
    const deployedGuards = activeGuards.filter(g => {
      const loc = g.assignedLocationId || g.assigned_location_id;
      return loc && loc === targetSiteId;
    });

    const chosen = [];
    for (let i = 0; i < shiftsList.length; i++) {
      const p = shiftsList[i];
      if (!available(targetDate, p, now)) {
        chosen.push('');
        continue;
      }
      const plan = SchedulePeriod.buildDutyPlan(targetDate, [{ period: 'auto', start_time: p[0], end_time: p[1], next_day: false }]);
      if (plan.error) {
        chosen.push('');
        continue;
      }

      // Priority 1: Stationed guards at this site
      let candidates = deployedGuards.filter(g => {
        if (busyToday.has(g.id) || alreadyTakenGuardIds.has(g.id) || chosen.includes(g.id)) return false;
        const contractErr = ContractPeriod.dutyError(g, plan.periods[0].startAt, plan.periods[0].endAt);
        return !contractErr;
      });

      // Priority 2: If site has NO deployed guards in system, fallback to unassigned guards only (never guards assigned to other sites!)
      if (!candidates.length && !deployedGuards.length) {
        candidates = activeGuards.filter(g => {
          const loc = g.assignedLocationId || g.assigned_location_id;
          if (loc) return false; // Do not take guards deployed to another client!
          if (busyToday.has(g.id) || alreadyTakenGuardIds.has(g.id) || chosen.includes(g.id)) return false;
          const contractErr = ContractPeriod.dutyError(g, plan.periods[0].startAt, plan.periods[0].endAt);
          return !contractErr;
        });
      }

      candidates.sort((a, b) => {
        const aCount = shiftCounts.get(a.id) || 0;
        const bCount = shiftCounts.get(b.id) || 0;
        if (aCount !== bCount) return aCount - bCount;
        return (a.name || '').localeCompare(b.name || '');
      });

      const winner = candidates[0];
      chosen.push(winner ? winner.id : '');
      if (winner) alreadyTakenGuardIds.add(winner.id);
    }
    return chosen;
  }

  window.autoAssignShiftRoster = () => {
    if (saving || setupSaving) return;
    const day = date.value || todayDateString();
    if (!site.value && (window.locations || locations || []).length) {
      const unstaffedSite = (window.locations || locations || []).find(loc => {
        return !(window.schedules || schedules || []).some(s => (s.locationId || s.location_id) === loc.id && s.date === day && s.approval_status !== 'cancelled');
      }) || (window.locations || locations || [])[0];
      if (unstaffedSite) {
        site.value = unstaffedSite.id;
        updateSiteOptions(unstaffedSite.id);
        applySiteContractShifts(unstaffedSite.id);
      }
    }
    const shiftsList = periods();
    if (!shiftsList.length) {
      appDialog.toast('Please select a Deployment site first.', { tone: 'warning' });
      return;
    }
    const assignedIds = pickEligibleGuardsForShifts(site.value, day, shiftsList);
    const selects = [...slots.querySelectorAll('select')];
    let filledCount = 0;
    selects.forEach((sel, idx) => {
      if (!sel.disabled && assignedIds[idx]) {
        sel.value = assignedIds[idx];
        filledCount++;
      }
    });
    summary();
    const locObj = (window.locations || locations || []).find(l => l.id === site.value);
    const siteLabel = locObj?.label || 'this site';
    if (filledCount > 0) {
      appDialog.toast(`Auto-assigned ${filledCount} guard${filledCount === 1 ? '' : 's'} stationed at ${siteLabel}. Click "Assign weekly schedule" to confirm.`, { tone: 'success' });
    } else {
      appDialog.toast(`No available stationed guards found for ${siteLabel}. Make sure guards are assigned to this site in Personnel.`, { tone: 'warning' });
    }
  };

  document.getElementById('autoAssignRosterBtn')?.addEventListener('click', () => window.autoAssignShiftRoster());

  if(editor)renderDraft();
  const clock=setInterval(()=>{if(!saving&&!document.hidden){summary();window.loadRosterSetups({silent:true});}},30000);
  window.addEventListener('focus',window.loadRosterSetups);
  window.addEventListener('pagehide',()=>clearInterval(clock),{once:true});
  window.renderShiftRoster();
})();

