# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: duty_requests.spec.js >> Admin downloads private letter, filters requests and approves absence in dark mobile UI
- Location: duty_requests.spec.js:30:1

# Error details

```
Error: expect(locator).toContainText(expected) failed

Locator: getByRole('dialog')
Expected substring: "Cancel this duty as an approved absence"
Received string:    "infoApprove absence requestApprove absence for this duty period only. Other periods on the same day remain scheduled. Existing attendance cannot be changed.closeDecision note (optional)CancelApprove request"
Timeout: 5000ms

Call log:
  - Expect "toContainText" with timeout 5000ms
  - waiting for getByRole('dialog')
    13 × locator resolved to <section role="dialog" class="sl-dialog" aria-modal="true" aria-labelledby="sl-dialog-title" aria-describedby="sl-dialog-message">…</section>
       - unexpected value "infoApprove absence requestApprove absence for this duty period only. Other periods on the same day remain scheduled. Existing attendance cannot be changed.closeDecision note (optional)CancelApprove request"

```

```yaml
- dialog "Approve absence request":
  - heading "Approve absence request" [level=2]
  - paragraph: Approve absence for this duty period only. Other periods on the same day remain scheduled. Existing attendance cannot be changed.
  - button "Close"
  - text: Decision note (optional)
  - textbox "Decision note (optional)"
  - paragraph
  - button "Cancel"
  - button "Approve request"
```

# Test source

