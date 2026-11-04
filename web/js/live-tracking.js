(async function() {
  'use strict';
  const status=document.getElementById('trackingStatus');
  const list=document.getElementById('guardList'), search=document.getElementById('guardSearch');
  const refreshButton=document.getElementById('refreshTracking');
  const entries=new Map();
  const siteEntries=new Map();
  const guardHistoryMap=new Map();
  const HISTORY_STORAGE_KEY='sams_guard_location_history_v1';
  let historyLayer=null,activeHistoryGuardId=null;
  try {
    const rawHist=localStorage.getItem(HISTORY_STORAGE_KEY);
    if(rawHist){
      const parsedHist=JSON.parse(rawHist);
      if(parsedHist&&typeof parsedHist==='object'){
        Object.entries(parsedHist).forEach(([k,v])=>{if(Array.isArray(v))guardHistoryMap.set(k,v.slice(0,100));});
      }
    }
  } catch(_) {}
  const serverClock=window.LiveTrackingModel.createServerClock();
  const reconcileMs=30000, realtimeBatchMs=1000, retryMs=500, requestTimeoutMs=10000;
  const AVATAR_PALETTE=['#b91c1c','#9f1239','#0f766e','#1d4ed8','#6d28d9','#b45309','#15803d','#334155'];
  const RING_HEX={green:'#16a34a',amber:'#f59e0b',gray:'#6b7280'};
  let rows=[],siteLocations=[],assignedGuards=[],selectedSiteKey=null,map,layer,siteLayer,channel,timer,ageTimer,refreshTimer,client,authSubscription,stopped=false,loading=false,refreshAgain=false,connected=false,hasFit=false;
  let requestController,retryTimer,retryResolve,requestGeneration=0;
  let interrupted=false,lastAuthorizedAt=0,accessExpiryTimer;
  const empty=document.createElement('p'); empty.className='tracking-empty';
  empty.textContent='No matching guards are currently on duty.';

  function setText(element,value) { if(element.textContent!==value)element.textContent=value; }

  function avatarColor(seed) {
    const text=String(seed||'').trim().toLowerCase();
    if(!text)return AVATAR_PALETTE[0];
    let hash=0;
    for(let i=0;i<text.length;i++)hash=((hash*31)+text.charCodeAt(i))&0x7fffffff;
    return AVATAR_PALETTE[hash%AVATAR_PALETTE.length];
  }

  function guardInitials(row) {
    const first=String(row?.first_name||'').trim();
    const last=String(row?.last_name||'').trim();
    if(first||last) {
      const a=first?first[0]:'';
      const b=last?last[0]:(first.length>1?first[1]:'');
      const pair=(a+b).replace(/[^A-Za-z0-9]/g,'').toUpperCase();
      if(pair)return pair;
    }
    const words=String(row?.guard_name||'').trim().split(/\s+/)
      .map(w=>w.replace(/[^A-Za-z0-9]/g,'')).filter(Boolean);
    if(words.length>=2)return (words[0][0]+words[words.length-1][0]).toUpperCase();
    if(words.length===1)return words[0].slice(0,2).toUpperCase();
    return 'SG';
  }

  function safePhotoUrl(raw) {
    const value=String(raw||'').trim();
    if(!value)return '';
    if(/^data:image\/(?:jpeg|jpg|png);base64,[A-Za-z0-9+/=]+$/i.test(value))return value;
    try {
      const parsed=new URL(value,window.location.href);
      if(parsed.protocol==='https:'||parsed.protocol==='http:')return parsed.href;
    } catch(_) {}
    return '';
  }

  function createAvatarDom(extraClass='') {
    const root=document.createElement('span');
    root.className='tracking-avatar'+(extraClass?' '+extraClass:'')+' ring-green';
    const initials=document.createElement('span');
    initials.className='tracking-avatar-initials';
    const img=document.createElement('img');
    img.className='tracking-avatar-img';
    img.alt='';
    img.hidden=true;
    img.addEventListener('error',()=>{img.hidden=true;});
    img.addEventListener('load',()=>{if(img.getAttribute('src'))img.hidden=false;});
    root.append(initials,img);
    return {root,initials,img,extraClass,photoUrl:''};
  }

  function syncAvatarDom(avatarObj,row,ring) {
    if(!avatarObj)return;
    const nextClass='tracking-avatar'+(avatarObj.extraClass?' '+avatarObj.extraClass:'')+' ring-'+ring;
    if(avatarObj.root.className!==nextClass)avatarObj.root.className=nextClass;
    avatarObj.root.dataset.ring=ring;
    const bg=avatarColor(row.user_id||row.guard_name);
    if(avatarObj.bg!==bg){avatarObj.bg=bg;avatarObj.root.style.backgroundColor=bg;}
    setText(avatarObj.initials,guardInitials(row));
    const url=safePhotoUrl(row.profile_photo_url||row.profilePhotoUrl);
    if(avatarObj.photoUrl!==url) {
      avatarObj.photoUrl=url;
      if(url) {
        avatarObj.img.src=url;
        avatarObj.img.hidden=false;
      } else {
        avatarObj.img.removeAttribute('src');
        avatarObj.img.hidden=true;
      }
    }
  }

  function parseGuardLocation(row) {
    let client = (row.client_name || '').trim();
    let address = (row.location_address || '').trim();
    const rawLabel = (row.location_label || '').trim();

    if (!client && rawLabel) {
      if (rawLabel.includes(' · ')) {
        const idx = rawLabel.indexOf(' · ');
        client = rawLabel.slice(0, idx).trim();
        address = address || rawLabel.slice(idx + 3).trim();
      } else {
        client = rawLabel;
        address = address || rawLabel;
      }
    }
    return {
      client: client || rawLabel || '—',
      location: address || rawLabel || '—'
    };
  }

  function createInfoRow(labelText, extraClass='') {
    const row = document.createElement('div');
    row.className = 'tracking-info-item' + (extraClass ? ' ' + extraClass : '');
    const label = document.createElement('span');
    label.className = 'tracking-info-label';
    label.textContent = labelText.endsWith(' ') ? labelText : (labelText + ' ');
    const val = document.createElement('span');
    val.className = 'tracking-info-val';
    row.append(label, val);
    return { row, label, val };
  }

  function ensureLocationProfilesUi() {
    const mapWrap = document.getElementById('trackingMap')?.parentElement;
    if (!mapWrap) return null;
    let companyDir = document.getElementById('trackingCompanyDirectory');
    const layout = list?.closest?.('.tracking-layout');
    if (!companyDir && layout && list) {
      let sidebarCol = list.parentElement;
      if (sidebarCol === layout) {
        sidebarCol = document.createElement('div');
        sidebarCol.className = 'tracking-sidebar-col';
        layout.insertBefore(sidebarCol, list);
        sidebarCol.appendChild(list);
      }
      companyDir = document.createElement('section');
      companyDir.id = 'trackingCompanyDirectory';
      companyDir.className = 'tracking-company-directory';
      companyDir.setAttribute('aria-label', 'Deployment sites and companies');
      companyDir.hidden = true;
      sidebarCol.insertBefore(companyDir, list);
    }
    let sitesBar = document.getElementById('trackingSiteChips');
    if (!sitesBar) {
      sitesBar = document.createElement('div');
      sitesBar.id = 'trackingSiteChips';
      sitesBar.className = 'tracking-site-chips';
      sitesBar.setAttribute('aria-label', 'Client locations');
      sitesBar.hidden = true;
      mapWrap.insertBefore(sitesBar, document.getElementById('trackingMap'));
    }
    let panel = document.getElementById('locationGuardsPanel');
    if (!panel) {
      panel = document.createElement('section');
      panel.id = 'locationGuardsPanel';
      panel.className = 'tracking-location-panel';
      panel.setAttribute('aria-label', 'Guards on duty at selected location');
      panel.hidden = true;
      mapWrap.appendChild(panel);
    }
    return { companyDir, sitesBar, panel };
  }

  function haversineMeters(lat1, lng1, lat2, lng2) {
    const toRad = d => (d * Math.PI) / 180;
    const R = 6371000;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  function recordGuardHistoryPoint(row) {
    if (!row || !row.user_id || row.state === 'waiting') return;
    const lat = Number(row.latitude), lng = Number(row.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    const uid = String(row.user_id);
    const capturedAt = row.captured_at || new Date().toISOString();
    const listPts = guardHistoryMap.get(uid) || [];
    if (listPts.length) {
      const latest = listPts[0];
      if (latest.captured_at === capturedAt) return;
      const dist = haversineMeters(latest.latitude, latest.longitude, lat, lng);
      const timeDiff = Math.abs(Date.parse(capturedAt) - Date.parse(latest.captured_at || 0));
      if (dist < 2 && timeDiff < 15000) return;
    }
    listPts.unshift({
      user_id: uid,
      guard_name: row.guard_name || 'Guard',
      location_label: row.location_label || '',
      latitude: lat,
      longitude: lng,
      accuracy_meters: Number(row.accuracy_meters) || 25,
      captured_at: capturedAt
    });
    if (listPts.length > 100) listPts.length = 100;
    guardHistoryMap.set(uid, listPts);
    try {
      const serial = {};
      for (const [k, v] of guardHistoryMap.entries()) serial[k] = v.slice(0, 50);
      localStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(serial));
    } catch (_) {}
  }

  async function openGuardLocationHistory(userId, fallbackGuard) {
    const uid = String(userId || '');
    if (!uid) return;
    activeHistoryGuardId = uid;
    const mapWrap = document.getElementById('trackingMap')?.parentElement;
    if (!mapWrap) return;
    let histPanel = document.getElementById('guardHistoryPanel');
    if (!histPanel) {
      histPanel = document.createElement('section');
      histPanel.id = 'guardHistoryPanel';
      histPanel.className = 'tracking-location-panel tracking-history-panel';
      histPanel.setAttribute('aria-label', 'Guard location history');
      mapWrap.appendChild(histPanel);
    }
    histPanel.hidden = false;
    histPanel.innerHTML = '<div class="tracking-location-panel-head"><div><h3 class="tracking-location-panel-title">Loading Location History…</h3></div></div>';

    let dbPoints = [];
    if (client && typeof client.rpc === 'function' && /^[0-9a-f-]{32,36}$/i.test(uid)) {
      try {
        const res = await client.rpc('get_guard_location_history', { p_user_id: uid, p_limit: 100 });
        if (Array.isArray(res?.data)) dbPoints = res.data;
      } catch (_) {}
    }
    const localPoints = guardHistoryMap.get(uid) || [];
    const mergedMap = new Map();
    [...dbPoints, ...localPoints].forEach(pt => {
      const lat = Number(pt.latitude), lng = Number(pt.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const key = `${pt.captured_at || ''}_${lat.toFixed(5)}_${lng.toFixed(5)}`;
      if (!mergedMap.has(key)) {
        mergedMap.set(key, {
          latitude: lat,
          longitude: lng,
          accuracy_meters: Number(pt.accuracy_meters) || 25,
          captured_at: pt.captured_at || new Date().toISOString(),
          location_label: pt.location_label || fallbackGuard?.location_label || 'Assigned Post'
        });
      }
    });
    const points = [...mergedMap.values()].sort((a, b) => Date.parse(b.captured_at) - Date.parse(a.captured_at));

    let totalDistanceMeters = 0;
    for (let i = 0; i < points.length - 1; i++) {
      totalDistanceMeters += haversineMeters(points[i].latitude, points[i].longitude, points[i + 1].latitude, points[i + 1].longitude);
    }

    if (map && window.L) {
      if (!historyLayer && typeof L.layerGroup === 'function') historyLayer = L.layerGroup().addTo(map);
      if (historyLayer && typeof historyLayer.clearLayers === 'function') historyLayer.clearLayers();
      if (points.length >= 2 && typeof L.polyline === 'function' && historyLayer) {
        L.polyline(points.map(p => [p.latitude, p.longitude]), { color: '#2563eb', weight: 3, dashArray: '6, 6', opacity: 0.85 }).addTo(historyLayer);
      }
      if (points.length && typeof map.setView === 'function') {
        map.setView([points[0].latitude, points[0].longitude], 17);
      }
    }

    const guardName = fallbackGuard?.guard_name || entries.get(uid)?.row?.guard_name || 'Guard';
    histPanel.replaceChildren();
    const head = document.createElement('div');
    head.className = 'tracking-location-panel-head';
    const titleWrap = document.createElement('div');
    const title = document.createElement('h3');
    title.className = 'tracking-location-panel-title';
    title.textContent = `${guardName} — Location History (${points.length} pts)`;
    const sub = document.createElement('p');
    sub.className = 'tracking-location-panel-sub';
    sub.textContent = `Total tracked movement: ${Math.round(totalDistanceMeters)} m · Stored in Guard Location History`;
    titleWrap.append(title, sub);

    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'tracking-location-panel-close';
    closeBtn.textContent = 'Close History';
    closeBtn.onclick = () => {
      activeHistoryGuardId = null;
      histPanel.hidden = true;
      if (historyLayer && typeof historyLayer.clearLayers === 'function') historyLayer.clearLayers();
    };
    head.append(titleWrap, closeBtn);
    histPanel.appendChild(head);

    if (!points.length) {
      const emptyEl = document.createElement('p');
      emptyEl.className = 'tracking-location-empty';
      emptyEl.textContent = 'No GPS location history points recorded for this guard yet.';
      histPanel.appendChild(emptyEl);
      return;
    }

    const listWrap = document.createElement('div');
    listWrap.className = 'tracking-history-list';
    points.forEach((pt, idx) => {
      const prevPt = points[idx + 1];
      const stepDist = prevPt ? Math.round(haversineMeters(pt.latitude, pt.longitude, prevPt.latitude, prevPt.longitude)) : 0;
      const item = document.createElement('div');
      item.className = 'tracking-history-item';
      const ts = new Date(pt.captured_at);
      const timeLabel = Number.isNaN(ts.getTime()) ? String(pt.captured_at) : ts.toLocaleString('en-PH', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', second: '2-digit' });
      const info = document.createElement('div');
      const strong = document.createElement('strong');
      strong.textContent = `${idx === 0 ? 'Latest · ' : `#${points.length - idx} · `}${timeLabel}`;
      const meta = document.createElement('div');
      meta.className = 'tracking-history-meta';
      meta.textContent = `${pt.latitude.toFixed(5)}, ${pt.longitude.toFixed(5)} · ±${Math.round(pt.accuracy_meters)} m${prevPt ? ` · Moved ${stepDist} m` : ' · Initial point'}`;
      info.append(strong, meta);

      const jumpBtn = document.createElement('button');
      jumpBtn.type = 'button';
      jumpBtn.className = 'tracking-focus-guard-btn';
      jumpBtn.style.marginTop = '0';
      jumpBtn.textContent = 'Pin on Map';
      jumpBtn.onclick = () => {
        map?.setView([pt.latitude, pt.longitude], 18);
      };
      item.append(info, jumpBtn);
      listWrap.appendChild(item);
    });
    histPanel.appendChild(listWrap);
  }

  function fullGuardName(g) {
    if (!g) return 'Guard';
    if (g.guard_name) return String(g.guard_name).trim();
    const parts = [g.first_name, g.middle_initial ? `${g.middle_initial}.` : '', g.last_name].filter(Boolean);
    return parts.join(' ').trim() || g.username || 'Guard';
  }

  function buildLocationGroups(onDutyRows) {
    const groups = new Map();
    const profileById = new Map();
    for (const g of assignedGuards) {
      if (g && g.id) profileById.set(String(g.id), g);
    }
    for (const loc of siteLocations) {
      if (!loc || loc.active === false) continue;
      const key = String(loc.id || loc.label || '').trim();
      if (!key) continue;
      const lat = Number(loc.latitude ?? loc.lat);
      const lng = Number(loc.longitude ?? loc.lng);
      groups.set(key, {
        key,
        id: loc.id || null,
        label: String(loc.label || 'Deployment Site').trim(),
        address: String(loc.address || '').trim(),
        lat,
        lng,
        radius: Number(loc.radius) || 100,
        guards: new Map()
      });
    }
    // Only include personnel who are currently assigned in real time / on duty right now
    for (const row of (onDutyRows || [])) {
      const parsed = parseGuardLocation(row);
      const clientName = parsed.client;
      const prof = profileById.get(String(row.user_id)) || {};
      let targetGroup = null;
      if (row.location_id && groups.has(String(row.location_id))) {
        targetGroup = groups.get(String(row.location_id));
      }
      if (!targetGroup) {
        for (const grp of groups.values()) {
          if (grp.label.toLowerCase() === clientName.toLowerCase() ||
              String(row.location_label || '').toLowerCase().includes(grp.label.toLowerCase())) {
            targetGroup = grp;
            break;
          }
        }
      }
      if (!targetGroup && prof.assigned_location_id && groups.has(String(prof.assigned_location_id))) {
        targetGroup = groups.get(String(prof.assigned_location_id));
      }
      if (!targetGroup && clientName && clientName !== '—') {
        const syntheticKey = 'loc:' + clientName.toLowerCase();
        targetGroup = groups.get(syntheticKey);
        if (!targetGroup) {
          targetGroup = {
            key: syntheticKey,
            id: null,
            label: clientName,
            address: parsed.location !== clientName ? parsed.location : '',
            lat: Number(row.latitude),
            lng: Number(row.longitude),
            radius: Number(row.accuracy_meters) || 100,
            guards: new Map()
          };
          groups.set(syntheticKey, targetGroup);
        }
      }
      if (targetGroup) {
        if (!Number.isFinite(targetGroup.lat) && Number.isFinite(Number(row.latitude))) {
          targetGroup.lat = Number(row.latitude);
          targetGroup.lng = Number(row.longitude);
        }
        targetGroup.guards.set(String(row.user_id), {
          user_id: String(row.user_id),
          guard_name: row.guard_name || fullGuardName(prof) || 'Guard',
          first_name: row.first_name || prof.first_name || '',
          last_name: row.last_name || prof.last_name || '',
          personnel_id: row.personnel_id || prof.personnel_id || '',
          employment_category: row.employment_category || prof.employment_category || 'regular',
          contract_start_date: row.contract_start_date || prof.contract_start_date || '',
          contract_end_date: row.contract_end_date || prof.contract_end_date || '',
          mobile_number: row.mobile_number || row.contact_number || prof.mobile_number || '',
          complete_address: row.complete_address || prof.complete_address || '',
          emergency_contact: row.emergency_contact || prof.emergency_contact || '',
          profile_photo_url: row.profile_photo_url || prof.profile_photo_url || '',
          location_label: row.location_label || targetGroup.label,
          location_address: row.location_address || targetGroup.address,
          ...row,
          onDuty: true
        });
      }
    }
    return groups;
  }

  function allOnDutyRows() {
    return window.LiveTrackingModel.visible(rows, '', serverClock.now())
      .map(row => interrupted && row.state !== 'waiting' ? { ...row, state: 'stale' } : row);
  }

  function groupMatchesQuery(grp, rawQuery) {
    const q = String(rawQuery || '').trim().toLowerCase();
    if (!q) return true;
    if (grp.label.toLowerCase().includes(q) || grp.address.toLowerCase().includes(q)) return true;
    for (const g of grp.guards.values()) {
      if (String(g.guard_name || '').toLowerCase().includes(q)) return true;
    }
    return false;
  }

  function openLocationGuardsProfile(groupKey, zoomOnMap = true) {
    const groups = buildLocationGroups(allOnDutyRows());
    const group = groups.get(groupKey);
    const ui = ensureLocationProfilesUi();
    if (!ui) return;
    if (!group) {
      selectedSiteKey = null;
      ui.panel.hidden = true;
      return;
    }
    selectedSiteKey = group.key;
    if (zoomOnMap && map && Number.isFinite(group.lat) && Number.isFinite(group.lng)) {
      if (typeof map.flyTo === 'function') map.flyTo([group.lat, group.lng], 17, { duration: 0.45 });
      else map.setView([group.lat, group.lng], 17);
    }
    ui.sitesBar.querySelectorAll('.tracking-site-chip').forEach(btn => {
      btn.classList.toggle('is-active', btn.dataset.siteKey === group.key);
    });
    siteEntries.forEach((entryObj, k) => {
      entryObj.pinEl?.classList.toggle('is-active', k === group.key);
    });
    if (ui.companyDir) {
      ui.companyDir.querySelectorAll('.tracking-company-card').forEach(card => {
        const active = card.dataset.siteKey === group.key;
        card.classList.toggle('is-active', active);
        const rosterEl = card.querySelector('.tracking-company-roster');
        if (rosterEl) rosterEl.hidden = !active;
      });
    }

    const guardsList = [...group.guards.values()];
    ui.panel.hidden = false;
    ui.panel.replaceChildren();

    const head = document.createElement('div');
    head.className = 'tracking-location-panel-head';
    const titleWrap = document.createElement('div');
    const title = document.createElement('h3');
    title.className = 'tracking-location-panel-title';
    title.textContent = `${group.label} — On-Duty Personnel in Real Time (${guardsList.length})`;
    const sub = document.createElement('p');
    sub.className = 'tracking-location-panel-sub';
    sub.textContent = (group.address ? `${group.address} · ` : '') + `Geofence radius: ${group.radius} m · Real-time active duty`;
    titleWrap.append(title, sub);

    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'tracking-location-panel-close';
    closeBtn.textContent = 'Close';
    closeBtn.onclick = () => {
      selectedSiteKey = null;
      ui.panel.hidden = true;
      ui.sitesBar.querySelectorAll('.tracking-site-chip').forEach(btn => btn.classList.remove('is-active'));
      siteEntries.forEach(entryObj => entryObj.pinEl?.classList.remove('is-active'));
      if (ui.companyDir) {
        ui.companyDir.querySelectorAll('.tracking-company-card').forEach(card => {
          card.classList.remove('is-active');
          const rosterEl = card.querySelector('.tracking-company-roster');
          if (rosterEl) rosterEl.hidden = true;
        });
      }
    };
    head.append(titleWrap, closeBtn);
    ui.panel.appendChild(head);

    if (!guardsList.length) {
      const emptyMsg = document.createElement('p');
      emptyMsg.className = 'tracking-location-empty';
      emptyMsg.textContent = `No personnel are currently on duty at ${group.label} in real time.`;
      ui.panel.appendChild(emptyMsg);
      return;
    }

    const grid = document.createElement('div');
    grid.className = 'tracking-location-guard-grid';
    guardsList.forEach(g => {
      const card = document.createElement('article');
      card.className = 'tracking-location-guard-card';
      const cardHead = document.createElement('div');
      cardHead.className = 'tracking-guard-head';
      const ring = g.state === 'waiting' ? 'gray' : (g.ageSeconds > 300 ? 'amber' : 'green');
      const av = createAvatarDom('tracking-list-avatar');
      syncAvatarDom(av, g, ring);
      const nameWrap = document.createElement('div');
      const gName = document.createElement('strong');
      gName.className = 'tracking-guard-name';
      gName.textContent = g.guard_name || 'Guard';
      const gBadge = document.createElement('div');
      gBadge.className = 'tracking-guard-submeta';
      const pid = g.personnel_id ? `${g.personnel_id} · ` : '';
      const cat = (g.employment_category === 'contract') ? 'Contract' : 'Regular';
      const liveState = g.state === 'waiting' ? 'On Duty · Waiting for GPS' : 'On Duty · Live in Real Time';
      gBadge.textContent = `${pid}${cat} · ${liveState}`;
      nameWrap.append(gName, gBadge);
      cardHead.append(av.root, nameWrap);

      const postRow = createInfoRow('Assigned Post:');
      setText(postRow.val, group.label + (group.address ? ` (${group.address})` : ''));
      const phoneRow = createInfoRow('Contact Number:');
      setText(phoneRow.val, (g.mobile_number || g.contact_number || '').trim() || '—');
      const addrRow = createInfoRow('Home Address:');
      setText(addrRow.val, (g.complete_address || '').trim() || '—');
      const emergRow = createInfoRow('Emergency Contact:');
      setText(emergRow.val, (g.emergency_contact || '').trim() || '—');

      card.append(cardHead, postRow.row, phoneRow.row, addrRow.row, emergRow.row);
      const histBtn = document.createElement('button');
      histBtn.type = 'button';
      histBtn.className = 'tracking-focus-guard-btn';
      histBtn.style.marginRight = '6px';
      histBtn.textContent = 'Location History';
      histBtn.onclick = () => openGuardLocationHistory(g.user_id, g);
      card.appendChild(histBtn);
      if (Number.isFinite(Number(g.latitude)) && Number.isFinite(Number(g.longitude))) {
        const focusBtn = document.createElement('button');
        focusBtn.type = 'button';
        focusBtn.className = 'tracking-focus-guard-btn';
        focusBtn.textContent = 'Zoom to Guard Marker';
        focusBtn.onclick = () => {
          map?.setView([Number(g.latitude), Number(g.longitude)], 18);
          entries.get(g.user_id)?.marker?.openPopup();
        };
        card.appendChild(focusBtn);
      }
      grid.appendChild(card);
    });
    ui.panel.appendChild(grid);
  }

  function renderLocationMarkersAndChips() {
    if (!siteLocations.length) return;
    const ui = ensureLocationProfilesUi();
    if (!ui) return;
    const groups = buildLocationGroups(allOnDutyRows());
    const query = search?.value || '';
    const matchingGroups = [...groups.entries()].filter(([, grp]) => groupMatchesQuery(grp, query));

    ui.sitesBar.replaceChildren();
    if (!groups.size) {
      ui.sitesBar.hidden = true;
      if (ui.companyDir) ui.companyDir.hidden = true;
      return;
    }

    // 1. Top Quick-Jump Chips Bar above the Map
    ui.sitesBar.hidden = false;
    const labelSpan = document.createElement('span');
    labelSpan.className = 'tracking-site-chips-label';
    labelSpan.textContent = `Companies & Deployment Sites (${matchingGroups.length}):`;
    ui.sitesBar.appendChild(labelSpan);

    for (const [key, grp] of matchingGroups) {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'tracking-site-chip' + (selectedSiteKey === key ? ' is-active' : '');
      chip.dataset.siteKey = key;
      chip.textContent = `${grp.label} (${grp.guards.size} on duty)`;
      chip.onclick = () => openLocationGuardsProfile(key, true);
      ui.sitesBar.appendChild(chip);
    }

    // 2. Map Building / Company Markers
    for (const [existingKey, existingEntry] of siteEntries) {
      if (!groups.has(existingKey)) {
        if (siteLayer && typeof siteLayer.removeLayer === 'function') {
          siteLayer.removeLayer(existingEntry.marker);
        }
        siteEntries.delete(existingKey);
      }
    }
    for (const [key, grp] of groups) {
      if (map && siteLayer && Number.isFinite(grp.lat) && Number.isFinite(grp.lng) && !siteEntries.has(key)) {
        const pinEl = document.createElement('div');
        pinEl.className = 'tracking-site-pin' + (selectedSiteKey === key ? ' is-active' : '');
        pinEl.title = `${grp.label} (${grp.guards.size} on duty)`;
        pinEl.textContent = `${grp.label} (${grp.guards.size})`;
        const icon = typeof L.divIcon === 'function'
          ? L.divIcon({ className: 'tracking-site-pin-shell', html: pinEl, iconSize: [130, 30], iconAnchor: [65, 15] })
          : undefined;
        const sMarker = typeof L.marker === 'function' && icon
          ? L.marker([grp.lat, grp.lng], { icon })
          : L.circleMarker([grp.lat, grp.lng], { radius: 9, color: '#991b1b', fillColor: '#dc2626', fillOpacity: 0.9 });
        sMarker.addTo(siteLayer);
        if (typeof sMarker.on === 'function') {
          sMarker.on('click', () => openLocationGuardsProfile(key, true));
        }
        pinEl.addEventListener('click', (ev) => {
          ev.stopPropagation();
          openLocationGuardsProfile(key, true);
        });
        siteEntries.set(key, { marker: sMarker, pinEl });
      } else if (siteEntries.has(key)) {
        const entryObj = siteEntries.get(key);
        if (Number.isFinite(grp.lat) && Number.isFinite(grp.lng)) {
          entryObj.marker?.setLatLng?.([grp.lat, grp.lng]);
        }
        entryObj.pinEl.textContent = `${grp.label} (${grp.guards.size})`;
        entryObj.pinEl.title = `${grp.label} (${grp.guards.size} on duty)`;
        entryObj.pinEl.classList.toggle('is-active', selectedSiteKey === key);
      }
    }

    // 3. Left Sidebar Company & Deployment Sites List (Searchable + Expandable Real-Time Personnel)
    if (ui.companyDir) {
      ui.companyDir.hidden = false;
      ui.companyDir.replaceChildren();
      const headEl = document.createElement('div');
      headEl.className = 'tracking-section-heading';
      const headTitle = document.createElement('span');
      headTitle.textContent = `Deployment Sites & Locations (${matchingGroups.length})`;
      const headHint = document.createElement('span');
      headHint.textContent = 'Click site for on-duty guards';
      headEl.append(headTitle, headHint);
      ui.companyDir.appendChild(headEl);

      if (!matchingGroups.length) {
        const noSite = document.createElement('p');
        noSite.className = 'tracking-company-empty';
        noSite.textContent = 'No deployment sites match your search.';
        ui.companyDir.appendChild(noSite);
      } else {
        for (const [key, grp] of matchingGroups) {
          const isSelected = selectedSiteKey === key;
          const card = document.createElement('div');
          card.className = 'tracking-company-card' + (isSelected ? ' is-active' : '');
          card.dataset.siteKey = key;
          card.setAttribute('role', 'button');
          card.tabIndex = 0;

          const cardHead = document.createElement('div');
          cardHead.className = 'tracking-company-head';
          const titleWrap = document.createElement('div');
          titleWrap.className = 'tracking-company-title-wrap';
          const iconSpan = document.createElement('span');
          iconSpan.className = 'tracking-company-icon material-symbols-rounded';
          iconSpan.setAttribute('aria-hidden', 'true');
          iconSpan.textContent = 'business';
          const copyWrap = document.createElement('div');
          const nameEl = document.createElement('div');
          nameEl.className = 'tracking-company-name';
          nameEl.textContent = grp.label;
          const addrEl = document.createElement('div');
          addrEl.className = 'tracking-company-addr';
          addrEl.textContent = (grp.address || 'Designated deployment location') + (grp.radius ? ` · ${grp.radius} m` : '');
          copyWrap.append(nameEl, addrEl);
          titleWrap.append(iconSpan, copyWrap);

          const countBadge = document.createElement('span');
          countBadge.className = 'tracking-company-badge' + (grp.guards.size > 0 ? ' has-onduty' : '');
          countBadge.textContent = `${grp.guards.size} On Duty`;
          cardHead.append(titleWrap, countBadge);
          card.appendChild(cardHead);

          // Inline Real-Time Assigned Personnel Roster (shown when clicked)
          const roster = document.createElement('div');
          roster.className = 'tracking-company-roster';
          roster.hidden = !isSelected;
          const guardsArr = [...grp.guards.values()];
          if (!guardsArr.length) {
            const emptyP = document.createElement('p');
            emptyP.className = 'tracking-company-empty';
            emptyP.textContent = 'No personnel currently on duty in real time at this location.';
            roster.appendChild(emptyP);
          } else {
            guardsArr.forEach(g => {
              const gRow = document.createElement('div');
              gRow.className = 'tracking-company-guard-row';
              const gLeft = document.createElement('div');
              gLeft.className = 'tracking-company-guard-left';
              const ring = g.state === 'waiting' ? 'gray' : (g.ageSeconds > 300 ? 'amber' : 'green');
              const av = createAvatarDom('tracking-list-avatar');
              syncAvatarDom(av, g, ring);
              const gMeta = document.createElement('div');
              gMeta.className = 'tracking-company-guard-meta';
              const gStrong = document.createElement('strong');
              gStrong.textContent = g.guard_name || 'Guard';
              const gSub = document.createElement('span');
              const statusLabel = g.state === 'waiting' ? 'On Duty · Waiting for GPS' : `On Duty · Live (${g.ageSeconds ?? 0}s ago)`;
              gSub.textContent = statusLabel + ((g.mobile_number || g.contact_number) ? ` · ${g.mobile_number || g.contact_number}` : '');
              gMeta.append(gStrong, gSub);
              gLeft.append(av.root, gMeta);
              gRow.appendChild(gLeft);
              roster.appendChild(gRow);
            });
          }
          card.appendChild(roster);

          const activateSite = (ev) => {
            if (ev.type === 'keydown' && ev.key !== 'Enter' && ev.key !== ' ') return;
            if (ev.type === 'keydown') ev.preventDefault();
            openLocationGuardsProfile(key, true);
          };
          card.addEventListener('click', activateSite);
          card.addEventListener('keydown', activateSite);
          ui.companyDir.appendChild(card);
        }
      }
    }

    if (selectedSiteKey && groups.has(selectedSiteKey)) {
      openLocationGuardsProfile(selectedSiteKey, false);
    }
  }

  function clear(message) { clearTimeout(accessExpiryTimer);rows=[]; render(); status.textContent=message; }

  function render() {
    const visible=window.LiveTrackingModel.visible(rows,search.value,serverClock.now())
      .map(row=>interrupted&&row.state!=='waiting'?{...row,state:'stale'}:row);
    const keys=new Set(visible.map(row=>row.user_id));
    for(const [key,entry] of entries) {
      if(keys.has(key))continue;
      entry.motion?.stop();
      entry.item.remove();
      if(entry.marker) { layer.removeLayer(entry.marker); layer.removeLayer(entry.circle); }
      entries.delete(key);
    }
    const waiting=visible.filter(r=>r.state==='waiting').length;
    setText(document.getElementById('guardCount'),`${visible.length} on duty · ${visible.filter(r=>r.state==='live').length} live${waiting?` · ${waiting} waiting for GPS`:''}`);
    if(visible.length)empty.remove();
    else if(!empty.parentNode)list.append(empty);
    visible.forEach((row,index)=>{
      recordGuardHistoryPoint(row);
      const ring=window.LiveTrackingModel.markerRing
        ? window.LiveTrackingModel.markerRing(row,{offline:row.offline===true||row.state==='offline'||row.state==='waiting'})
        : (row.state==='waiting'?'gray':(row.ageSeconds>300?'amber':'green'));
      const color=row.state==='live'&&!row.approximate?'#137c52':(ring==='gray'?'#6b7280':'#a66210');
      const ringHex=RING_HEX[ring]||RING_HEX.green;
      let entry=entries.get(row.user_id);
      if(!entry) {
        const item=document.createElement('button'); item.type='button'; item.className='tracking-guard';
        const itemHead=document.createElement('div'); itemHead.className='tracking-guard-head';
        const listAvatar=createAvatarDom('tracking-list-avatar');
        const name=document.createElement('strong'); name.className='tracking-guard-name';
        itemHead.append(listAvatar.root,name);
        const clientRow=createInfoRow('Client (Name of the Company):');
        const locRow=createInfoRow('Location:');
        const contactRow=createInfoRow('Contact Number:');
        const statusRow=createInfoRow('Status:', 'tracking-status-row');
        const detail=statusRow.val;
        const waitingNote=document.createElement('span'); waitingNote.className='tracking-waiting-note';
        item.append(itemHead,clientRow.row,locRow.row,contactRow.row,statusRow.row,waitingNote);

        const popup=document.createElement('div'); popup.className='tracking-popup-card';
        const popupHead=document.createElement('div'); popupHead.className='tracking-popup-head';
        const popupAvatar=createAvatarDom('tracking-popup-avatar');
        const title=document.createElement('strong'); title.className='tracking-popup-title';
        popupHead.append(popupAvatar.root,title);
        const popupClientRow=createInfoRow('Client (Name of the Company):');
        const popupLocRow=createInfoRow('Location:');
        const popupContactRow=createInfoRow('Contact Number:');
        const popupStatusRow=createInfoRow('Status:', 'tracking-status-row');
        const popupDetail=popupStatusRow.val;
        const popupWaitingNote=document.createElement('span'); popupWaitingNote.className='tracking-waiting-note';
        const popupHistBtn=document.createElement('button'); popupHistBtn.type='button'; popupHistBtn.className='tracking-focus-guard-btn'; popupHistBtn.textContent='Location History';
        popupHistBtn.onclick=(ev)=>{ev.stopPropagation();openGuardLocationHistory(row.user_id,entry.row||row);};
        popup.append(popupHead,popupClientRow.row,popupLocRow.row,popupContactRow.row,popupStatusRow.row,popupWaitingNote,popupHistBtn);

        entry={item,listAvatar,name,clientRow,locRow,contactRow,statusRow,detail,waitingNote,
               popup,popupAvatar,title,popupClientRow,popupLocRow,popupContactRow,popupStatusRow,popupDetail,popupWaitingNote,
               markerAvatar:null};
        entries.set(row.user_id,entry);
      }
      if(map && row.state!=='waiting' && !entry.marker) {
          entry.circle=L.circle([row.latitude,row.longitude],{radius:row.accuracy_meters,color,weight:1,fillOpacity:0.08}).addTo(layer);
          // Circular photo / colored-initials marker replacing the plain dot, keeping open popups mounted on update.
          if(typeof L.marker==='function' && typeof L.divIcon==='function') {
            entry.markerAvatar=createAvatarDom('tracking-map-marker-avatar');
            syncAvatarDom(entry.markerAvatar,row,ring);
            const icon=L.divIcon({
              className:'tracking-avatar-marker-shell',
              html:entry.markerAvatar.root,
              iconSize:[42,42],
              iconAnchor:[21,21],
              popupAnchor:[0,-22]
            });
            entry.marker=L.marker([row.latitude,row.longitude],{icon,color,ringColor:ringHex}).addTo(layer).bindPopup(entry.popup,{autoPan:false});
          } else {
            entry.marker=L.circleMarker([row.latitude,row.longitude],{radius:8,color,fillColor:color,fillOpacity:0.85}).addTo(layer).bindPopup(entry.popup,{autoPan:false});
          }
          entry.motion=window.LiveMarkerMotion?.create({marker:entry.marker,circle:entry.circle});
          entry.item.onclick=()=>{
            if(entry.row.state==='waiting'||entry.row.state==='offline')return;
            map.setView([entry.row.latitude,entry.row.longitude],16);
            entry.marker.openPopup();
          };
          if(typeof entry.marker?.on==='function') {
            entry.marker.on('click',()=>{
              map.setView([entry.row.latitude,entry.row.longitude],17);
              const parsed=parseGuardLocation(entry.row);
              const groups=buildLocationGroups(window.LiveTrackingModel.visible(rows,search.value,serverClock.now()));
              for(const [k,grp] of groups) {
                if(grp.label.toLowerCase()===parsed.client.toLowerCase()) {
                  openLocationGuardsProfile(k,false);
                  break;
                }
              }
            });
          }
      }
      if(row.state==='waiting' && entry.marker) {
        entry.motion?.stop();layer.removeLayer(entry.marker);layer.removeLayer(entry.circle);
        entry.marker=null;entry.circle=null;entry.markerAvatar=null;entry.motion=null;entry.item.onclick=null;
      }
      entry.item.disabled=row.state==='waiting';
      const previous=entry.row;
      if(previous&&previous.state!=='waiting'&&row.state!=='waiting'&&(previous.latitude!==row.latitude||previous.longitude!==row.longitude)) {
        const duration=row.state==='live'
          ? Math.min(4500,Math.max(500,Date.parse(row.captured_at)-Date.parse(previous.captured_at))) : 0;
        if(entry.motion)entry.motion.moveTo([row.latitude,row.longitude],{duration});
        else {
          entry.marker?.setLatLng([row.latitude,row.longitude]);
          entry.circle?.setLatLng([row.latitude,row.longitude]);
        }
      }
      if(previous&&previous.accuracy_meters!==row.accuracy_meters)entry.circle?.setRadius(row.accuracy_meters);
      if(previous&&(entry.color!==color||entry.ring!==ring)) {
        if(entry.marker?.options){entry.marker.options.color=color;entry.marker.options.ringColor=ringHex;}
        if(typeof entry.marker?.setStyle==='function')entry.marker.setStyle({color,fillColor:color});
        entry.circle?.setStyle({color});
      }
      entry.row=row; entry.color=color; entry.ring=ring;

      syncAvatarDom(entry.listAvatar,row,ring);
      syncAvatarDom(entry.popupAvatar,row,ring);
      if(entry.markerAvatar)syncAvatarDom(entry.markerAvatar,row,ring);

      const parsedLoc=parseGuardLocation(row);
      const contactNumber=(row.mobile_number||row.contact_number||'').trim()||'—';

      setText(entry.name,row.guard_name||'Guard');
      setText(entry.clientRow.val,parsedLoc.client);
      setText(entry.locRow.val,parsedLoc.location);
      setText(entry.contactRow.val,contactNumber);

      const detailClass=row.state==='offline'?'tracking-offline':`tracking-${row.state}`;
      const statusText=row.state==='waiting'
        ? 'On duty · Waiting for GPS'
        : row.state==='offline'
        ? 'Offline'
        : `${row.state==='live'?'Live':'Last known location'}${row.approximate?' · Approximate':''} · ${row.ageSeconds}s ago · ±${Math.round(row.accuracy_meters)} m`;

      if(entry.detail.className!==`tracking-info-val ${detailClass}`)entry.detail.className=`tracking-info-val ${detailClass}`;
      setText(entry.detail,statusText);
      entry.waitingNote.hidden=row.state!=='waiting';
      setText(entry.waitingNote,row.state==='waiting'?'No location received from the guard app yet.':'');

      setText(entry.title,entry.name.textContent);
      setText(entry.popupClientRow.val,parsedLoc.client);
      setText(entry.popupLocRow.val,parsedLoc.location);
      setText(entry.popupContactRow.val,contactNumber);
      if(entry.popupDetail.className!==`tracking-info-val ${detailClass}`)entry.popupDetail.className=`tracking-info-val ${detailClass}`;
      setText(entry.popupDetail,statusText);
      entry.popupWaitingNote.hidden=row.state!=='waiting';
      setText(entry.popupWaitingNote,entry.waitingNote.textContent);
      // Keep the focused list item, map layers and open popup mounted during updates.
      if(list.children[index]!==entry.item)list.insertBefore(entry.item,list.children[index]||null);
    });
    renderLocationMarkersAndChips(visible);
    if(map&&!hasFit&&(visible.some(r=>r.state!=='waiting')||siteLocations.some(l=>l.active!==false&&Number.isFinite(Number(l.latitude??l.lat))&&Number.isFinite(Number(l.longitude??l.lng))))) { fit();hasFit=true; }
  }
  function fit() {
    const points=window.LiveTrackingModel.visible(rows,search.value,serverClock.now()).filter(r=>r.state!=='waiting').map(r=>[r.latitude,r.longitude]);
    if(!points.length&&siteLocations.length) {
      siteLocations.forEach(loc=>{
        if(loc.active===false)return;
        const lat=Number(loc.latitude??loc.lat),lng=Number(loc.longitude??loc.lng);
        if(Number.isFinite(lat)&&Number.isFinite(lng))points.push([lat,lng]);
      });
    }
    if(map&&points.length) map.fitBounds(points,{padding:[35,35],maxZoom:16});
  }
  function schedulePoll() {
    clearTimeout(timer);
    // Recheck visibility and access even when no location broadcasts arrive.
    if(!stopped&&!document.hidden)timer=setTimeout(refresh,interrupted?5000:reconcileMs);
  }
  function scheduleRefresh() {
    if(stopped||document.hidden||refreshTimer)return;
    refreshTimer=setTimeout(()=>{refreshTimer=null;refresh();},realtimeBatchMs);
  }
  function transientError(error) {
    if([401,403].includes(error?.status)||['42501','PGRST301','PGRST302','PGRST303'].includes(error?.code))return false;
    return error?.status===408||(error?.status>=500&&error.status<=599)||error?.name==='TimeoutError'||
      (error?.name==='TypeError'&&/fetch|network|load failed/i.test(error.message||''))||
      /^(?:TypeError:\s*)?(?:Failed to fetch|NetworkError\b|Network request failed|Load failed|fetch failed)/i.test(error?.message||'');
  }
  function cancelPendingRequests() {
    requestGeneration++;
    requestController?.abort();
    clearTimeout(retryTimer);retryTimer=null;
    retryResolve?.(false);retryResolve=null;
  }
  function waitForRetry() {
    return new Promise(resolve=>{
      retryResolve=resolve;
      retryTimer=setTimeout(()=>{retryTimer=null;retryResolve=null;resolve(true);},retryMs);
    });
  }
  async function fetchLocations() {
    const controller=new AbortController();requestController=controller;
    let timeout;
    try {
      const interrupted=new Promise((_,reject)=>{
        controller.signal.addEventListener('abort',()=>reject(controller.signal.reason||new DOMException('Request cancelled.','AbortError')),{once:true});
        timeout=setTimeout(()=>controller.abort(new DOMException('Location request timed out.','TimeoutError')),requestTimeoutMs);
      });
      let request=client.rpc('live_guard_map_snapshot');
      if(typeof request.abortSignal==='function')request=request.abortSignal(controller.signal);
      const result=await Promise.race([request,interrupted]);
      if(result.error)throw {...result.error,status:result.status??result.error.status};
      if(!result.data||!Array.isArray(result.data.locations)||!Number.isFinite(Date.parse(result.data.server_now))) {
        throw new Error('Invalid live map snapshot. Reload the page.');
      }
      return result.data;
    } finally {
      clearTimeout(timeout);
      if(requestController===controller)requestController=null;
    }
  }
  async function refresh() {
    if(stopped||document.hidden) return;
    if(loading) {refreshAgain=true;return;}
    clearTimeout(timer);
    loading=true; refreshButton.disabled=true;
    const generation=requestGeneration;
    try {
      let nextRows;
      try { nextRows=await fetchLocations(); }
      catch(error) {
        if(stopped||document.hidden||generation!==requestGeneration)return;
        if(!transientError(error))throw error;
        status.textContent='Connection interrupted. Retrying locations…';
        interrupted=true;render();
        // Keep the same markers through one brief transport retry. Access failures
        // and a confirmed empty server response still clear protected locations.
        if(!await waitForRetry()||stopped||document.hidden||generation!==requestGeneration)return;
        nextRows=await fetchLocations();
      }
      if(stopped||document.hidden||generation!==requestGeneration)return;
      clearTimeout(accessExpiryTimer);interrupted=false;lastAuthorizedAt=performance.now();
      serverClock.sync(nextRows.server_now);
      rows=nextRows.locations; render();
      status.textContent=connected?'Live updates connected. Locations update in place.':'Realtime reconnecting. Checking locations every 30 seconds…';
    } catch(error) {
      if(!stopped&&!document.hidden&&generation===requestGeneration) {
        const remaining=lastAuthorizedAt+60000-performance.now();
        if(transientError(error)&&rows.length&&remaining>0) {
          interrupted=true;render();
          status.textContent='Connection interrupted. Showing last known locations; retrying…';
          clearTimeout(accessExpiryTimer);
          accessExpiryTimer=setTimeout(()=>clear('Location data unavailable. Reconnect to verify access and locations.'),remaining);
        } else clear('Location data unavailable. Check your connection and access, then retry.');
      }
    }
    finally {
      loading=false;refreshButton.disabled=false;
      schedulePoll();
      if(refreshAgain&&!stopped){refreshAgain=false;scheduleRefresh();}
    }
  }
  async function stop() {
    stopped=true;cancelPendingRequests();clearTimeout(timer);clearTimeout(refreshTimer);clearInterval(ageTimer);clear('Location view closed.');
    authSubscription?.unsubscribe();
    if(channel) await client.removeChannel(channel);
  }
  const urlParam = new URLSearchParams(window.location.search).get('guard') || new URLSearchParams(window.location.search).get('q');
  if (urlParam && search) search.value = urlParam;
  search.addEventListener('input',render);
  document.getElementById('fitGuards').onclick=fit;
  window.addEventListener('pagehide',stop,{once:true});
  document.addEventListener('visibilitychange',()=>{
    if(document.hidden){
      for(const entry of entries.values())entry.motion?.stop({finish:true});
      cancelPendingRequests();clearTimeout(timer);clearTimeout(refreshTimer);refreshTimer=null;
    }
    else if(client&&!stopped){render();refresh();}
  });
  if(!window.SENTINEL_LIVE_TRACKING_ENABLED) {
    clear('Live tracking is unavailable. Reload the page.');return;
  }
  ageTimer=setInterval(()=>{if(!stopped&&!document.hidden)render();},10000);
  if(window.L) {
    map=L.map('trackingMap').setView([14.5995,120.9842],12);
    map.attributionControl?.setPrefix(false);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{
      attribution:'© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',maxZoom:19
    }).on('tileerror',()=>{document.getElementById('mapNotice').textContent='Map tiles unavailable. Please try again shortly.';}).addTo(map);
    layer=L.layerGroup().addTo(map);
    siteLayer=L.layerGroup().addTo(map);
  } else document.getElementById('mapNotice').textContent='Map library unavailable. Check your internet connection.';
  if(window.SENTINEL_LIVE_TRACKING_DEMO && ['localhost','127.0.0.1','[::1]'].includes(location.hostname)) {
    document.getElementById('demoNotice').hidden=false;
    let tick=0;
    const update=()=>{
      tick++;
      serverClock.sync(new Date().toISOString());
      rows=[
        {guard_name:'Demo guard A',location_label:'Balboa · Eroreco - Queen of Mercy Hospital Turning Point, Camia Street, Bacolod',mobile_number:'09171234561',ageMs:0},
        {guard_name:'Demo guard B',location_label:'Jollibee Main · Lacson Street, Bacolod, Negros Occidental',mobile_number:'09181234562',ageMs:45000},
        {guard_name:'Demo guard C',location_label:'SM City Bacolod · Reclamation Area, Bacolod, Negros Occidental',mobile_number:'09191234563',ageMs:360000}
      ].map((demo,i)=>({
        user_id:String(i),guard_name:demo.guard_name,location_label:demo.location_label,mobile_number:demo.mobile_number,
        latitude:14.5995+i*0.007+Math.sin(tick/4+i)*0.001,longitude:120.9842+i*0.009,
        accuracy_meters:100,captured_at:new Date(Date.now()-demo.ageMs).toISOString(),
        received_at:new Date(Date.now()-demo.ageMs).toISOString(),duty_end_at:new Date(Date.now()+3600000).toISOString()
      }));
      render();status.textContent='Local simulation running · no real GPS or database connection.';
    };
    client={rpc:async()=>({data:{server_now:new Date().toISOString(),locations:rows}})};refreshButton.onclick=update;update();timer=setInterval(update,5000);return;
  }
  client=window.appSupabase;
  if(!client || !['localhost','127.0.0.1','[::1]','syyofdcynuzgergqlaqj.supabase.co'].includes(new URL(client.supabaseUrl).hostname)) {
    clear('Live tracking is unavailable for this connection.');return;
  }
  try {
    const {data,error}=await client.auth.getUser();
    if(error||!data.user) { location.href='../staff/login.html';return; }
    const profile=await client.from('profiles').select('role,active').eq('id',data.user.id).single();
    if(profile.error||!profile.data.active||!['admin','inspector'].includes(profile.data.role)) {
      clear('Only active Operations Heads and assigned Inspectors can view live locations.');return;
    }
    authSubscription=client.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT')stop();}).data?.subscription;
    function loadSiteAndProfileCatalog() {
      try {
        const locQuery=client.from('locations')?.select('id,label,address,latitude,longitude,radius,active');
        const guardQuery=client.from('profiles')?.select('id,first_name,middle_initial,last_name,username,personnel_id,employment_category,contract_start_date,contract_end_date,mobile_number,complete_address,emergency_contact,profile_photo_url,assigned_location_id,role,active');
        if(typeof locQuery?.then==='function' && typeof guardQuery?.then==='function') {
          Promise.all([locQuery,guardQuery]).then(([locRes,guardRes])=>{
            if(Array.isArray(locRes?.data)) siteLocations=locRes.data;
            if(Array.isArray(guardRes?.data)) assignedGuards=guardRes.data;
            if(!stopped) render();
          }).catch(()=>{});
        }
      } catch(_) {}
    }
    refreshButton.onclick=()=>{ loadSiteAndProfileCatalog(); refresh(); };
    loadSiteAndProfileCatalog();
    channel=client.channel('live-guards:'+data.user.id,{config:{private:true}}).on('broadcast',{
      event:'location_changed'
    },scheduleRefresh).subscribe(state=>{
      if(stopped)return;
      connected=state==='SUBSCRIBED';
      schedulePoll();
      if(connected)scheduleRefresh();
      else status.textContent='Realtime disconnected. Checking locations every 30 seconds.';
    });
    await refresh();
  } catch(_) { clear('Could not open live tracking. Check your connection and sign in again.'); }
})();
