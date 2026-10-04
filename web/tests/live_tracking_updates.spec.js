const {test,expect}=require('@playwright/test');
const path=require('node:path');

async function openTracking(page,{animate=false,serverOffset=0}={}) {
  await page.clock.install({time:new Date('2026-09-08T00:00:00Z')});
  await page.clock.pauseAt(new Date('2026-09-08T00:00:01Z'));
  await page.setContent(`
    <p id="trackingStatus"></p><p id="guardCount"></p>
    <input id="guardSearch"><button id="refreshTracking">Refresh</button><button id="fitGuards">Show all</button>
    <div id="guardList"></div><div id="trackingMap"></div><p id="mapNotice"></p><p id="demoNotice" hidden></p>`);
  await page.evaluate(serverOffset=>{
    window.serverOffset=serverOffset;
    window.SENTINEL_LIVE_TRACKING_ENABLED=true;
    window.locations=[{
      user_id:'guard-a',guard_name:'Guard A',location_label:'Main gate',latitude:14.6,longitude:120.98,
      accuracy_meters:114,captured_at:new Date(Date.now()+serverOffset-5000).toISOString(),
      received_at:new Date(Date.now()+serverOffset-5000).toISOString(),duty_end_at:new Date(Date.now()+serverOffset+3600000).toISOString()
    }];
    window.rpcCount=0; window.pendingRpc=null;
    window.appSupabase={
      supabaseUrl:'http://localhost:54321',
      auth:{
        getUser:async()=>({data:{user:{id:'viewer'}}}),
        onAuthStateChange:callback=>{
          window.authChange=callback;
          return {data:{subscription:{unsubscribe(){window.authUnsubscribed=true;}}}};
        }
      },
      from:()=>({select:()=>({eq:()=>({single:async()=>({data:{role:'inspector',active:true}})})})}),
      rpc:(name)=>{
        if(name!=='live_guard_map_snapshot')throw Error('Expected server-clock snapshot');
        window.rpcCount++;
        const response=(async()=>{
          if(window.holdRpc)await new Promise(resolve=>{window.pendingRpc=resolve;});
          const failure=window.rpcFailures?.shift();
          if(failure==='network')throw new TypeError('Failed to fetch');
          return {data:{locations:structuredClone(window.locations),server_now:new Date(window.snapshotTime??(Date.now()+window.serverOffset)).toISOString()},error:failure||window.rpcError||null};
        })();
        response.abortSignal=signal=>{window.lastRequestSignal=signal;return response;};
        return response;
      },
      channel:()=>({on(event,config,callback){window.broadcast=callback;return this;},subscribe(callback){window.connection=callback;return this;}}),
      removeChannel:async()=>{window.channelRemoved=true;}
    };
    window.markers=[]; window.circles=[];
    window.mapState={center:[0,0],zoom:0,fitCount:0,setViewCount:0};
    const addTo=function(){return this;};
    function shape(center,options) {
      return {center,options,addTo,getLatLng(){return {lat:this.center[0],lng:this.center[1]};},setLatLng(value){this.center=value;return this;},
        setRadius(value){this.options.radius=value;return this;},
        setStyle(value){Object.assign(this.options,value);return this;},
        bindPopup(content,config){this.popup=content;this.popupConfig=config;return this;},
        openPopup(){this.popupOpen=true;return this;}};
    }
    window.L={
      map:()=>({
        setView(center,zoom){Object.assign(window.mapState,{center,zoom});window.mapState.setViewCount++;return this;},
        fitBounds(){window.mapState.fitCount++;return this;}
      }),
      tileLayer:()=>({addTo,on(){return this;}}),
      layerGroup:()=>({addTo,removeLayer(marker){marker.removed=true;marker.popupOpen=false;}}),
      circleMarker:(center,options)=>{const marker=shape(center,options);window.markers.push(marker);return marker;},
      circle:(center,options)=>{const circle=shape(center,options);window.circles.push(circle);return circle;}
    };
  },serverOffset);
  await page.addScriptTag({path:path.resolve(__dirname,'../js/live-tracking-model.js')});
  if(animate)await page.addScriptTag({path:path.resolve(__dirname,'../js/live-marker-motion.js')});
  await page.addScriptTag({path:path.resolve(__dirname,'../js/live-tracking.js')});
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await page.evaluate(()=>window.connection('SUBSCRIBED'));
  await page.clock.runFor(1000);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(2);
}

