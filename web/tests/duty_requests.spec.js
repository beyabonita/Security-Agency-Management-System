const {test,expect}=require('@playwright/test');
const guard='11111111-1111-4111-8111-111111111111';
const cover='22222222-2222-4222-8222-222222222222';
async function prepare(page,kind='absence') {
  await page.route('**/notification-center.js',route=>route.fulfill({contentType:'text/javascript',body:''}));
  await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`
    window.calls=[];window.rpcError=null;window.deleteError=null;window.applyAdminRoleNavigation=()=>{};
    window.requestRows=[{id:'33333333-3333-4333-8333-333333333333',requester_id:'${guard}',requested_schedule_id:'duty',
      request_type:'${kind}',reason:'Family appointment <img src=x onerror=alert(1)>',status:'pending_admin',
      created_at:'2026-09-04T02:00:00Z',letter_path:'${guard}/letter.pdf',letter_name:'Request letter.pdf'}];
    const profiles=[{id:'${guard}',first_name:'Guard',last_name:'One',role:'user',active:true},
      {id:'${cover}',first_name:'Cover',last_name:'Guard',role:'user',active:true}];
    const duties=[{id:'duty',start_at:'2026-09-10T00:00:00Z',end_at:'2026-09-10T09:00:00Z',location_label:'Agency post'}];
    const makeQuery=table=>{const filters=[];const q={select:()=>q,order:()=>q,limit:()=>q,in:()=>q,
      eq:(key,value)=>{filters.push([key,value]);return q;},then:(resolve,reject)=>Promise.resolve({data:
        (table==='shift_swap_requests'?window.requestRows:table==='profiles'?(window.profileRows||profiles):table==='attendance_sessions'?(window.attendanceRows||[]):(window.dutyRows||duties))
        .filter(row=>filters.every(([key,value])=>row[key]===value)),error:null}).then(resolve,reject)};return q;};
    window.appSupabase={from:makeQuery,rpc:async(name,args)=>{window.calls.push({name,args});await new Promise(r=>setTimeout(r,200));
      if(window.rpcError)return {error:{message:window.rpcError}};
      window.requestRows=window.requestRows.map(r=>({...r,status:args.p_approve?'approved':'rejected',admin_note:args.p_note}));return {data:null,error:null};},
      storage:{from:bucket=>({createSignedUrl:async(path,ttl,options)=>{window.calls.push({bucket,path,ttl,options});return {data:{signedUrl:'https://syyofdcynuzgergqlaqj.supabase.co/storage/v1/object/sign/request-letters/'+path+'?token=test'},error:null};}})},
      functions:{invoke:async(name,args)=>{window.calls.push({name,args});await new Promise(r=>setTimeout(r,200));return window.deleteError?
        {error:{context:{json:async()=>({error:window.deleteError})}}}:{data:{ok:true},error:null};}}};
    window.firebase={auth:()=>({onAuthStateChanged:cb=>setTimeout(()=>cb({uid:'hr'}),0),signOut:async()=>{}}),
      firestore:()=>({collection:()=>({doc:()=>({get:async()=>({exists:true,data:()=>({role:'admin',active:true,firstName:'HR',lastName:'Tester'})})}),
        orderBy:()=>({onSnapshot:cb=>cb({forEach:()=>{}})})})})};
  `}));
}

