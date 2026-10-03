const { expect, test } = require('@playwright/test');

const currentUserId = '11111111-1111-4111-8111-111111111111';
const otherAdminId = '22222222-2222-4222-8222-222222222222';

const accounts = [
  {
    id: currentUserId,
    username: 'platform.owner', email: 'platform.owner@gmail.com',
    first_name: 'Platform',
    last_name: 'Owner',
    role: 'it_admin',
    active: true,
  },
  {
    id: otherAdminId,
    username: 'operations.admin', email: 'operations.admin@gmail.com',
    first_name: 'Operations',
    last_name: 'Operations Head',
    role: 'admin',
    active: true,
  },
];

async function mockAccountBackend(page, options = {}) {
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return url.origin === 'http://127.0.0.1:4173'
      ? route.continue()
      : route.fulfill({ contentType: 'text/javascript', body: '' });
  });

  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `(() => {
      const currentUserId = ${JSON.stringify(currentUserId)};
      const rows = ${JSON.stringify(accounts)};
      const options = ${JSON.stringify(options)};
      const profile = {
        id: currentUserId,
        role: 'it_admin',
        active: true,
        organization_id: null,
        first_name: 'Platform',
        last_name: 'Owner'
      };
      const state = window.itAdminAccountTestBackend = {
        invoked: [],
        rows: rows.map(row => ({ ...row }))
      };

      function resultFor(table, single) {
        if (table === 'profiles') {
          return Promise.resolve({
            data: single ? { ...profile } : state.rows.map(row => ({ ...row })),
            error: null
          });
        }
        if (table === 'user_notifications') return Promise.resolve({ data: [], error: null });
        return Promise.resolve({ data: single ? null : [], error: null });
      }

      function query(table) {
        const builder = {
          select() { return this; },
          in() { return this; },
          eq() { return this; },
          order() { return this; },
          limit() { return this; },
          maybeSingle() { return resultFor(table, true); },
          then(resolve, reject) { return resultFor(table, false).then(resolve, reject); }
        };
        return builder;
      }

      const auth = {
        onAuthStateChanged(callback) {
          setTimeout(() => callback({ uid: currentUserId }), 0);
          return () => {};
        },
        signOut: async () => {}
      };
      window.firebase = {
        auth: () => auth,
        firestore: () => ({
          collection: () => ({
            doc: () => ({
              get: async () => ({ exists: true, data: () => ({ ...profile }) })
            })
          })
        })
      };

      window.appSupabase = {
        auth: {
          getSession: async () => ({ data: { session: { user: { id: currentUserId } } } }),
          onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } })
        },
        from: query,
        rpc: async () => ({ data: '', error: null }),
        functions: {
          invoke: async (name, request) => {
            state.invoked.push({ name, body: request && request.body });
            if (name === 'admin-manage-user' && options.editFailure) {
              return {
                data: null,
                error: {
                  name: 'FunctionsHttpError',
                  message: 'Edge Function returned a non-2xx status code',
                  context: {
                    headers: { get: key => key.toLowerCase() === 'x-request-id' ? 'req-header-account-edit' : null },
                    clone: () => ({
                      json: async () => ({
                        error: 'That email address is already in use.',
                        code: 'username_taken',
                        requestId: 'req-account-edit'
                      })
                    })
                  }
                }
              };
            }
            return { data: { ok: true }, error: null };
          }
        },
        channel: () => ({ on() { return this; }, subscribe() { return this; } }),
        removeChannel: async () => {}
      };
    })();`,
  }));
}

async function openAccounts(page, options = {}) {
  await mockAccountBackend(page, options);
  await page.goto('/it-admin/users.html', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#rows tr')).toHaveCount(2);
}

const invalidPasswords=['Aa1!abc','lowercase1!','UPPERCASE1!','NoNumbers!','NoSymbols1'];

test('IT Admin creation rejects each missing password requirement and accepts an eight-character mix',async({page})=>{
  await openAccounts(page);
  for(const [id,value] of Object.entries({first:'New',last:'Operations Head',username:'new.admin@gmail.com'}))await page.locator('#'+id).fill(value);
  for(const password of invalidPasswords){
    await page.locator('#password').fill(password);
    await page.locator('#createAccountButton').click();
    await expect(page.locator('#createNotice')).toContainText('uppercase letter');
    expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked)).toHaveLength(0);
  }
  await page.locator('#password').fill('Aa1!abcd');
  await page.locator('#createAccountButton').click();
  await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0]))
    .toMatchObject({name:'admin-create-user',body:{password:'Aa1!abcd'}});
});