test('age updates preserve guard focus, marker, popup and user map view',async({page})=>{
  await openTracking(page);
  await page.locator('.tracking-guard').click();
  await page.evaluate(()=>{
    window.originalItem=document.querySelector('.tracking-guard');
    window.originalMarker=window.markers[0];
    window.originalPopup=window.markers[0].popup;
    window.mapState.center=[14.7,121.0];window.mapState.zoom=13;
  });
  await page.clock.runFor(10000);
  await expect(page.locator('.tracking-guard')).toContainText('15s ago');
  expect(await page.evaluate(()=>({
    itemSame:window.originalItem===document.querySelector('.tracking-guard'),
    focused:document.activeElement===window.originalItem,markerCount:window.markers.length,
    popupSame:window.markers[0].popup===window.originalPopup,popupOpen:window.markers[0].popupOpen,
    view:window.mapState,rpcCount:window.rpcCount
  }))).toEqual({itemSame:true,focused:true,markerCount:1,popupSame:true,popupOpen:true,
    view:{center:[14.7,121.0],zoom:13,fitCount:1,setViewCount:2},rpcCount:2});
});

test('a real GPS update glides marker and accuracy circle without replacing either',async({page})=>{
  await openTracking(page,{animate:true});
  await page.locator('.tracking-guard').click();
  await page.evaluate(()=>{
    window.originalMarker=window.markers[0];
    window.originalCircle=window.circles[0];
    Object.assign(window.locations[0],{latitude:14.6002,captured_at:new Date().toISOString(),received_at:new Date().toISOString()});
    window.broadcast({});
  });
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).not.toContainText('14.60020');
  await page.clock.runFor(1000);
  const moving=await page.evaluate(()=>({lat:window.markers[0].center[0],circle:window.circles[0].center[0],popup:window.markers[0].popupOpen,count:window.markers.length}));
  expect(moving.lat).toBeGreaterThan(14.6);
  expect(moving.lat).toBeLessThan(14.6002);
  expect(moving.circle).toBe(moving.lat);
  expect(moving.popup).toBe(true);
  expect(moving.count).toBe(1);
  await page.clock.runFor(4500);
  expect(await page.evaluate(()=>window.markers[0].center[0])).toBeCloseTo(14.6002,8);
  await page.clock.runFor(1000);
  expect(await page.evaluate(()=>window.markers[0].center[0])).toBeCloseTo(14.6002,8);
});