test('Operations Head downloads private letter, filters requests and approves absence in dark mobile UI',async({page},info)=>{
  test.setTimeout(60_000);
  await prepare(page);
  await page.addInitScript(()=>localStorage.setItem('sentinel-link-theme','dark'));
  await page.setViewportSize({width:390,height:844});
  await page.goto('/admin/swaps.html');
  const card=page.locator('.duty-request-card');
  await expect(card).toContainText('Absence');
  await expect(card.locator('img')).toHaveCount(0);
  await page.getByLabel('Search requests').fill('not present');
  await expect(card).toHaveCount(0);
  await page.getByLabel('Search requests').fill('Guard One');
  await expect(card).toBeVisible();
  await page.route('**/storage/v1/object/sign/request-letters/**',r=>r.fulfill({contentType:'application/pdf',body:'%PDF-1.7'}));
  await page.getByRole('button',{name:/View letter/}).click();
  await expect.poll(()=>page.evaluate(()=>window.calls.filter(call=>call.bucket).length)).toBe(1);
  expect(await page.evaluate(()=>window.calls.find(call=>call.bucket).bucket)).toBe('request-letters');
  expect(await page.evaluate(()=>window.calls.find(call=>call.bucket).ttl)).toBe(120);
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.locator('.sl-dialog-btn', {hasText: 'Close'}).click();
  await page.getByRole('button',{name:'Approve',exact:true}).click();
  await expect(page.getByRole('dialog')).toContainText('Approve absence for the remaining duty period');
  await expect(page.getByRole('dialog')).toContainText('Other periods remain scheduled');
  await expect(page.getByLabel('Replacement Guard')).toHaveCount(0);
  await page.screenshot({path:info.outputPath('absence-approval-dark-mobile.png'),fullPage:true});
  await page.getByRole('button',{name:'Approve request',exact:true}).click();
  await expect(page.locator('.sl-toast').last()).toContainText('Guard has been notified');
  await page.getByRole('combobox',{name:'Status',exact:true}).selectOption('approved');
  await expect(card).toContainText('Approved');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(391);
});

test('swap approval requires replacement and leaves request pending on server conflict',async({page},info)=>{
  await prepare(page,'swap');await page.goto('/admin/swaps.html');
  await page.evaluate(()=>{window.calls=[];});
  await page.getByRole('button',{name:'Approve',exact:true}).click();
  await page.getByRole('button',{name:'Approve request',exact:true}).click();
  expect(await page.evaluate(()=>window.calls.length)).toBe(0);
  await page.getByLabel('Replacement Guard').selectOption(cover);
  await page.evaluate(()=>window.rpcError='The replacement Guard already has an overlapping duty.');
  await page.getByRole('button',{name:'Approve request',exact:true}).click();
  await expect(page.locator('.sl-toast').last()).toContainText('overlapping duty');
  await expect(page.locator('.duty-request-card')).toContainText('Awaiting Operations Head approval');
  expect(await page.evaluate(()=>window.calls.find(call=>call.name==='decide_duty_relief').args.p_replacement_guard_id)).toBe(cover);
  await page.screenshot({path:info.outputPath('swap-conflict-preserved.png'),fullPage:true});
});

test('replacement guard dropdown filters guards assigned to the same post / deployment', async ({page}) => {
  await prepare(page, 'swap');
  await page.addInitScript(({guard, cover}) => {
    window.profileRows = [
      { id: guard, first_name: 'Guard', last_name: 'One', role: 'user', active: true, assigned_location_id: 'loc-balboa' },
      { id: cover, first_name: 'Cover', last_name: 'Guard', role: 'user', active: true, assigned_location_id: 'loc-balboa' },
      { id: '33333333-3333-4333-8333-333333333334', first_name: 'Other', last_name: 'PostGuard', role: 'user', active: true, assigned_location_id: 'loc-chmsu' }
    ];
    window.dutyRows = [
      { id: 'duty', start_at: '2026-09-10T00:00:00Z', end_at: '2026-09-10T09:00:00Z', location_id: 'loc-balboa', location_label: 'Balboa' }
    ];
  }, {guard, cover});
  await page.goto('/admin/swaps.html');
  await page.getByRole('button', {name: 'Approve', exact: true}).click();
  const select = page.getByLabel('Replacement Guard');
  await expect(select).toBeVisible();
  const optionTexts = await select.locator('option').allInnerTexts();
  expect(optionTexts.some(t => t.includes('Cover Guard (Balboa)'))).toBe(true);
  expect(optionTexts.some(t => t.includes('Other PostGuard'))).toBe(false);
  expect(optionTexts[0]).toBe('Select replacement Guard');
  await expect(page.locator('.sl-dialog-hint')).toHaveText('Showing active Guards assigned to Balboa.');
});

