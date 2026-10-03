(() => {
  'use strict';
  const setup=document.getElementById('rosterSetup'), date=document.getElementById('rosterDate');
  const site=document.getElementById('rosterSite'), slots=document.getElementById('rosterGuards');
  const siteFilter=document.getElementById('rosterSiteFilter'), siteFilterClear=document.getElementById('rosterSiteFilterClear');
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
      select.parentElement.querySelector('.roster-slot-status').textContent=ended?'Shift ended':'';
      if(!ended)remaining++;
    });
    button.textContent=remaining===shifts.length?'Assign all shifts':'Assign remaining shifts';
  }
  const currentName=id=>guards.find(g=>g.id===id)?.name || 'Select a Guard';
  function summary(){
    availability();
    managementControls();
    if(!customSetup()){
      preview.textContent=setupsLoaded?'Create a shifting setup to get started.':'Loading shifting setups…';
      assigned.textContent='';return;
    }
    const ids=selected();
    const cutoff=SchedulePeriod.dtrPeriodForDate(date.value);
    preview.innerHTML='<p><strong>Selected guard shifts</strong></p>'+
      `<p>${cutoff ? `Duty date: ${escapeHtml(formatDate(date.value))} · DTR cut-off: ${escapeHtml(cutoff.label)}` : 'Choose a valid schedule date.'}</p>`+
      '<div class="roster-dtr-scroll" tabindex="0" aria-label="Planned guard shifts"><table class="roster-dtr-preview"><thead><tr><th scope="col">Shift and Guard</th><th scope="col">Scheduled IN</th><th scope="col">Scheduled OUT</th><th scope="col">Planned hours</th></tr></thead><tbody>'+
      periods().map((p,i)=>{
        const shift=SchedulePeriod.calculate(date.value,p[0],p[1]);
        const cell=(time,nextDay=false)=>time ? `<strong>${escapeHtml(formatTime(time))}${nextDay?' (next day)':''}</strong>` : '—';
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
    const term = siteFilter ? siteFilter.value.trim().toLowerCase() : '';
    const current = selectedId !== undefined ? selectedId : site.value;
    const filtered = term
      ? locations.filter(l => (l.label || '').toLowerCase().includes(term) || (l.address || '').toLowerCase().includes(term))
      : locations;
    let html = `<option value="">Select location${term ? ` (${filtered.length} found)` : ''}</option>`;
    html += filtered.map(l => `<option value="${escapeHtml(l.id)}">${escapeHtml(l.label)}</option>`).join('');
    if (current && !filtered.some(l => l.id === current)) {
      const activeObj = locations.find(l => l.id === current);
      if (activeObj) html += `<option value="${escapeHtml(activeObj.id)}" selected>${escapeHtml(activeObj.label)} (selected)</option>`;
    }
    site.innerHTML = html;
    site.value = current;
    if (siteFilterClear) siteFilterClear.hidden = !term;
  }

  window.renderShiftRoster=()=>{
    const ids=selected(),oldSite=site.value;
    updateSiteOptions(oldSite);
    slots.innerHTML=periods().map((p,i)=>`<div class="schedule-field"><label class="form-label" for="rosterGuard${i}">${p[2]}</label><select id="rosterGuard${i}" class="form-select" aria-describedby="rosterStatus${i}"><option value="">Select Guard ${i+1}</option>${guards.filter(g=>g.active&&g.role==='user').map(g=>`<option value="${escapeHtml(g.id)}">${escapeHtml(g.name)}</option>`).join('')}</select><p id="rosterStatus${i}" class="form-hint roster-slot-status"></p></div>`).join('');
    slots.querySelectorAll('select').forEach((s,i)=>{s.value=ids[i]||'';s.disabled=saving;s.addEventListener('change',summary);});
    summary();
  };
  date.min=todayDateString();
  date.value=todayDateString();
  setup.addEventListener('change',()=>{if(editingSetup)resetEditor();window.renderShiftRoster();});
  date.addEventListener('change',summary);site.addEventListener('change',summary);
  if(siteFilter){
    siteFilter.addEventListener('input',()=>{
      const old=site.value;
      updateSiteOptions(old);
      const term=siteFilter.value.trim().toLowerCase();
      if(term){
        const matches=locations.filter(l=>(l.label||'').toLowerCase().includes(term));
        if(matches.length===1 && site.value!==matches[0].id){
          site.value=matches[0].id;
          summary();
        }
      }
    });
  }
  if(siteFilterClear){
    siteFilterClear.addEventListener('click',()=>{
      siteFilter.value='';
      updateSiteOptions();
      siteFilter.focus();
    });
  }
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
    document.getElementById('saveRosterSetup').disabled=true;
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
    finally{saving=false;[setup,date,site].forEach(el=>el.disabled=false);if(siteFilter)siteFilter.disabled=false;document.getElementById('saveRosterSetup').disabled=setupSaving;summary();}
  });
  // Setups are saved per agency. Assigned schedules already contain their own
  // start/end timestamps, so saving another setup cannot rewrite old duty/DTR.
  const editor=document.getElementById('newRosterSetup'),form=document.getElementById('rosterSetupForm');
  const setupName=document.getElementById('rosterSetupName'),setupCount=document.getElementById('rosterSetupCount');
  const timeFields=document.getElementById('rosterSetupTimes'),setupError=document.getElementById('rosterSetupError');
  const setupStatus=document.getElementById('rosterSetupsStatus'),retry=document.getElementById('retryRosterSetups');
  const editButton=document.getElementById('editRosterSetup'),removeButton=document.getElementById('removeRosterSetup');
  const saveSetupButton=document.getElementById('saveRosterSetup'),cancelEdit=document.getElementById('cancelRosterSetup');
  const editorTitle=editor.querySelector('summary');
  function managementControls(){
    document.getElementById('manageRosterSetup').hidden=!customSetup();
    const item=customSetup(),locked=item?.in_use!==false;
    editButton.disabled=removeButton.disabled=saving||setupSaving||setupLoading||locked;
    const lockStatus=document.getElementById('rosterSetupLock');
    lockStatus.textContent=item?.in_use===true?'In use — editing and removal locked.':locked?'Checking setup availability…':'';
    lockStatus.hidden=!lockStatus.textContent;
    saveSetupButton.disabled=setupSaving||saving||Boolean(editingSetup&&(locked||setupLoading));
    retry.disabled=saving||setupSaving||setupLoading;
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
    setupLoading=true;managementControls();const revision=setupRevision;if(!silent)setupStatus.textContent='Loading saved shifting setups…';
    try{
      const {data,error}=await appSupabase.rpc('list_shift_roster_setups');
      if(error)throw error;
      if(!Array.isArray(data)||data.some(item=>!item.id||typeof item.name!=='string'||typeof item.in_use!=='boolean'||RosterSetup.validate(item.shifts)))throw Error('Invalid saved setup response.');
      // A late read must never restore an item removed/edited during the request.
      if(revision!==setupRevision){setupStatus.textContent='';return;}
      const next=uniqueSetups(data);
      const definition=items=>JSON.stringify(items.map(({id,name,shifts,version})=>({id,name,shifts,version})));
      const changed=!setupsLoaded||definition(savedSetups)!==definition(next);
      savedSetups=next;setupsLoaded=true;
      if(editingSetup&&!savedSetups.some(item=>item.id===editingSetup.id&&item.version===editingSetup.version&&!item.in_use))resetEditor();
      if(changed)options();setupStatus.textContent='';
    }catch(error){savedSetups.forEach(item=>{item.in_use=undefined;});setupStatus.textContent='Could not check shifting setups. Reload to try again.';retry.hidden=false;}
    finally{setupLoading=false;managementControls();}
  };
  retry.addEventListener('click',window.loadRosterSetups);
  const draftShifts=()=>[...timeFields.querySelectorAll('.roster-setup-time')].map(row=>({
    start_time:row.querySelector('[data-start]').value,end_time:row.querySelector('[data-end]').value,
  }));
  function validateDraft(){
    const error=RosterSetup.validate(draftShifts());
    document.getElementById('rosterSetupValidation').textContent=error||'24-hour coverage complete.';
    return error;
  }
  function renderDraft(shifts=RosterSetup.defaults(Number(setupCount.value))){
    timeFields.innerHTML=shifts.map((shift,i)=>`<div class="roster-setup-time"><strong>Shift ${i+1}</strong><div><label for="setupStart${i}">Start time</label><input id="setupStart${i}" data-start type="time" class="form-control" required value="${shift.start_time}"></div><div><label for="setupEnd${i}">End time</label><input id="setupEnd${i}" data-end type="time" class="form-control" required value="${shift.end_time}"></div></div>`).join('');
    validateDraft();
  }
  function resetEditor(){
    editingSetup=null;form.reset();renderDraft();setupError.hidden=true;
    editorTitle.textContent='Create a new shifting setup';saveSetupButton.textContent='Save shifting setup';cancelEdit.hidden=true;editor.open=false;
  }
  cancelEdit.addEventListener('click',()=>{if(!setupSaving){resetEditor();setup.focus();}});
  editButton.addEventListener('click',()=>{
    if(saving||setupSaving||setupLoading||customSetup()?.in_use!==false)return;
    editingSetup=structuredClone(customSetup());setupName.value=editingSetup.name;setupCount.value=String(editingSetup.shifts.length);
    renderDraft(editingSetup.shifts);setupError.hidden=true;
    editorTitle.textContent='Edit shifting setup';saveSetupButton.textContent='Save changes';cancelEdit.hidden=false;editor.open=true;setupName.focus();
  });
  removeButton.addEventListener('click',async()=>{
    const item=customSetup();if(saving||setupSaving||setupLoading||item?.in_use!==false)return;
    setupSaving=true;setup.disabled=true;button.disabled=true;saveSetupButton.disabled=true;managementControls();
    try{
      const confirmed=await appDialog.confirm(`Remove “${item.name}” from the shifting setups?`,{title:'Remove shifting setup',confirmText:'Remove setup',danger:true,icon:'delete'});
      if(!confirmed)return;
      const {data,error}=await appSupabase.rpc('remove_shift_roster_setup',{p_setup_id:item.id,p_expected_version:item.version});
      if(error)throw error;if(data!==item.id)throw Error('Could not confirm removal. Reload saved setups.');
      setupRevision++;savedSetups=savedSetups.filter(s=>s.id!==item.id);resetEditor();options();
      appDialog.toast('Shifting setup removed.',{tone:'success'});
    }catch(error){appDialog.toast(error.message||'Could not remove the setup. Try again.',{tone:'danger'});}
    finally{setupSaving=false;setup.disabled=false;button.disabled=false;saveSetupButton.disabled=false;managementControls();}
  });
  setupCount.addEventListener('change',()=>renderDraft());timeFields.addEventListener('input',validateDraft);
  form.addEventListener('submit',async event=>{
    event.preventDefault();if(setupSaving||saving||(editingSetup&&(setupLoading||customSetup()?.in_use!==false)))return;
    setupError.hidden=true;
    const name=setupName.value.trim(),shifts=draftShifts();
    const validation=RosterSetup.validate(shifts)||(!name?'Enter a name for this shifting setup.':null);
    if(validation){setupError.textContent=validation;setupError.hidden=false;return;}
    const candidates=savedSetups;
    const duplicate=candidates.find(item=>item.id!==editingSetup?.id&&(RosterSetup.signature(item.shifts)===RosterSetup.signature(shifts)||item.name.trim().toLowerCase()===name.toLowerCase()));
    if(duplicate){setupError.textContent=`A setup with the same name or shift times already exists: ${duplicate.name}. Select or edit that setup instead.`;setupError.hidden=false;return;}
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
      savedSuccessfully=true;options(data.id);editor.open=false;setup.focus();
      resetEditor();
      appDialog.toast(wasEditing?'Shifting setup updated.':'Shifting setup saved.',{tone:'success'});
    }catch(error){setupError.textContent=error.message||'Could not save the shifting setup. Please try again.';setupError.hidden=false;}
    finally{setupSaving=false;fields.forEach(field=>field.disabled=false);button.disabled=false;setup.disabled=false;managementControls();if(savedSuccessfully)await window.loadRosterSetups();}
  });
  renderDraft();
  const clock=setInterval(()=>{if(!saving&&!document.hidden){summary();window.loadRosterSetups({silent:true});}},30000);
  window.addEventListener('focus',window.loadRosterSetups);
  window.addEventListener('pagehide',()=>clearInterval(clock),{once:true});
  window.renderShiftRoster();
})();

