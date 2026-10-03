const { test, expect } = require('@playwright/test');

test.use({ timezoneId: 'America/New_York' });
test.beforeEach(async ({page}) => {
  await page.route('**/notification-center.js', route => route.fulfill({body:''}));
  await page.route('**/platform-configuration.js', route => route.fulfill({body:''}));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({contentType:'text/javascript',body:`
    window.timeoutTest = { calls: [], failure:null, sessions:[{
      id:'session-old', user_id:'guard-one', schedule_id:'duty-old', duty_date:'2026-09-01',
      location_label:'Main Gate <script>bad()</script>', status:'missed_timeout',
      scheduled_start_at:'2026-09-01T00:00:00Z', scheduled_end_at:'2026-09-01T12:00:00Z',
      clock_in_at:'2026-09-01T00:00:00Z', clock_out_at:null, updated_at:'2026-09-02T00:00:00Z'
    }], reviews:[] };
    const snapshot = {empty:true,forEach(){}};
    window.firebase = {auth:()=>({onAuthStateChanged(){}}),firestore:()=>({collection:()=>({get:async()=>snapshot})})};
    window.appSupabase = {
      from(table) {
        const filters={}; return {select(){return this;},eq(k,v){filters[k]=v;return this;},order(){return this;},
          then(resolve,reject){return Promise.resolve({data:(table==='attendance_timeout_reviews'?timeoutTest.reviews:table==='attendance_sessions'?timeoutTest.sessions:[]).filter(row=>Object.entries(filters).every(([k,v])=>row[k]===v))}).then(resolve,reject);}
        };
      },
      async rpc(name,params) {
        timeoutTest.calls.push({name,params});
        if(name==='evaluate_time_record')return {data:{duty_days:1,completed_days:0,total_minutes:780,late_minutes:137,undertime_minutes:65}};
        if(timeoutTest.failure)return {error:{message:timeoutTest.failure}};
        const session=timeoutTest.sessions.find(s=>s.id===params.p_session_id);
        timeoutTest.reviews.push({session_id:session.id,before_record:{...session},verified_clock_out_at:params.p_clock_out_at,reviewed_at:new Date().toISOString(),reviewed_by:'Operations Head reviewer',reason:params.p_reason});
        Object.assign(session,{clock_out_at:params.p_clock_out_at,status:'closed',timeout_verified_at:new Date().toISOString(),timeout_verification_reason:params.p_reason,timeout_verified_by:'Operations Head reviewer'});
        return {data:session};
      }
    };
  `}));
  await page.goto('/admin/users.html');
  await page.evaluate(async()=>{await loadUsers();await viewDTR('guard-one');});
  await expect(page.locator('#dtrTimeoutReviews')).toContainText('Awaiting Time Out verification');
});

async function fillReview(page) {
  await page.getByRole('button',{name:'Verify Time Out',exact:true}).click();
  await page.locator('[name=actualEnd]').fill('2026-09-01T20:00');
  await page.locator('[name=reason]').click();
  await expect(page.locator('[name=reason]')).toBeFocused();
  await page.locator('[name=reason]').pressSequentially('Confirmed end with post supervisor and guard.');
}

test('Operations Head records verified Philippine time, refreshes hours and sees preserved history',async({page})=>{
  await expect(page.locator('#dtrRecordsList')).toContainText('Missing Time Out');
  await fillReview(page);
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>timeoutTest.calls.length)).toBe(1);
  const call=await page.evaluate(()=>timeoutTest.calls[0]);
  expect(call.name).toBe('verify_attendance_timeout');
  expect(call.params).toMatchObject({p_session_id:'session-old',p_clock_out_at:'2026-09-01T12:00:00.000Z',p_expected_updated_at:'2026-09-02T00:00:00Z'});
  expect(call.params.p_request_id).toMatch(/^[a-f0-9-]{36}$/);
  await expect(page.locator('#dtrTimeoutReviews')).toContainText('Operations Head verified');
  await expect(page.locator('#dtrRecordsList')).toContainText('12:00');
  await expect(page.getByRole('button',{name:'Verify Time Out',exact:true})).toHaveCount(0);
  await page.getByRole('button',{name:'Review history',exact:true}).click();
  await expect(page.locator('.sl-dialog')).toContainText('Original Time Out: Missing');
  await expect(page.locator('.sl-dialog')).toContainText('Confirmed end with post supervisor');
  expect(await page.evaluate(()=>typeof bad)).toBe('undefined');
});

test('Invalid and cancelled reviews never submit a correction',async({page})=>{
  await fillReview(page);
  await page.locator('[name=actualEnd]').fill('2026-08-31T20:00');
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  await expect(page.locator('.sl-dialog-error')).toContainText('between Time In and now');
  await page.locator('[name=actualEnd]').fill('2026-09-01T20:00');
  await page.locator('[name=reason]').fill('no');
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  await expect(page.locator('.sl-dialog-error')).toContainText('verification reason');
  await page.locator('.sl-dialog').getByRole('button',{name:'Cancel',exact:true}).click();
  expect(await page.evaluate(()=>timeoutTest.calls.length)).toBe(0);
});