test('removing a moving guard cancels animation without resurrecting the marker',async({page})=>{
  await openTracking(page,{animate:true});
  await page.evaluate(()=>{
    Object.assign(window.locations[0],{latitude:14.6002,captured_at:new Date().toISOString()});
    window.broadcast({});
  });
  await page.clock.runFor(1500);
  await page.evaluate(()=>{window.locations=[];window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  const removed=await page.evaluate(()=>window.markers[0].center);
  await page.clock.runFor(5000);
  expect(await page.evaluate(()=>window.markers[0].center)).toEqual(removed);
  expect(await page.evaluate(()=>window.markers[0].removed)).toBe(true);
});

test('realtime bursts are batched and update coordinates and accuracy in place',async({page})=>{
  await openTracking(page);
  await page.locator('.tracking-guard').click();
  await page.evaluate(()=>{
    window.originalItem=document.querySelector('.tracking-guard');
    Object.assign(window.locations[0],{latitude:14.61,longitude:120.99,accuracy_meters:20,guard_name:'Updated <script>'});
    for(let i=0;i<25;i++)window.broadcast({});
  });
  await page.clock.runFor(999);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(2);
  await page.clock.runFor(1);
  await expect(page.locator('.tracking-guard')).toContainText('±20 m');
  await expect(page.locator('.tracking-guard')).not.toContainText('14.61000, 120.99000');
  await expect(page.locator('.tracking-guard')).not.toContainText('Approximate');
  expect(await page.evaluate(()=>({count:window.rpcCount,markerCount:window.markers.length,
    itemSame:window.originalItem===document.querySelector('.tracking-guard'),
    center:window.markers[0].center,color:window.markers[0].options.color,
    radius:window.circles[0].options.radius,popupOpen:window.markers[0].popupOpen,
    popupText:window.markers[0].popup.textContent
  }))).toMatchObject({count:3,markerCount:1,itemSame:true,center:[14.61,120.99],color:'#137c52',radius:20,popupOpen:true});
  await expect(page.locator('.tracking-guard strong')).toHaveText('Updated <script>');
});

test('silent reconciliation still checks access every 30 seconds and reconnecting continues',async({page})=>{
  await openTracking(page);
  await page.clock.runFor(29000);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(2);
  await page.clock.runFor(1000);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(3);
  await page.evaluate(()=>window.connection('CHANNEL_ERROR'));
  await page.clock.runFor(30000);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(4);
  await expect(page.locator('#trackingStatus')).toContainText('30 seconds');
});

test('expiry and server removals clear only affected guards',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{
    window.originalItem=document.querySelector('.tracking-guard');
    window.locations.push({...window.locations[0],user_id:'guard-b',guard_name:'Guard B',duty_end_at:new Date(Date.now()+4000).toISOString()});
    window.broadcast({});
  });
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(2);
  await page.clock.runFor(8000);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  expect(await page.evaluate(()=>window.originalItem===document.querySelector('.tracking-guard'))).toBe(true);
  expect(await page.evaluate(()=>window.markers[1].removed)).toBe(true);
  await page.evaluate(()=>{window.locations=[];window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  await expect(page.locator('.tracking-empty')).toHaveCount(1);
});

test('search keeps matching guards mounted and fetching failure clears protected data',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.originalItem=document.querySelector('.tracking-guard');});
  await page.locator('#guardSearch').fill('main');
  expect(await page.evaluate(()=>window.originalItem===document.querySelector('.tracking-guard'))).toBe(true);
  await page.evaluate(()=>{window.rpcError={message:'Access denied'};window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  await expect(page.locator('#trackingStatus')).toContainText('connection and access');
  expect(await page.evaluate(()=>window.markers[0].removed)).toBe(true);
});

test('one transient failure retries without removing the marker, list item or open popup',async({page})=>{
  await openTracking(page);
  await page.locator('.tracking-guard').click();
  await page.evaluate(()=>{
    window.originalItem=document.querySelector('.tracking-guard');
    window.rpcFailures=['network'];window.broadcast({});
  });
  await page.clock.runFor(1000);
  await expect(page.locator('#trackingStatus')).toContainText('Retrying locations');
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await page.clock.runFor(499);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(3);
  await page.clock.runFor(1);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(4);
  await expect(page.locator('#trackingStatus')).toContainText('Live updates connected');
  expect(await page.evaluate(()=>({same:window.originalItem===document.querySelector('.tracking-guard'),
    markerCount:window.markers.length,removed:!!window.markers[0].removed,popupOpen:window.markers[0].popupOpen})))
    .toEqual({same:true,markerCount:1,removed:false,popupOpen:true});
});

test('repeated transient failures retain last known marker and recover without flicker',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.rpcFailures=['network','network'];window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await page.clock.runFor(500);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await expect(page.locator('.tracking-guard')).toContainText('Last known location');
  expect(await page.evaluate(()=>window.rpcCount)).toBe(4);
  await page.clock.runFor(5000);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(5);
  expect(await page.evaluate(()=>window.markers.length)).toBe(1);
});