test('IT Admin reset validates each password requirement before sending a change',async({page})=>{
  await openAccounts(page);
  await page.locator('#rows tr').filter({hasText:'operations.admin'}).getByRole('button',{name:'Edit',exact:true}).click();
  const dialog=page.getByRole('dialog',{name:'Edit privileged account',exact:true});
  for(const password of invalidPasswords){
    await dialog.locator('[name=password]').fill(password);
    await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
    await expect(dialog.locator('.sl-dialog-error')).toContainText('uppercase letter');
    expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked)).toHaveLength(0);
  }
  await dialog.locator('[name=password]').fill('Aa1!abcd');
  await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0]))
    .toMatchObject({name:'admin-manage-user',body:{password:'Aa1!abcd'}});
});

test('IT Admin keeps the password when the optional edit field is blank',async({page})=>{
  await openAccounts(page);
  await page.locator('#rows tr').filter({hasText:'operations.admin'}).getByRole('button',{name:'Edit',exact:true}).click();
  const dialog=page.getByRole('dialog',{name:'Edit privileged account',exact:true});
  await expect(dialog.locator('[name=password]')).toHaveValue('');
  await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0]))
    .toMatchObject({name:'admin-manage-user',body:{password:''}});
});

test('current IT Admin is protected while another Operations Head keeps account actions', async ({ page }) => {
  await openAccounts(page);

  const currentRow = page.locator('#rows tr').filter({ hasText: 'platform.owner' });
  await expect(currentRow).toContainText('Change my email');
  await expect(currentRow.getByRole('button', { name: 'Edit', exact: true })).toHaveCount(0);
  await expect(currentRow.getByRole('button', { name: 'Disable', exact: true })).toHaveCount(0);

  const otherRow = page.locator('#rows tr').filter({ hasText: 'operations.admin' });
  await expect(otherRow.getByRole('button', { name: 'Edit', exact: true })).toBeVisible();
  await expect(otherRow.getByRole('button', { name: 'Disable', exact: true })).toBeVisible();

  await expect(page.getByText(/reset\s+device/i)).toHaveCount(0);
  await expect(page.getByRole('columnheader', { name: 'Device', exact: true })).toHaveCount(0);
});

test('account editing shows the Edge Function public JSON message', async ({ page }) => {
  await openAccounts(page, { editFailure: true });

  const otherRow = page.locator('#rows tr').filter({ hasText: 'operations.admin' });
  await otherRow.getByRole('button', { name: 'Edit', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: 'Edit privileged account', exact: true });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Save changes', exact: true }).click();

  await expect(page.getByRole('alert')).toContainText(
    'That email address is already in use. (Request ID: req-account-edit)',
  );
  await expect(page.getByText(/Edge Function returned a non-2xx status code/i)).toHaveCount(0);

  const calls = await page.evaluate(() => window.itAdminAccountTestBackend.invoked);
  expect(calls).toEqual([{
    name: 'admin-manage-user',
    body: {
      action: 'update',
      userId: otherAdminId,
      firstName: 'Operations',
      lastName: 'Operations Head',
      email: 'operations.admin@gmail.com',
      role: 'admin',
      password: '',
    },
  }]);
});

test('IT Admin changes own email with current password and no access fields',async({page})=>{
 await openAccounts(page);
 await page.getByRole('button',{name:'Change my email'}).click();
 const dialog=page.getByRole('dialog',{name:'Change my email',exact:true});
 await dialog.locator('[name=email]').fill('Owner.New@gmail.com');
 await dialog.locator('[name=currentPassword]').fill('Current1!');
 await dialog.getByRole('button',{name:'Save email',exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
 expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0].body)).toEqual({action:'update',userId:currentUserId,email:'owner.new@gmail.com',currentPassword:'Current1!'});
});
test('account creation rejects legacy aliases and invalid email',async({page})=>{
 await openAccounts(page);
 for(const [id,value] of Object.entries({first:'New',last:'Head',password:'Test123!'})) await page.locator('#'+id).fill(value);
 for(const value of ['oldname','old@asamanion-26858.auth','a..b@gmail.com']){
   await page.locator('#username').fill(value);await page.locator('#createAccountButton').click();
   await expect(page.locator('#createNotice')).toContainText('valid email');
 }
 expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked)).toHaveLength(0);
});