test('replacement guard dropdown shows clean placeholder and informative hint when no guards are at the same post', async ({page}) => {
  await prepare(page, 'swap');
  await page.addInitScript(({guard, cover}) => {
    window.profileRows = [
      { id: guard, first_name: 'Guard', last_name: 'One', role: 'user', active: true, assigned_location_id: 'loc-balboa' },
      { id: cover, first_name: 'Beta', last_name: 'Guard', role: 'user', active: true, assigned_location_id: 'loc-chmsu' },
      { id: '33333333-3333-4333-8333-333333333334', first_name: 'Alpha', last_name: 'Guard', role: 'user', active: true, assigned_location_id: 'loc-chmsu' }
    ];
    window.dutyRows = [
      { id: 'duty', start_at: '2026-09-10T00:00:00Z', end_at: '2026-09-10T09:00:00Z', location_id: 'loc-balboa', location_label: 'Balboa' }
    ];
  }, {guard, cover});
  await page.goto('/admin/swaps.html');
  await page.getByRole('button', {name: 'Approve', exact: true}).click();
  const select = page.getByLabel('Replacement Guard');
  await expect(select).toBeVisible();
  const optionTexts = await select.locator('option').allInnerTexts();
  expect(optionTexts[0]).toBe('Select replacement Guard');
  expect(optionTexts.slice(1)).toEqual(['Alpha Guard', 'Beta Guard']);
  await expect(page.locator('.sl-dialog-hint')).toHaveText('No other Guards assigned to Balboa. Showing all active Guards.');
});

test('reciprocal exchange shows both duties and approves without replacing the selected Guard',async({page},info)=>{
  await prepare(page,'swap');
  await page.goto('/admin/swaps.html');
  await expect(page.locator('.duty-request-card')).toBeVisible();
  await page.evaluate(({cover})=>{
    window.requestRows[0].target_schedule_id='peer-duty';
    window.requestRows[0].target_guard_id=cover;
    window.requestRows[0].exchange_snapshot={target_name:'Cover Guard',
      offered:{start_at:'2026-09-10T00:00:00Z',end_at:'2026-09-10T04:00:00Z',location_label:'Post A',dtr_period:'morning'},
      requested:{start_at:'2026-09-11T05:00:00Z',end_at:'2026-09-11T09:00:00Z',location_label:'Post B',dtr_period:'afternoon'}};
  },{cover});
  await page.getByRole('button',{name:'Refresh',exact:true}).click();
  const preview=page.getByRole('region',{name:'Proposed duty exchange'});
  await expect(preview).toContainText('Guard One will take');
  await expect(preview).toContainText('Cover Guard will take');
  await expect(preview).toContainText('Post A');
  await expect(preview).toContainText('Post B');
  await page.screenshot({path:info.outputPath('reciprocal-exchange-preview.png'),fullPage:true});
  await page.getByRole('button',{name:'Approve',exact:true}).click();
  await expect(page.getByLabel('Replacement Guard')).toHaveCount(0);
  await page.getByRole('button',{name:'Approve request',exact:true}).click();
  await expect(page.locator('.sl-toast').last()).toContainText('Both Guards have been notified');
  expect(await page.evaluate(()=>window.calls.find(c=>c.name==='decide_duty_request').args.p_replacement_guard_id)).toBeNull();
  await page.screenshot({path:info.outputPath('reciprocal-exchange-approved.png'),fullPage:true});
});

test('reject requires a clear note and sends it to the backend',async({page})=>{
  await prepare(page);await page.goto('/admin/swaps.html');
  await page.evaluate(()=>{window.calls=[];});
  await page.getByRole('button',{name:'Reject',exact:true}).click();
  await page.getByLabel('Reason for rejection').fill('No');
  await page.getByRole('button',{name:'Reject request',exact:true}).click();
  await expect(page.locator('.sl-dialog-error')).toContainText('at least 5');
  await page.getByLabel('Reason for rejection').fill('Please discuss the date with Operations Head.');
  await page.getByRole('button',{name:'Reject request',exact:true}).click();
  await expect(page.locator('.sl-toast').last()).toContainText('Request rejected');
  expect(await page.evaluate(()=>window.calls.find(call=>call.name==='decide_duty_relief').args.p_approve)).toBe(false);
});