test('an outage never preserves protected coordinates beyond the access cache deadline',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.rpcError={status:503,message:'Unavailable'};window.broadcast({});});
  await page.clock.runFor(2000);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await page.clock.runFor(60000);
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  expect(await page.evaluate(()=>window.markers[0].removed)).toBe(true);
});

test('guard waiting for GPS gets a list entry and only gains a marker with real coordinates',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{
    window.locations.push({...window.locations[0],user_id:'guard-b',guard_name:'Guard B',latitude:null,longitude:null,accuracy_meters:null,captured_at:null,received_at:null});
    window.broadcast({});
  });
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(2);
  await expect(page.locator('.tracking-guard').nth(1)).toContainText('Waiting for GPS');
  await expect(page.locator('.tracking-guard').nth(1)).toBeDisabled();
  expect(await page.evaluate(()=>window.markers.length)).toBe(1);
  await page.evaluate(()=>{
    window.waitingItem=document.querySelectorAll('.tracking-guard')[1];
    Object.assign(window.locations[1],{latitude:14.61,longitude:120.99,accuracy_meters:20,captured_at:new Date().toISOString(),received_at:new Date().toISOString()});
    window.broadcast({});
  });
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard').nth(1)).toBeEnabled();
  await expect(page.locator('.tracking-guard').nth(1)).not.toContainText('14.61000');
  await expect(page.locator('.tracking-guard').nth(1)).not.toContainText('120.99000');
  expect(await page.evaluate(()=>window.markers.length)).toBe(2);
  expect(await page.evaluate(()=>window.waitingItem===document.querySelectorAll('.tracking-guard')[1])).toBe(true);
});

test('server errors retry, but explicit access errors clear immediately without retry',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.rpcFailures=[{status:503,message:'Unavailable'}];window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await page.clock.runFor(500);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(4);
  await page.evaluate(()=>{window.rpcError={status:403,code:'42501',message:'Access denied'};window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  await page.clock.runFor(500);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(5);
});

test('sign out during the retry delay cancels the request without restoring locations',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.rpcFailures=['network'];window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('#trackingStatus')).toContainText('Retrying locations');
  await page.evaluate(()=>window.authChange('SIGNED_OUT'));
  await page.clock.runFor(150000);
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(3);
  await expect(page.locator('#trackingStatus')).toHaveText('Location view closed.');
});

test('hiding during retry cancels it and resuming still refreshes',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.rpcFailures=['network'];window.broadcast({});});
  await page.clock.runFor(1000);
  await expect(page.locator('#trackingStatus')).toContainText('Retrying locations');
  await page.evaluate(()=>{
    Object.defineProperty(document,'hidden',{configurable:true,value:true});
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.clock.runFor(60000);
  expect(await page.evaluate(()=>window.rpcCount)).toBe(3);
  await page.evaluate(()=>{
    Object.defineProperty(document,'hidden',{configurable:true,value:false});
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(4);
  await expect(page.locator('#trackingStatus')).toContainText('Live updates connected');
});

test('a stalled request is aborted at its deadline and retried once',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.holdRpc=true;window.broadcast({});});
  await page.clock.runFor(1000);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(3);
  await page.evaluate(()=>{window.timedOutSignal=window.lastRequestSignal;});
  await page.clock.runFor(10000);
  await expect(page.locator('#trackingStatus')).toContainText('Retrying locations');
  expect(await page.evaluate(()=>window.timedOutSignal.aborted)).toBe(true);
  await page.evaluate(()=>{window.holdRpc=false;});
  await page.clock.runFor(500);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(4);
  await expect(page.locator('#trackingStatus')).toContainText('Live updates connected');
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  await page.evaluate(()=>window.pendingRpc());
  expect(await page.evaluate(()=>window.markers.length)).toBe(1);
});

