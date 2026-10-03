'use strict';
const auth = firebase.auth(), db = firebase.firestore();
let dutyRequests = [], dutyProfiles = {}, dutySchedules = {}, loadSequence = 0;
const requestList = document.getElementById('requests');
const requestStatus = document.getElementById('requestStatus');
const requestSearch = document.getElementById('requestSearch');
const escapeText = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const profileName = p => p ? [p.first_name, p.middle_initial ? `${p.middle_initial}.` : '', p.last_name].filter(Boolean).join(' ') || p.username : 'Guard';
const when = value => value ? new Date(value).toLocaleString('en-PH', {timeZone:'Asia/Manila',year:'numeric',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'}) : '—';
const isExchange = r => Boolean(r.target_schedule_id);
const requestKind = r => r.request_type === 'absence' ? 'Absence' : isExchange(r) ? 'Duty exchange' : 'Coverage';
const dutySummary = s => `${({morning:'Morning',afternoon:'Afternoon',overtime:'Overtime'})[s?.dtr_period] || 'Continuous shift'} · ${when(s?.start_at)} – ${when(s?.end_at)} · ${s?.location_label || 'Duty site'}`;
const statusLabel = s => ({pending_admin:'Awaiting Operations Head approval',approved:'Approved',rejected:'Rejected',cancelled:'Cancelled'}[s] || s);

auth.onAuthStateChanged(async user => {
  if (!user) { location.href = '../staff/login.html'; return; }
  try {
    const profile = await db.collection('users').doc(user.uid).get();
    if (!profile.exists || profile.data().role !== 'admin' || profile.data().active === false) { location.href = '../staff/login.html'; return; }
    finishPageLoading();
    await loadDutyRequests();
  } catch (_) { finishPageLoading(); requestList.textContent = 'Could not load your account. Please sign in again.'; }
});

async function loadDutyRequests() {
  const sequence = ++loadSequence;
  requestList.innerHTML = '<div class="empty-state" role="status">Loading duty requests…</div>';
  try {
    let query = appSupabase.from('shift_swap_requests').select().order('created_at',{ascending:false}).limit(200);
    if (requestStatus.value !== 'all') query = query.eq('status', requestStatus.value);
    const [requests, profiles] = await Promise.all([query, appSupabase.from('profiles').select('id,first_name,middle_initial,last_name,username,role,active')]);
    if (requests.error || profiles.error) throw requests.error || profiles.error;
    const ids = [...new Set((requests.data || []).flatMap(r => [r.requested_schedule_id,r.target_schedule_id]).filter(Boolean))];
    const schedules = ids.length ? await appSupabase.from('schedules').select('id,start_at,end_at,location_label,duty_date,dtr_period').in('id',ids) : {data:[]};
    if (schedules.error) throw schedules.error;
    if (sequence !== loadSequence) return;
    dutyRequests = requests.data || [];
    dutyProfiles = Object.fromEntries((profiles.data || []).map(p => [p.id,p]));
    dutySchedules = Object.fromEntries((schedules.data || []).map(s => [s.id,s]));
    renderDutyRequests();
  } catch (error) {
    if (sequence !== loadSequence) return;
    requestList.innerHTML = '<div class="empty-state">Could not load requests. Use Refresh to retry.</div>';
    appDialog.toast(error.message || 'Could not load duty requests.', {tone:'danger'});
  }
}

function renderDutyRequests() {
  const term = requestSearch.value.trim().toLowerCase();
  const visible = dutyRequests.filter(r => `${profileName(dutyProfiles[r.requester_id])} ${requestKind(r)} ${r.reason}`.toLowerCase().includes(term));
  if (!visible.length) { requestList.innerHTML = '<div class="empty-state">No matching duty requests.</div>'; return; }
  requestList.innerHTML = visible.map(r => {
    const s = r.exchange_snapshot?.offered || dutySchedules[r.requested_schedule_id] || {};
    const target = r.exchange_snapshot?.requested || dutySchedules[r.target_schedule_id] || {};
    const targetName = r.exchange_snapshot?.target_name || profileName(dutyProfiles[r.target_guard_id]);
    return `<article class="duty-request-card" data-request-id="${escapeText(r.id)}">
      <div class="duty-request-heading"><h2>${escapeText(profileName(dutyProfiles[r.requester_id]))}</h2><span class="ax-role-pill">${escapeText(requestKind(r))} · ${escapeText(statusLabel(r.status))}</span></div>
      <p class="duty-request-reason">${escapeText(r.reason)}</p>
      <dl class="duty-request-meta"><div><dt>Requested duty period</dt><dd>${escapeText(({morning:'Morning',afternoon:'Afternoon',overtime:'Overtime'})[s.dtr_period] || 'Continuous shift')} · ${escapeText(when(s.start_at))} – ${escapeText(when(s.end_at))}<br>${escapeText(s.location_label || 'Duty site')}</dd></div><div><dt>Submitted</dt><dd>${escapeText(when(r.created_at))}</dd></div></dl>
      ${isExchange(r) ? `<section class="duty-exchange-preview" aria-label="Proposed duty exchange">
        <div><strong>${escapeText(profileName(dutyProfiles[r.requester_id]))} will take</strong><p>${escapeText(dutySummary(target))}</p></div>
        <div><strong>${escapeText(targetName)} will take</strong><p>${escapeText(dutySummary(s))}</p></div>
        <small>Both duty assignments change together on approval. Dates, times, posts and DTR periods stay unchanged.</small>
      </section>` : r.target_guard_id ? `<p>Replacement: ${escapeText(profileName(dutyProfiles[r.target_guard_id]))}</p>` : ''}
      ${!isExchange(r) && r.request_type !== 'absence' ? '<p class="ax-cell-secondary">The Operations Head selects a replacement for the remaining duty. Existing attendance stays with the original Guard.</p>' : ''}
      ${r.admin_note ? `<p>Operations Head decision: ${escapeText(r.admin_note)}</p>` : ''}
      <div class="duty-request-actions">${r.letter_path ? `<button type="button" class="action-btn" data-action="letter">Download letter · ${escapeText(r.letter_name || 'Attachment')}</button>` : '<span class="ax-cell-secondary">Legacy request · no attachment</span>'}
      ${r.status === 'pending_admin' ? '<button type="button" class="action-btn btn-enable" data-action="approve">Approve</button><button type="button" class="action-btn btn-disable" data-action="reject">Reject</button>' : ''}</div></article>`;
  }).join('');
  if (dutyRequests.length === 200) requestList.insertAdjacentHTML('beforeend','<p class="empty-state">Showing the latest 200 requests. Narrow the status filter for older decisions.</p>');
}

async function downloadLetter(r, button) {
  await appDialog.runBusy(button, async () => {
    const {data,error} = await appSupabase.storage.from('request-letters').createSignedUrl(r.letter_path,120,{download:r.letter_name || 'Request letter'});
    if (error) throw error;
    const url = new URL(data?.signedUrl || '');
    if (url.origin !== 'https://uqtupmpofjqrnefgrexm.supabase.co' || !url.pathname.startsWith('/storage/v1/object/sign/request-letters/')) throw new Error('The attachment link is invalid.');
    const a = document.createElement('a'); a.href = url.href; a.target = '_blank'; a.rel = 'noopener noreferrer';
    document.body.appendChild(a); a.click(); a.remove();
  },{label:'Opening letter…'});
}

async function decideRequest(r, approve, button) {
  const needsReplacement = approve && r.request_type !== 'absence' && !isExchange(r);
  const fields = [];
  let openAttendance = null;
  if (approve && !isExchange(r)) {
    const {data,error}=await appSupabase.from('attendance_sessions').select('id,clock_in_at,clock_out_at,scheduled_end_at').eq('schedule_id',r.requested_schedule_id);
    if(error)throw error;
    openAttendance=(data||[]).find(a=>!a.clock_out_at);
    if(openAttendance)fields.push({name:'actualEnd',label:'Confirmed actual Time Out (Philippine time)',type:'datetime-local',required:true});
  }
  if (needsReplacement) fields.push({name:'replacement',label:'Replacement Guard',type:'select',required:true,
    options:[{value:'',label:'Select an active Guard'},...Object.values(dutyProfiles).filter(p => p.role === 'user' && p.active && p.id !== r.requester_id)
      .map(p => ({value:p.id,label:profileName(p)}))]});
  fields.push({name:'note',label:openAttendance ? 'How was the actual Time Out confirmed?' : approve ? 'Decision note (optional)' : 'Reason for rejection',type:'textarea',required:!approve || !!openAttendance});
  const values = await appDialog.form({title:`${approve ? 'Approve' : 'Reject'} ${requestKind(r).toLowerCase()} request`,
    message:openAttendance ? 'Confirm when the Guard actually stopped working. Recorded work remains on their DTR; only the remaining duty is released. Do not use the approval time unless that is the actual Time Out.' : approve ? r.request_type === 'absence' ? 'Approve absence for the remaining duty period. Any recorded work stays on the Guard’s DTR. Other periods remain scheduled.' : isExchange(r)
      ? `Exchange the two duties shown for ${profileName(dutyProfiles[r.requester_id])} and ${r.exchange_snapshot?.target_name || profileName(dutyProfiles[r.target_guard_id])}? Both Guards will be notified. Changed, started or conflicting duties cannot be exchanged.`
      : 'Create a separate assignment for the replacement from now (or the future shift start) until the original end. Existing attendance stays with the original Guard.' : 'Tell the Guard why this request was rejected.',
    confirmText:approve ? 'Approve request' : 'Reject request',danger:!approve,fields,
    validate:v => {
      if((!approve||openAttendance)&&v.note.trim().length<5)return 'Enter at least 5 characters for the decision note.';
      if(v.note.trim().length>1500)return 'Keep the note within 1500 characters.';
      if(openAttendance){const end=new Date(v.actualEnd+'+08:00');if(!Number.isFinite(end.getTime())||end<new Date(openAttendance.clock_in_at)||end>new Date()||end>new Date(openAttendance.scheduled_end_at))return 'Use the confirmed Time Out between Time In and the earlier of now or scheduled end.';}
      return null;
    }});
  if (!values) return;
  await appDialog.runBusy(button, async () => {
    const {error} = await appSupabase.rpc(isExchange(r)?'decide_duty_request':'decide_duty_relief',{p_request_id:r.id,p_approve:approve,p_note:values.note.trim(),p_replacement_guard_id:needsReplacement ? values.replacement : null,
      ...(!isExchange(r)?{p_actual_end_at:openAttendance ? new Date(values.actualEnd+'+08:00').toISOString() : null}:{})});
    if (error) throw error;
    await loadDutyRequests();
  },{label:approve ? 'Approving…' : 'Rejecting…'});
  appDialog.toast(approve ? isExchange(r) ? 'Duties exchanged. Both Guards have been notified.' : 'Request approved. The Guard has been notified.' : 'Request rejected. The Guard has been notified.',{tone:'success'});
}

const activeRequests = new Set();
requestList.addEventListener('click',async event => {
  const button = event.target.closest('button[data-action]');
  const id = button?.closest('[data-request-id]')?.dataset.requestId;
  const request = dutyRequests.find(r => r.id === id);
  if (!request || activeRequests.has(id)) return;
  activeRequests.add(id);
  try {
    if (button.dataset.action === 'letter') await downloadLetter(request,button);
    else await decideRequest(request,button.dataset.action === 'approve',button);
  } catch (error) { appDialog.toast(error.message || 'Could not process this request. Try again.',{tone:'danger'}); }
  finally { activeRequests.delete(id); }
});
requestStatus.addEventListener('change',loadDutyRequests);
requestSearch.addEventListener('input',renderDutyRequests);
document.getElementById('refreshRequests').addEventListener('click',loadDutyRequests);