async function openIncident(page) {
  await prepare(page);await page.goto('/admin/incidents.html');
  await expect(page.locator('#loadingScreen')).toBeHidden();
  await page.evaluate(()=>{
    incidents=[{id:'44444444-4444-4444-8444-444444444444',guardName:'Guard One',category:'other',
      description:'Test report only',status:'open',photoData:'AAAA',createdAt:{toDate:()=>new Date()}}];
    renderTable();openDetail(incidents[0].id);
    window.calls=[];
  });
}

test('Operations Head must confirm actual Time Out before approving started-duty relief',async({page})=>{
  await prepare(page,'swap');
  await page.clock.setFixedTime(new Date('2026-09-11T03:00:00Z'));
  await page.goto('/admin/swaps.html');
  await page.evaluate(()=>window.attendanceRows=[{id:'session',schedule_id:'duty',clock_in_at:'2026-09-11T00:00:00Z',clock_out_at:null,scheduled_end_at:'2026-09-11T10:00:00Z'}]);
  await page.getByRole('button',{name:'Approve',exact:true}).click();
  await expect(page.getByRole('dialog')).toContainText('Confirm when the Guard actually stopped working');
  await page.getByLabel('Replacement Guard').selectOption(cover);
  const actualEndInput = page.getByLabel('Confirmed actual Time Out (Philippine time)');
  await expect(actualEndInput).not.toHaveValue('');
  await page.getByRole('button',{name:'Approve request',exact:true}).click();
  expect(await page.evaluate(()=>calls.filter(c=>c.name==='decide_duty_relief').length)).toBe(0);
  await page.getByLabel('Confirmed actual Time Out (Philippine time)').fill('2026-09-11T10:30');
  await page.getByLabel('How was the actual Time Out confirmed?').fill('Guard confirmed leaving the post at 10:30 AM.');
  await page.getByRole('button',{name:'Approve request',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>calls.filter(c=>c.name==='decide_duty_relief').length)).toBe(1);
  expect(await page.evaluate(()=>calls.find(c=>c.name==='decide_duty_relief').args.p_actual_end_at)).toBe('2026-09-11T02:30:00.000Z');
});

test('emergency deletion supports cancel, clear errors, retry and success',async({page},info)=>{
  await openIncident(page);
  await page.getByRole('button',{name:'Delete report',exact:true}).click();
  await expect(page.locator('.sl-dialog')).toContainText('cannot be undone');
  await page.getByRole('button',{name:'Keep report',exact:true}).click();
  expect(await page.evaluate(()=>window.calls.length)).toBe(0);
  await page.evaluate(()=>window.deleteError='Video cleanup failed. The report is still listed; retry Delete report.');
  await page.getByRole('button',{name:'Delete report',exact:true}).click();
  await page.getByRole('button',{name:'Delete report and media',exact:true}).click();
  await expect(page.locator('.sl-toast').last()).toContainText('Video cleanup failed');
  await expect(page.locator('#detailModal')).toBeVisible();
  expect(await page.evaluate(()=>incidents.length)).toBe(1);
  await page.screenshot({path:info.outputPath('incident-cleanup-error-retains-report.png')});
  await page.evaluate(()=>window.deleteError=null);
  await page.getByRole('button',{name:'Delete report',exact:true}).click();
  await page.getByRole('button',{name:'Delete report and media',exact:true}).click();
  await expect(page.locator('#detailModal')).toBeHidden();
  await expect(page.locator('#incidentTableBody')).toContainText('No incident reports');
  expect(await page.evaluate(()=>window.calls.every(c=>c.name==='admin-delete-incident'))).toBe(true);
  await page.screenshot({path:info.outputPath('incident-deletion-success.png')});
});

test('Inspector has no emergency delete button or duty approval controls',async({page})=>{
  await page.route('**/supabase-firebase-bridge.js',r=>r.fulfill({contentType:'text/javascript',body:'window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};'}));
  await page.goto('/inspector/incidents.html');
  await expect(page.locator('#deleteIncidentBtn')).toHaveCount(0);
  await page.goto('/inspector/swaps.html');
  expect(await page.evaluate(()=>typeof window.decide)).toBe('undefined');
  await expect(page.getByRole('button',{name:'Recommend',exact:true})).toHaveCount(0);
});