test('sign out clears locations and cancels realtime, scheduled and in-flight refreshes',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.holdRpc=true;window.broadcast({});});
  await page.clock.runFor(1000);
  await expect.poll(()=>page.evaluate(()=>window.rpcCount)).toBe(3);
  await page.evaluate(()=>{window.authChange('SIGNED_OUT');window.pendingRpc();});
  await expect(page.locator('.tracking-guard')).toHaveCount(0);
  await page.evaluate(()=>window.broadcast({}));
  await page.clock.runFor(150000);
  expect(await page.evaluate(()=>({count:window.rpcCount,removed:window.channelRemoved,unsubscribed:window.authUnsubscribed})))
    .toEqual({count:3,removed:true,unsubscribed:true});
  await expect(page.locator('#trackingStatus')).toHaveText('Location view closed.');
});

for(const serverOffset of [120000,-7200000])test('server clock keeps GPS visible with viewer clock offset '+serverOffset,async({page})=>{
  await openTracking(page,{animate:true,serverOffset});
  await page.locator('.tracking-guard').click();
  for(let i=0;i<4;i++){
    await page.evaluate(()=>{
      const now=Date.now()+window.serverOffset;
      Object.assign(window.locations[0],{latitude:window.locations[0].latitude+0.0001,captured_at:new Date(now).toISOString(),received_at:new Date(now).toISOString()});
      window.broadcast({});
    });
    await page.clock.runFor(1000);await page.clock.runFor(10000);
    await expect(page.locator('.tracking-guard')).toHaveCount(1);
    expect(await page.evaluate(()=>({count:markers.length,removed:!!markers[0].removed,popup:markers[0].popupOpen}))).toEqual({count:1,removed:false,popup:true});
  }
});

test('computer clock jumps cannot hide an authorized marker between refreshes',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{window.snapshotTime=Date.now();window.holdRpc=true;});
  await page.clock.setSystemTime(new Date('2030-01-01T00:00:00Z'));
  await page.clock.runFor(10000);
  await expect(page.locator('.tracking-guard')).toHaveCount(1);
  expect(await page.evaluate(()=>!!markers[0].removed)).toBe(false);
});

test('guard information formats name, client, location, contact number, and status in sidebar and popup',async({page})=>{
  await openTracking(page);
  await page.evaluate(()=>{
    window.locations=[{
      user_id:'guard-formatted',guard_name:'Nicor Bea',
      location_label:'Balboa · Eroreco - Queen of Mercy Hospital Turning Point, Camia Street, Bacolod',
      mobile_number:'09123456789',latitude:14.6,longitude:120.98,accuracy_meters:15,
      captured_at:new Date().toISOString(),received_at:new Date().toISOString(),duty_end_at:new Date(Date.now()+3600000).toISOString()
    }];
    window.broadcast({});
  });
  await page.clock.runFor(1000);
  const card=page.locator('.tracking-guard');
  await expect(card.locator('strong')).toHaveText('Nicor Bea');
  await expect(card).toContainText('Client (Name of the Company): Balboa');
  await expect(card).toContainText('Location: Eroreco - Queen of Mercy Hospital Turning Point, Camia Street, Bacolod');
  await expect(card).toContainText('Contact Number: 09123456789');
  await expect(card).toContainText('Status: Live');

  await card.click();
  const popupText=await page.evaluate(()=>window.markers.find(m=>!m.removed).popup.textContent);
  expect(popupText).toContain('Nicor Bea');
  expect(popupText).toContain('Client (Name of the Company): Balboa');
  expect(popupText).toContain('Location: Eroreco - Queen of Mercy Hospital Turning Point, Camia Street, Bacolod');
  expect(popupText).toContain('Contact Number: 09123456789');
  expect(popupText).toContain('Status: Live');
});

