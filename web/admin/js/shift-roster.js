(() => {
  'use strict';
  const setup=document.getElementById('rosterSetup'), date=document.getElementById('rosterDate');
  const site=document.getElementById('rosterSite'), slots=document.getElementById('rosterGuards');
  const siteFilter=document.getElementById('rosterSiteFilter'), siteFilterClear=document.getElementById('rosterSiteFilterClear');
  const combobox=document.getElementById('rosterCombobox'), siteMenu=document.getElementById('rosterSiteMenu'), comboboxToggle=document.getElementById('rosterComboboxToggle');
  const preview=document.getElementById('rosterPreview'), assigned=document.getElementById('assignedRoster');
  const button=document.getElementById('saveRoster');
  let saving=false,setupSaving=false,setupLoading=false;
  let savedSetups=[];
  let editingSetup=null,setupRevision=0,setupsLoaded=false;
  const customSetup=()=>savedSetups.find(item=>item.id===setup.value);
  const periods=()=>customSetup()?RosterSetup.periods(customSetup().shifts):[];
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
    button.textContent=remaining===shifts.length?'Assign all shifts':'Assign remaining shifts';
  }
  const currentName=id=>guards.find(g=>g.id===id)?.name || 'Select a Guard';
  function summary(){
    availability();
    managementControls();
    syncGuardSelections();
    if(!customSetup()){
      preview.textContent=setupsLoaded?'Create a shifting setup to get started.':'Loading shifting setups…';
      assigned.textContent='';return;
    }
    const ids=selected();
    const cutoff=SchedulePeriod.dtrPeriodForDate(date.value);
    preview.innerHTML='<div class="roster-preview-header d-flex justify-content-between align-items-center flex-wrap gap-2 mb-1">'+
      '<p class="mb-0"><strong>Selected guard shifts</strong></p>'+
      '<button type="button" id="editRosterTimesBtn" class="btn btn-sm btn-outline-danger py-1 px-2" aria-label="Edit shift times">'+
        'Edit shift times'+
      '</button>'+
      '</div>'+
      `<p class="mb-2 text-muted small">${cutoff ? `Duty date: ${escapeHtml(formatDate(date.value))} · DTR cut-off: ${escapeHtml(cutoff.label)}` : 'Choose a valid schedule date.'}</p>`+
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
    slots.innerHTML=periods().map((p,i)=>`<div class="schedule-field"><label class="form-label" for="rosterGuard${i}">${p[2]}</label><select id="rosterGuard${i}" class="form-select" aria-describedby="rosterStatus${i}"><option value="">Select Guard ${i+1}</option>${guards.filter(g=>g.active&&g.role==='user').map(g=>`<option value="${escapeHtml(g.id)}">${escapeHtml(g.name)}</option>`).join('')}</select><p id="rosterStatus${i}" class="form-hint roster-slot-status"></p></div>`).join('');
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
  date.value=todayDateString();
  setup.addEventListener('change',()=>{if(editingSetup)resetEditor();window.renderShiftRoster();});
  date.addEventListener('change',summary);
  site.addEventListener('change', () => {
    const activeObj = locations.find(l => l.id === site.value);
    if (siteFilter) {
      siteFilter.value = activeObj ? activeObj.label : '';
    }
    if (siteFilterClear) {
      siteFilterClear.hidden = !site.value;
    }
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
  button.addEventListener('click',async()=>{
    if(saving||setupSaving)return;
    summary();
    const chosenSetup=customSetup(),day=date.value,location=site.value,now=new Date();
    if(!chosenSetup)return;
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
        const args={p_location_id:location,p_duty_date:day,p_guard_ids:ids};
        args.p_setup_id=chosenSetup.id;args.p_expected_version=chosenSetup.version;
        const {data,error}=await appSupabase.rpc('assign_saved_shift_roster',args);
        if(error)throw error;
        if(!Array.isArray(data)||data.length!==expected)throw Error('Could not confirm all assignments. Refresh the schedule before retrying.');
        chosenSetup.in_use=true;setupRevision++;managementControls();
        setScheduleListPeriod(day);await refreshSchedules();
        appDialog.toast(`${data.length} ${data.length===1?'shift':'shifts'} assigned successfully.`,{tone:'success'});
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
    button.disabled=saving||setupSaving||!customSetup();
    setup.disabled=saving||setupSaving||!savedSetups.length;
  }
  function uniqueSetups(items){
    const signatures=new Set();
    return items.filter(item=>{const key=RosterSetup.signature(item.shifts);if(signatures.has(key))return false;signatures.add(key);return true;});
  }
  function options(selectedId=setup.value){
    setup.innerHTML=savedSetups.length?savedSetups.map(item=>`<option value="${escapeHtml(item.id)}">${escapeHtml(item.name)}${item.name.toLowerCase()===`${item.shifts.length} shifts`?'':` (${item.shifts.length} shifts)`}</option>`).join(''):'<option value="">No shifting setups</option>';
    setup.value=savedSetups.some(item=>item.id===selectedId)?selectedId:(savedSetups[0]?.id||'');
    window.renderShiftRoster();
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
      const next=uniqueSetups(data);
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

  function renderRosterTimesInputs(shifts) {
    if (!rosterTimesInputs) return;
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
    if (!cur || !cur.shifts || !cur.shifts.length) {
      appDialog.toast('No active shifting setup found to edit.', { tone: 'warning' });
      return;
    }
    if (rosterTimesError) {
      rosterTimesError.hidden = true;
      rosterTimesError.textContent = '';
    }

    renderRosterTimesInputs(cur.shifts);
    showModal(rosterTimesModalEl);

    setTimeout(() => {
      const targetInput = document.getElementById(`modalShiftStart${focusIndex}`) || document.getElementById('modalShiftStart0');
      if (targetInput) targetInput.focus();
    }, 150);
  }

  // Delegated click handler on preview container for edit button
  preview.addEventListener('click', e => {
    const editBtn = e.target.closest('#editRosterTimesBtn');
    if (editBtn) {
      e.preventDefault();
      openRosterTimesModal(0);
    }
  });

  // Auto-sync continuous 24h coverage for 2-shift rosters
  if (rosterTimesInputs) {
    rosterTimesInputs.addEventListener('input', e => {
      const input = e.target;
      const isStart = input.hasAttribute('data-start');
      const box = input.closest('.roster-modal-shift-box');
      const idx = box ? Number(box.dataset.shiftIdx) : -1;
      const allStarts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
      const allEnds = [...rosterTimesInputs.querySelectorAll('[data-end]')];

      if (allStarts.length === 2) {
        if (idx === 0) {
          if (!isStart && allStarts[1]) allStarts[1].value = input.value;
          if (isStart && allEnds[1]) allEnds[1].value = input.value;
        } else if (idx === 1) {
          if (isStart && allEnds[0]) allEnds[0].value = input.value;
          if (!isStart && allStarts[0]) allStarts[0].value = input.value;
        }
      }

      updateModalDurationBadges();
      if (rosterTimesError) rosterTimesError.hidden = true;
    });
  }

  // Preset buttons
  document.querySelectorAll('.roster-preset-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const preset = btn.dataset.preset;
      if (!preset || !rosterTimesInputs) return;
      const [start, end] = preset.split('-');
      const allStarts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
      const allEnds = [...rosterTimesInputs.querySelectorAll('[data-end]')];
      if (allStarts.length >= 2) {
        allStarts[0].value = start;
        allEnds[0].value = end;
        allStarts[1].value = end;
        allEnds[1].value = start;
        updateModalDurationBadges();
        if (rosterTimesError) rosterTimesError.hidden = true;
      }
    });
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
      if (!cur) return;

      const starts = [...rosterTimesInputs.querySelectorAll('[data-start]')];
      const ends = [...rosterTimesInputs.querySelectorAll('[data-end]')];
      const newShifts = starts.map((input, i) => ({
        start_time: input.value,
        end_time: ends[i].value
      }));

      const validationError = RosterSetup.validate(newShifts);
      if (validationError) {
        if (rosterTimesError) {
          rosterTimesError.textContent = validationError;
          rosterTimesError.hidden = false;
        }
        return;
      }

      const saveBtn = document.getElementById('saveRosterTimesBtn');
      if (saveBtn) saveBtn.disabled = true;

      try {
        let savedInDb = false;
        if (cur.id && window.appSupabase) {
          try {
            if (cur.in_use === false && cur.version) {
              const { data, error } = await appSupabase.rpc('update_shift_roster_setup', {
                p_setup_id: cur.id,
                p_name: cur.name,
                p_shifts: newShifts,
                p_expected_version: cur.version
              });
              if (!error && data) {
                cur.shifts = newShifts;
                cur.version = data.version;
                savedInDb = true;
              }
            }
            if (!savedInDb) {
              const newName = `${newShifts.length} Shifts (${formatTimeShort(newShifts[0].start_time)} – ${formatTimeShort(newShifts[0].end_time)})`;
              const { data, error } = await appSupabase.rpc('save_shift_roster_setup', {
                p_name: newName,
                p_shifts: newShifts
              });
              if (!error && data?.id) {
                setupRevision++;
                const existingIdx = savedSetups.findIndex(s => s.id === data.id);
                if (existingIdx >= 0) savedSetups[existingIdx] = data;
                else savedSetups.push(data);
                setup.value = data.id;
                savedInDb = true;
              }
            }
          } catch (dbErr) {
            console.warn('Database sync for shift times edit:', dbErr);
          }
        }

        // Always update active setup shifts in memory
        cur.shifts = newShifts;

        hideModal(rosterTimesModalEl);
        window.renderShiftRoster();
        summary();
        appDialog.toast('Shift times updated successfully.', { tone: 'success' });
      } catch (err) {
        if (rosterTimesError) {
          rosterTimesError.textContent = err.message || 'Could not update shift times.';
          rosterTimesError.hidden = false;
        }
      } finally {
        if (saveBtn) saveBtn.disabled = false;
      }
    });
  }

  if(editor)renderDraft();
  const clock=setInterval(()=>{if(!saving&&!document.hidden){summary();window.loadRosterSetups({silent:true});}},30000);
  window.addEventListener('focus',window.loadRosterSetups);
  window.addEventListener('pagehide',()=>clearInterval(clock),{once:true});
  window.renderShiftRoster();
})();