test('Rejected server review leaves missing punch and hours unchanged',async({page})=>{
  await page.evaluate(()=>timeoutTest.failure='This attendance record changed. Reload it before reviewing.');
  await fillReview(page);
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  await expect(page.getByText('This attendance record changed. Reload it before reviewing.',{exact:true})).toBeVisible();
  await expect(page.locator('#dtrTimeoutReviews')).toContainText('Awaiting Time Out verification');
  expect(await page.evaluate(()=>timeoutTest.sessions[0].clock_out_at)).toBe(null);
});

test('Uncertain submission reuses request identity for same review',async({page})=>{
  await page.evaluate(()=>timeoutTest.failure='Network unavailable');
  await fillReview(page);
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>timeoutTest.calls.length)).toBe(1);
  await fillReview(page);
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>timeoutTest.calls.length)).toBe(2);
  expect(await page.evaluate(()=>timeoutTest.calls[0].params.p_request_id===timeoutTest.calls[1].params.p_request_id)).toBe(true);
});

test('Newly selected guard cannot receive the previous guard review result',async({page})=>{
  await fillReview(page);
  await page.evaluate(()=>{currentDTRUid='guard-two';currentDTRData=[];refreshDtrPeriod();});
  await page.getByRole('button',{name:'Save verified Time Out',exact:true}).click();
  expect(await page.evaluate(()=>timeoutTest.calls.length)).toBe(0);
});

test('DTR PDF includes pending review notes and excludes an unverified 24-hour punch',async({page})=>{
  const result = await page.evaluate(async()=>{
    const NativePdf=window.jspdf.jsPDF; let doc;
    function Pdf(options){doc=new NativePdf(options);doc.save=()=>{};return doc;}
    const session={...timeoutTest.sessions[0],status:'closed',clock_out_at:'2026-09-02T00:00:00Z'};
    const result=await DtrReport.generatePdf({jsPDF:Pdf,sessions:[session],period:DtrReport.periodFromSelection('2026-09','first')});
    return {minutes:result.report.totalMinutes,text:doc.output(),pages:doc.getNumberOfPages()};
  });
  expect(result.minutes).toBe(0);
  expect(result.text).toContain('awaiting Operations Head verification');
  expect(result.pages).toBeGreaterThan(0);
});

test('Review form fits a mobile screen and supports keyboard entry',async({page})=>{
  await page.setViewportSize({width:390,height:844});
  await fillReview(page);
  const dialog=page.locator('.sl-dialog');
  await expect(dialog.getByRole('button',{name:'Save verified Time Out',exact:true})).toBeVisible();
  const box=await dialog.boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x+box.width).toBeLessThanOrEqual(391);
  await page.screenshot({path:test.info().outputPath('timeout-review-mobile.png'),fullPage:true});
});

test('time evaluation uses readable hours and minutes without explanatory text',async({page},info)=>{
 await page.evaluate(()=>{document.querySelector('#loadingScreen').style.display='none';void evaluateDTR();});
 const dialog=page.getByRole('dialog').filter({hasText:'Time evaluation'});
 await expect(dialog).toContainText('Recorded hours: 13 hrs');
 await expect(dialog).toContainText('Late: 2 hrs and 17 min');
 await expect(dialog).toContainText('Undertime: 1 hr and 5 min');
 await expect(dialog).not.toContainText('Hours include');
 expect(await page.evaluate(()=>[0,3,60,61,137].map(formatDtrMinutes))).toEqual(['0 min','3 min','1 hr','1 hr and 1 min','2 hrs and 17 min']);
 await page.screenshot({path:info.outputPath('time-evaluation.png'),animations:'disabled'});
});

test('overtime request stays off DTR until the Operations Head approves the submitted time',async({page})=>{
  await page.evaluate(()=>{
    Object.assign(timeoutTest.sessions[0],{status:'closed',clock_out_at:'2026-09-01T14:00:35.123Z',timeout_submitted_at:'2026-09-01T14:00:35.123Z',overtime_requested:true});
    currentDTRData=timeoutTest.sessions;refreshDtrPeriod();
  });
  await expect(page.locator('#dtrTimeoutReviews')).toContainText('Overtime requested: 2 hrs');
  const row=page.locator('#dtrRecordsList .dtr-sheet-table tbody tr').first();
  await expect(row.locator('td').nth(2)).toHaveText('');
  await page.getByRole('button',{name:'Review overtime Time Out',exact:true}).click();
  await expect(page.locator('[name=actualEnd]')).toHaveValue('2026-09-01T22:00');
  await page.locator('[name=reason]').fill('Relief guard arrived two hours late.');
  await page.getByRole('button',{name:'Approve verified Time Out',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>timeoutTest.calls.length)).toBe(1);
  expect(await page.evaluate(()=>timeoutTest.calls[0].params.p_clock_out_at)).toBe('2026-09-01T14:00:35.123Z');
  await expect(row.locator('td').nth(2)).toContainText('10:00 PM');
  await expect(row.locator('td').nth(3)).toContainText('2:00');
  await expect(row.locator('td').nth(4)).toContainText('14:00');
});