```ts
  1   | const {test,expect}=require('@playwright/test');
  2   | const guard='11111111-1111-4111-8111-111111111111';
  3   | const cover='22222222-2222-4222-8222-222222222222';
  4   | async function prepare(page,kind='absence') {
  5   |   await page.route('**/notification-center.js',route=>route.fulfill({contentType:'text/javascript',body:''}));
  6   |   await page.route('**/supabase-firebase-bridge.js',route=>route.fulfill({contentType:'text/javascript',body:`
  7   |     window.calls=[];window.rpcError=null;window.deleteError=null;window.applyAdminRoleNavigation=()=>{};
  8   |     window.requestRows=[{id:'33333333-3333-4333-8333-333333333333',requester_id:'${guard}',requested_schedule_id:'duty',
  9   |       request_type:'${kind}',reason:'Family appointment <img src=x onerror=alert(1)>',status:'pending_admin',
  10  |       created_at:'2026-09-04T02:00:00Z',letter_path:'${guard}/letter.pdf',letter_name:'Request letter.pdf'}];
  11  |     const profiles=[{id:'${guard}',first_name:'Guard',last_name:'One',role:'user',active:true},
  12  |       {id:'${cover}',first_name:'Cover',last_name:'Guard',role:'user',active:true}];
  13  |     const duties=[{id:'duty',start_at:'2026-09-10T00:00:00Z',end_at:'2026-09-10T09:00:00Z',location_label:'Agency post'}];
  14  |     const makeQuery=table=>{const filters=[];const q={select:()=>q,order:()=>q,limit:()=>q,in:()=>q,
  15  |       eq:(key,value)=>{filters.push([key,value]);return q;},then:(resolve,reject)=>Promise.resolve({data:
  16  |         (table==='shift_swap_requests'?window.requestRows:table==='profiles'?profiles:duties)
  17  |         .filter(row=>filters.every(([key,value])=>row[key]===value)),error:null}).then(resolve,reject)};return q;};
  18  |     window.appSupabase={from:makeQuery,rpc:async(name,args)=>{window.calls.push({name,args});await new Promise(r=>setTimeout(r,200));
  19  |       if(window.rpcError)return {error:{message:window.rpcError}};
  20  |       window.requestRows=window.requestRows.map(r=>({...r,status:args.p_approve?'approved':'rejected',admin_note:args.p_note}));return {data:null,error:null};},
  21  |       storage:{from:bucket=>({createSignedUrl:async(path,ttl,options)=>{window.calls.push({bucket,path,ttl,options});return {data:{signedUrl:'https://uqtupmpofjqrnefgrexm.supabase.co/storage/v1/object/sign/request-letters/'+path+'?token=test'},error:null};}})},
  22  |       functions:{invoke:async(name,args)=>{window.calls.push({name,args});await new Promise(r=>setTimeout(r,200));return window.deleteError?
  23  |         {error:{context:{json:async()=>({error:window.deleteError})}}}:{data:{ok:true},error:null};}}};
  24  |     window.firebase={auth:()=>({onAuthStateChanged:cb=>setTimeout(()=>cb({uid:'hr'}),0),signOut:async()=>{}}),
  25  |       firestore:()=>({collection:()=>({doc:()=>({get:async()=>({exists:true,data:()=>({role:'admin',active:true,firstName:'HR',lastName:'Tester'})})}),
  26  |         orderBy:()=>({onSnapshot:cb=>cb({forEach:()=>{}})})})})};
  27  |   `}));
  28  | }
  29  | 
  30  | test('Admin downloads private letter, filters requests and approves absence in dark mobile UI',async({page},info)=>{
  31  |   test.setTimeout(60_000);
  32  |   await prepare(page);
  33  |   await page.addInitScript(()=>localStorage.setItem('sentinel-link-theme','dark'));
  34  |   await page.setViewportSize({width:390,height:844});
  35  |   await page.goto('/admin/swaps.html');
  36  |   const card=page.locator('.duty-request-card');
  37  |   await expect(card).toContainText('Absence');
  38  |   await expect(card.locator('img')).toHaveCount(0);
  39  |   await page.getByLabel('Search requests').fill('not present');
  40  |   await expect(card).toHaveCount(0);
  41  |   await page.getByLabel('Search requests').fill('Guard One');
  42  |   await expect(card).toBeVisible();
  43  |   await page.route('**/storage/v1/object/sign/request-letters/**',r=>r.fulfill({contentType:'application/pdf',body:'%PDF-1.7'}));
  44  |   await page.getByRole('button',{name:/Download letter/}).click();
  45  |   await expect.poll(()=>page.evaluate(()=>window.calls.filter(call=>call.bucket).length)).toBe(1);
  46  |   expect(await page.evaluate(()=>window.calls.find(call=>call.bucket).bucket)).toBe('request-letters');
  47  |   expect(await page.evaluate(()=>window.calls.find(call=>call.bucket).ttl)).toBe(120);
  48  |   await page.getByRole('button',{name:'Approve',exact:true}).click();
> 49  |   await expect(page.getByRole('dialog')).toContainText('Cancel this duty as an approved absence');
      |                                          ^ Error: expect(locator).toContainText(expected) failed
  50  |   await expect(page.getByLabel('Replacement Guard')).toHaveCount(0);
  51  |   await page.screenshot({path:info.outputPath('absence-approval-dark-mobile.png'),fullPage:true});
  52  |   await page.getByRole('button',{name:'Approve request',exact:true}).click();
  53  |   await expect(page.locator('.sl-toast').last()).toContainText('Guard has been notified');
  54  |   await page.getByRole('combobox',{name:'Status',exact:true}).selectOption('approved');
  55  |   await expect(card).toContainText('Approved');
  56  |   expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(391);
  57  | });
  58  | 
  59  | test('swap approval requires replacement and leaves request pending on server conflict',async({page},info)=>{
  60  |   await prepare(page,'swap');await page.goto('/admin/swaps.html');
  61  |   await page.evaluate(()=>{window.calls=[];});
  62  |   await page.getByRole('button',{name:'Approve',exact:true}).click();
  63  |   await page.getByRole('button',{name:'Approve request',exact:true}).click();
  64  |   expect(await page.evaluate(()=>window.calls.length)).toBe(0);
  65  |   await page.getByLabel('Replacement Guard').selectOption(cover);
  66  |   await page.evaluate(()=>window.rpcError='The replacement Guard already has an overlapping duty.');
  67  |   await page.getByRole('button',{name:'Approve request',exact:true}).click();
  68  |   await expect(page.locator('.sl-toast').last()).toContainText('overlapping duty');
  69  |   await expect(page.locator('.duty-request-card')).toContainText('Awaiting Admin approval');
  70  |   expect(await page.evaluate(()=>window.calls.find(call=>call.name==='decide_duty_request').args.p_replacement_guard_id)).toBe(cover);
  71  |   await page.screenshot({path:info.outputPath('swap-conflict-preserved.png'),fullPage:true});
  72  | });
  73  | 
  74  | test('reject requires a clear note and sends it to the backend',async({page})=>{
  75  |   await prepare(page);await page.goto('/admin/swaps.html');
  76  |   await page.evaluate(()=>{window.calls=[];});
  77  |   await page.getByRole('button',{name:'Reject',exact:true}).click();
  78  |   await page.getByLabel('Reason for rejection').fill('No');
  79  |   await page.getByRole('button',{name:'Reject request',exact:true}).click();
  80  |   await expect(page.locator('.sl-dialog-error')).toContainText('at least 5');
  81  |   await page.getByLabel('Reason for rejection').fill('Please discuss the date with Admin.');
  82  |   await page.getByRole('button',{name:'Reject request',exact:true}).click();
  83  |   await expect(page.locator('.sl-toast').last()).toContainText('Request rejected');
  84  |   expect(await page.evaluate(()=>window.calls.find(call=>call.name==='decide_duty_request').args.p_approve)).toBe(false);
  85  | });
  86  | 
  87  | async function openIncident(page) {
  88  |   await prepare(page);await page.goto('/admin/incidents.html');
  89  |   await expect(page.locator('#loadingScreen')).toBeHidden();
  90  |   await page.evaluate(()=>{
  91  |     incidents=[{id:'44444444-4444-4444-8444-444444444444',guardName:'Guard One',category:'other',
  92  |       description:'Test report only',status:'open',photoData:'AAAA',createdAt:{toDate:()=>new Date()}}];
  93  |     renderTable();openDetail(incidents[0].id);
  94  |     window.calls=[];
  95  |   });
  96  | }
  97  | 
  98  | test('emergency deletion supports cancel, clear errors, retry and success',async({page},info)=>{
  99  |   await openIncident(page);
  100 |   await page.getByRole('button',{name:'Delete report',exact:true}).click();
  101 |   await expect(page.locator('.sl-dialog')).toContainText('cannot be undone');
  102 |   await page.getByRole('button',{name:'Keep report',exact:true}).click();
  103 |   expect(await page.evaluate(()=>window.calls.length)).toBe(0);
  104 |   await page.evaluate(()=>window.deleteError='Video cleanup failed. The report is still listed; retry Delete report.');
  105 |   await page.getByRole('button',{name:'Delete report',exact:true}).click();
  106 |   await page.getByRole('button',{name:'Delete report and media',exact:true}).click();
  107 |   await expect(page.locator('.sl-toast').last()).toContainText('Video cleanup failed');
  108 |   await expect(page.locator('#detailModal')).toBeVisible();
  109 |   expect(await page.evaluate(()=>incidents.length)).toBe(1);
  110 |   await page.screenshot({path:info.outputPath('incident-cleanup-error-retains-report.png')});
  111 |   await page.evaluate(()=>window.deleteError=null);
  112 |   await page.getByRole('button',{name:'Delete report',exact:true}).click();
  113 |   await page.getByRole('button',{name:'Delete report and media',exact:true}).click();
  114 |   await expect(page.locator('#detailModal')).toBeHidden();
  115 |   await expect(page.locator('#incidentTableBody')).toContainText('No incident reports');
  116 |   expect(await page.evaluate(()=>window.calls.every(c=>c.name==='admin-delete-incident'))).toBe(true);
  117 |   await page.screenshot({path:info.outputPath('incident-deletion-success.png')});
  118 | });
  119 | 
  120 | test('Inspector has no emergency delete button or duty approval controls',async({page})=>{
  121 |   await page.route('**/supabase-firebase-bridge.js',r=>r.fulfill({contentType:'text/javascript',body:'window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({})};'}));
  122 |   await page.goto('/inspector/incidents.html');
  123 |   await expect(page.locator('#deleteIncidentBtn')).toHaveCount(0);
  124 |   await page.goto('/inspector/swaps.html');
  125 |   expect(await page.evaluate(()=>typeof window.decide)).toBe('undefined');
  126 |   await expect(page.getByRole('button',{name:'Recommend',exact:true})).toHaveCount(0);
  127 | });
  128 | 
```