(async function() {
  'use strict';
  const status=document.getElementById('trackingStatus');
  const list=document.getElementById('guardList'), search=document.getElementById('guardSearch');
  const refreshButton=document.getElementById('refreshTracking');
  const entries=new Map();
  const serverClock=window.LiveTrackingModel.createServerClock();
  const reconcileMs=30000, realtimeBatchMs=1000, retryMs=500, requestTimeoutMs=10000;
  const AVATAR_PALETTE=['#b91c1c','#9f1239','#0f766e','#1d4ed8','#6d28d9','#b45309','#15803d','#334155'];
  const RING_HEX={green:'#16a34a',amber:'#f59e0b',gray:'#6b7280'};
  let rows=[],map,layer,channel,timer,ageTimer,refreshTimer,client,authSubscription,stopped=false,loading=false,refreshAgain=false,connected=false,hasFit=false;
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
        popup.append(popupHead,popupClientRow.row,popupLocRow.row,popupContactRow.row,popupStatusRow.row,popupWaitingNote);

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
    if(map&&!hasFit&&visible.some(r=>r.state!=='waiting')) { fit();hasFit=true; }
  }
  function fit() {
    const points=window.LiveTrackingModel.visible(rows,search.value,serverClock.now()).filter(r=>r.state!=='waiting').map(r=>[r.latitude,r.longitude]);
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
    refreshButton.onclick=refresh;
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
