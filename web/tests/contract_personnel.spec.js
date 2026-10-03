const {test, expect} = require('@playwright/test');

test.beforeEach(async ({page}) => {
  await page.route('**/notification-center.js', route => route.fulfill({body:''}));
  await page.route('**/platform-configuration.js', route => route.fulfill({body:''}));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({contentType:'text/javascript',body:`
    window.contractTest = { calls: [], rows: [{id:'guard-contract',role:'user',username:'contract.guard',email:'contract.guard@gmail.com',firstName:'Contract',lastName:'Guard',active:true,employmentCategory:'contract',contractStartDate:'2026-09-01',contractEndDate:'2026-09-30'}] };
    const snapshot = () => ({empty:true,forEach(fn){contractTest.rows.forEach(row=>fn({id:row.id,data:()=>row}));}});
    const query = {where(){return this;},limit(){return this;},get:async()=>snapshot()};
    window.firebase={auth:()=>({onAuthStateChanged(){}}),firestore:()=>({collection:()=>query})};
    window.appSupabase={from:()=>({select:async()=>({data:[]})}),functions:{invoke:async(name,{body})=>{
      contractTest.calls.push({name,body});return {data:{success:true}};
    }}};
  `}));
  await page.goto('/admin/users.html');
  await page.evaluate(() => loadUsers());
  await expect(page.locator('#guardTableBody')).toContainText('Contract Guard');
});

test('Contract creation requires dates and sends the inclusive period', async ({page}) => {
  await page.evaluate(() => openPersonnelCreate());
  await page.locator('#newGuardEmploymentCategory').selectOption('contract');
  await expect(page.locator('#newGuardContractPeriod')).toBeVisible();
  await page.locator('#createGuardBtn').click();
  await expect(page.locator('#createGuardError')).toContainText('Set valid contract start and end dates');
  expect(await page.evaluate(()=>contractTest.calls)).toHaveLength(0);
  await page.locator('#newGuardContractStart').fill('2026-09-10');
  await page.locator('#newGuardContractEnd').fill('2026-09-09');
  await page.locator('#createGuardBtn').click();
  await expect(page.locator('#createGuardError')).toContainText('on or after');
  await page.locator('#newGuardContractEnd').fill('2026-12-31');
  for (const [id,value] of Object.entries({newGuardFirstName:'QA',newGuardLastName:'Contract',newGuardUsername:'qa.contract@gmail.com',newGuardPassword:'Test-Only9!Password',newGuardPasswordConfirm:'Test-Only9!Password'})) await page.locator('#'+id).fill(value);
  await page.locator('#createGuardBtn').click();
  await expect.poll(()=>page.evaluate(()=>contractTest.calls.length)).toBe(1);
  expect(await page.evaluate(()=>contractTest.calls[0].body)).toMatchObject({employmentCategory:'contract',contractStartDate:'2026-09-10',contractEndDate:'2026-12-31'});
  await expect(page.getByText('Guard account created. Email: qa.contract@gmail.com',{exact:true})).toBeVisible();
  await page.screenshot({path:test.info().outputPath('contract-created.png'),fullPage:true});
});

test('Inspector and Regular creation do not require contract dates', async ({page}) => {
  await page.evaluate(()=>openPersonnelCreate());
  await expect(page.locator('#newGuardContractPeriod')).toBeHidden();
  await page.locator('#newGuardEmploymentCategory').selectOption('contract');
  await page.locator('#newGuardRole').selectOption('inspector');
  await expect(page.locator('#newGuardContractPeriod')).toBeHidden();
  await expect(page.locator('#newGuardEmploymentCategory')).toHaveValue('regular');
  await page.locator('#createGuardBtn').click();
  await expect(page.locator('#createGuardError')).toHaveText('Please complete all required fields.');
});

test('Editing loads saved dates, validates and submits renewal', async ({page}) => {
  await expect(page.locator('#guardTableBody')).toContainText('2026-09-01 – 2026-09-30');
  await page.evaluate(()=>{void editPersonnel('guard-contract',null);});
  const dialog = page.getByRole('dialog');
  await expect(dialog.locator('[name=contractStartDate]')).toHaveValue('2026-09-01');
  await dialog.locator('[name=contractEndDate]').fill('2026-08-01');
  await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  await expect(dialog.locator('.sl-dialog-error')).toContainText('on or after');
  await dialog.locator('[name=contractEndDate]').fill('2027-09-30');
  await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>contractTest.calls.length)).toBe(1);
  expect(await page.evaluate(()=>contractTest.calls[0])).toMatchObject({name:'admin-manage-user',body:{contractStartDate:'2026-09-01',contractEndDate:'2027-09-30',password:''}});
});

const invalidPasswords=['Aa1!abc','lowercase1!','UPPERCASE1!','NoNumbers!','NoSymbols1'];

test('Operations Head creation rejects each missing password requirement and accepts an eight-character mix',async({page})=>{
  await page.evaluate(()=>openPersonnelCreate());
  for(const [id,value] of Object.entries({newGuardFirstName:'QA',newGuardLastName:'Guard',newGuardUsername:'qa.password@gmail.com'}))await page.locator('#'+id).fill(value);
  for(const password of invalidPasswords){
    await page.locator('#newGuardPassword').fill(password);
    await page.locator('#newGuardPasswordConfirm').fill(password);
    await page.locator('#createGuardBtn').click();
    await expect(page.locator('#createGuardError')).toContainText('uppercase letter');
    expect(await page.evaluate(()=>contractTest.calls)).toHaveLength(0);
  }
  await page.locator('#newGuardPassword').fill('Aa1!abcd');
  await page.locator('#newGuardPasswordConfirm').fill('Aa1!abcd');
  await page.locator('#createGuardBtn').click();
  await expect.poll(()=>page.evaluate(()=>contractTest.calls.length)).toBe(1);
  expect(await page.evaluate(()=>contractTest.calls[0])).toMatchObject({name:'admin-create-user',body:{password:'Aa1!abcd'}});
});

test('Operations Head reset validates all password requirements before sending a change',async({page})=>{
  await page.evaluate(()=>{void editPersonnel('guard-contract',null);});
  const dialog=page.getByRole('dialog');
  for(const password of invalidPasswords){
    await dialog.locator('[name=password]').fill(password);
    await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
    await expect(dialog.locator('.sl-dialog-error')).toContainText('uppercase letter');
    expect(await page.evaluate(()=>contractTest.calls)).toHaveLength(0);
  }
  await dialog.locator('[name=password]').fill('Aa1!abcd');
  await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>contractTest.calls.length)).toBe(1);
  expect(await page.evaluate(()=>contractTest.calls[0])).toMatchObject({name:'admin-manage-user',body:{password:'Aa1!abcd'}});
});

test('Legacy missing-date contract is identified, not silently treated as Regular', async ({page}) => {
  await page.evaluate(async()=>{contractTest.rows[0].contractStartDate=null;contractTest.rows[0].contractEndDate=null;await loadUsers();});
  await expect(page.locator('#guardTableBody')).toContainText('Set contract dates');
  await page.evaluate(()=>{void editPersonnel('guard-contract',null);});
  await page.getByRole('dialog').getByRole('button',{name:'Save changes',exact:true}).click();
  await expect(page.locator('.sl-dialog-error')).toContainText('Set valid contract start and end dates');
});
