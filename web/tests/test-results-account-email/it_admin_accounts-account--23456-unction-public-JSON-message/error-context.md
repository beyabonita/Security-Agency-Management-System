# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: it_admin_accounts.spec.js >> account editing shows the Edge Function public JSON message
- Location: web\tests\it_admin_accounts.spec.js:201:1

# Error details

```
Error: expect(received).toEqual(expected) // deep equality

- Expected  - 1
+ Received  + 1

  Array [
    Object {
      "body": Object {
        "action": "update",
+       "email": "operations.admin@gmail.com",
        "firstName": "Operations",
        "lastName": "Operations Head",
        "password": "",
        "role": "admin",
        "userId": "22222222-2222-4222-8222-222222222222",
-       "username": "operations.admin",
      },
      "name": "admin-manage-user",
    },
  ]
```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - link "Skip to main content" [ref=e2] [cursor=pointer]:
    - /url: "#main-content"
  - generic [ref=e3]:
    - complementary [ref=e4]:
      - generic [ref=e5]:
        - generic [ref=e6]: Security Agency Management System
        - paragraph [ref=e7]: IT Admin Panel
        - paragraph [ref=e8]: Platform maintenance
      - navigation [ref=e9]:
        - generic [ref=e10]: System
        - link "System overview" [ref=e11] [cursor=pointer]:
          - /url: dashboard.html
          - generic [ref=e12]: dashboard
          - text: System overview
        - link "System controls" [ref=e13] [cursor=pointer]:
          - /url: clients.html
          - generic [ref=e14]: tune
          - text: System controls
        - link "IT & Operations Head access" [ref=e15]:
          - /url: users.html
          - generic [ref=e16]: admin_panel_settings
          - text: IT & Operations Head access
      - generic [ref=e17]: System administration
    - generic [ref=e18]:
      - banner [ref=e19]:
        - generic [ref=e21]:
          - generic [ref=e22]: System Administration
          - heading "IT & Operations Head access" [level=1] [ref=e23]
        - generic [ref=e24]:
          - button "Switch to dark mode" [ref=e26] [cursor=pointer]:
            - generic [ref=e27]: dark_mode
            - generic [ref=e28]: Dark mode
          - button "0 unread notifications" [ref=e30] [cursor=pointer]:
            - generic [ref=e31]: notifications
          - button "Sign out" [ref=e32] [cursor=pointer]
      - main [ref=e33]:
        - generic [ref=e34]:
          - generic [ref=e35]:
            - generic [ref=e36]:
              - heading "Account activity · All roles" [level=2] [ref=e37]
              - button "Refresh activity" [ref=e38] [cursor=pointer]
            - generic [ref=e39]:
              - generic [ref=e41]:
                - text: Search name or email
                - searchbox "Search name or email" [ref=e42]
              - generic [ref=e44]:
                - text: Role
                - combobox "Role" [ref=e45]:
                  - option "All roles" [selected]
                  - option "IT Admin"
                  - option "Operations Head"
                  - option "Inspector"
                  - option "Guard"
              - generic [ref=e47]:
                - text: Connection
                - combobox "Connection" [ref=e48]:
                  - option "All connections" [selected]
                  - option "Online"
                  - option "Offline"
            - status [ref=e49]: Status unavailable. Account activity is unavailable.
            - table [ref=e51]:
              - rowgroup [ref=e52]:
                - row [ref=e53]:
                  - columnheader "Name" [ref=e54]
                  - columnheader "Email" [ref=e55]
                  - columnheader "Role" [ref=e56]
                  - columnheader "Connection" [ref=e57]
                  - columnheader "Last seen" [ref=e58]
              - rowgroup [ref=e59]:
                - row [ref=e60]:
                  - cell "Online status could not be verified." [ref=e61]
            - generic [ref=e62]:
              - button "Previous" [disabled] [ref=e63]
              - generic [ref=e64]: Page 1 of 1 · 0 records
              - button "Next" [disabled] [ref=e65]
          - generic [ref=e66]:
            - heading "Login history" [level=2] [ref=e67]
            - table [ref=e69]:
              - rowgroup [ref=e70]:
                - row [ref=e71]:
                  - columnheader "Name" [ref=e72]
                  - columnheader "Role" [ref=e73]
                  - columnheader "Client" [ref=e74]
                  - columnheader "Signed in" [ref=e75]
                  - columnheader "Last seen" [ref=e76]
                  - columnheader "Session ended" [ref=e77]
                  - columnheader "Status" [ref=e78]
              - rowgroup [ref=e79]:
                - row [ref=e80]:
                  - cell "History could not be loaded." [ref=e81]
            - generic [ref=e82]:
              - button "Previous" [disabled] [ref=e83]
              - generic [ref=e84]: Page 1 of 1 · 0 records
              - button "Next" [disabled] [ref=e85]
        - generic [ref=e86]:
          - heading "Create privileged account" [level=3] [ref=e87]
          - generic [ref=e88]:
            - generic [ref=e89]:
              - generic [ref=e90]: Role
              - combobox "Role" [ref=e91]:
                - option "Operations Head" [selected]
                - option "IT Admin"
            - generic [ref=e92]:
              - generic [ref=e93]: First name
              - textbox "First name" [ref=e94]
            - generic [ref=e95]:
              - generic [ref=e96]: Last name
              - textbox "Last name" [ref=e97]
            - generic [ref=e98]:
              - generic [ref=e99]: Email
              - textbox "Email" [ref=e100]:
                - /placeholder: name@gmail.com
            - generic [ref=e101]:
              - generic [ref=e102]: Temporary password
              - textbox "Temporary password" [ref=e103]
              - text: Use at least 8 characters with uppercase and lowercase letters, a number, and a symbol.
          - button "Create account" [ref=e105] [cursor=pointer]
        - generic [ref=e107]:
          - heading "Privileged accounts" [level=3] [ref=e108]
          - table [ref=e110]:
            - rowgroup [ref=e111]:
              - row [ref=e112]:
                - columnheader "Name" [ref=e113]
                - columnheader "Email" [ref=e114]
                - columnheader "Access scope" [ref=e115]
                - columnheader "Role" [ref=e116]
                - columnheader "Account access" [ref=e117]
                - columnheader "Actions" [ref=e118]
            - rowgroup [ref=e119]:
              - row [ref=e120]:
                - cell "Platform Owner" [ref=e121]
                - cell "platform.owner@gmail.com" [ref=e122]
                - cell "System administration" [ref=e123]
                - cell "IT Admin" [ref=e125]
                - cell "Enabled" [ref=e126]
                - cell [ref=e128]:
                  - button "Change my email" [ref=e129] [cursor=pointer]
              - row [ref=e130]:
                - cell "Operations Operations Head" [ref=e131]
                - cell "operations.admin@gmail.com" [ref=e132]
                - cell "TwentyTwenty operations" [ref=e133]
                - cell "Operations Head" [ref=e135]
                - cell "Enabled" [ref=e136]
                - cell [ref=e138]:
                  - generic [ref=e139]:
                    - button "Edit" [ref=e140] [cursor=pointer]
                    - button "Disable" [ref=e141] [cursor=pointer]
  - status:
    - alert [ref=e142]:
      - generic [ref=e143]: error
      - generic [ref=e144]: "That email address is already in use. (Request ID: req-account-edit)"
      - button "Dismiss notification" [ref=e145] [cursor=pointer]:
        - generic [ref=e146]: close
```

# Test source

```ts
  117 |                       })
  118 |                     })
  119 |                   }
  120 |                 }
  121 |               };
  122 |             }
  123 |             return { data: { ok: true }, error: null };
  124 |           }
  125 |         },
  126 |         channel: () => ({ on() { return this; }, subscribe() { return this; } }),
  127 |         removeChannel: async () => {}
  128 |       };
  129 |     })();`,
  130 |   }));
  131 | }
  132 | 
  133 | async function openAccounts(page, options = {}) {
  134 |   await mockAccountBackend(page, options);
  135 |   await page.goto('/it-admin/users.html', { waitUntil: 'domcontentloaded' });
  136 |   await expect(page.locator('#rows tr')).toHaveCount(2);
  137 | }
  138 | 
  139 | const invalidPasswords=['Aa1!abc','lowercase1!','UPPERCASE1!','NoNumbers!','NoSymbols1'];
  140 | 
  141 | test('IT Admin creation rejects each missing password requirement and accepts an eight-character mix',async({page})=>{
  142 |   await openAccounts(page);
  143 |   for(const [id,value] of Object.entries({first:'New',last:'Operations Head',username:'new.admin@gmail.com'}))await page.locator('#'+id).fill(value);
  144 |   for(const password of invalidPasswords){
  145 |     await page.locator('#password').fill(password);
  146 |     await page.locator('#createAccountButton').click();
  147 |     await expect(page.locator('#createNotice')).toContainText('uppercase letter');
  148 |     expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked)).toHaveLength(0);
  149 |   }
  150 |   await page.locator('#password').fill('Aa1!abcd');
  151 |   await page.locator('#createAccountButton').click();
  152 |   await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  153 |   expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0]))
  154 |     .toMatchObject({name:'admin-create-user',body:{password:'Aa1!abcd'}});
  155 | });
  156 | 
  157 | test('IT Admin reset validates each password requirement before sending a change',async({page})=>{
  158 |   await openAccounts(page);
  159 |   await page.locator('#rows tr').filter({hasText:'operations.admin'}).getByRole('button',{name:'Edit',exact:true}).click();
  160 |   const dialog=page.getByRole('dialog',{name:'Edit privileged account',exact:true});
  161 |   for(const password of invalidPasswords){
  162 |     await dialog.locator('[name=password]').fill(password);
  163 |     await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  164 |     await expect(dialog.locator('.sl-dialog-error')).toContainText('uppercase letter');
  165 |     expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked)).toHaveLength(0);
  166 |   }
  167 |   await dialog.locator('[name=password]').fill('Aa1!abcd');
  168 |   await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  169 |   await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  170 |   expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0]))
  171 |     .toMatchObject({name:'admin-manage-user',body:{password:'Aa1!abcd'}});
  172 | });
  173 | 
  174 | test('IT Admin keeps the password when the optional edit field is blank',async({page})=>{
  175 |   await openAccounts(page);
  176 |   await page.locator('#rows tr').filter({hasText:'operations.admin'}).getByRole('button',{name:'Edit',exact:true}).click();
  177 |   const dialog=page.getByRole('dialog',{name:'Edit privileged account',exact:true});
  178 |   await expect(dialog.locator('[name=password]')).toHaveValue('');
  179 |   await dialog.getByRole('button',{name:'Save changes',exact:true}).click();
  180 |   await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  181 |   expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0]))
  182 |     .toMatchObject({name:'admin-manage-user',body:{password:''}});
  183 | });
  184 | 
  185 | test('current IT Admin is protected while another Operations Head keeps account actions', async ({ page }) => {
  186 |   await openAccounts(page);
  187 | 
  188 |   const currentRow = page.locator('#rows tr').filter({ hasText: 'platform.owner' });
  189 |   await expect(currentRow).toContainText('Change my email');
  190 |   await expect(currentRow.getByRole('button', { name: 'Edit', exact: true })).toHaveCount(0);
  191 |   await expect(currentRow.getByRole('button', { name: 'Disable', exact: true })).toHaveCount(0);
  192 | 
  193 |   const otherRow = page.locator('#rows tr').filter({ hasText: 'operations.admin' });
  194 |   await expect(otherRow.getByRole('button', { name: 'Edit', exact: true })).toBeVisible();
  195 |   await expect(otherRow.getByRole('button', { name: 'Disable', exact: true })).toBeVisible();
  196 | 
  197 |   await expect(page.getByText(/reset\s+device/i)).toHaveCount(0);
  198 |   await expect(page.getByRole('columnheader', { name: 'Device', exact: true })).toHaveCount(0);
  199 | });
  200 | 
  201 | test('account editing shows the Edge Function public JSON message', async ({ page }) => {
  202 |   await openAccounts(page, { editFailure: true });
  203 | 
  204 |   const otherRow = page.locator('#rows tr').filter({ hasText: 'operations.admin' });
  205 |   await otherRow.getByRole('button', { name: 'Edit', exact: true }).click();
  206 | 
  207 |   const dialog = page.getByRole('dialog', { name: 'Edit privileged account', exact: true });
  208 |   await expect(dialog).toBeVisible();
  209 |   await dialog.getByRole('button', { name: 'Save changes', exact: true }).click();
  210 | 
  211 |   await expect(page.getByRole('alert')).toContainText(
  212 |     'That email address is already in use. (Request ID: req-account-edit)',
  213 |   );
  214 |   await expect(page.getByText(/Edge Function returned a non-2xx status code/i)).toHaveCount(0);
  215 | 
  216 |   const calls = await page.evaluate(() => window.itAdminAccountTestBackend.invoked);
> 217 |   expect(calls).toEqual([{
      |                 ^ Error: expect(received).toEqual(expected) // deep equality
  218 |     name: 'admin-manage-user',
  219 |     body: {
  220 |       action: 'update',
  221 |       userId: otherAdminId,
  222 |       firstName: 'Operations',
  223 |       lastName: 'Operations Head',
  224 |       username: 'operations.admin',
  225 |       role: 'admin',
  226 |       password: '',
  227 |     },
  228 |   }]);
  229 | });
  230 | 
  231 | test('IT Admin changes own email with current password and no access fields',async({page})=>{
  232 |  await openAccounts(page);
  233 |  await page.getByRole('button',{name:'Change my email'}).click();
  234 |  const dialog=page.getByRole('dialog',{name:'Change my email',exact:true});
  235 |  await dialog.locator('[name=email]').fill('Owner.New@gmail.com');
  236 |  await dialog.locator('[name=currentPassword]').fill('Current1!');
  237 |  await dialog.getByRole('button',{name:'Save email',exact:true}).click();
  238 |  await expect.poll(()=>page.evaluate(()=>window.itAdminAccountTestBackend.invoked.length)).toBe(1);
  239 |  expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked[0].body)).toEqual({action:'update',userId:currentUserId,email:'owner.new@gmail.com',currentPassword:'Current1!'});
  240 | });
  241 | test('account creation rejects legacy aliases and invalid email',async({page})=>{
  242 |  await openAccounts(page);
  243 |  for(const [id,value] of Object.entries({first:'New',last:'Head',password:'Test123!'})) await page.locator('#'+id).fill(value);
  244 |  for(const value of ['oldname','old@asamanion-26858.auth','a..b@gmail.com']){
  245 |    await page.locator('#username').fill(value);await page.locator('#createAccountButton').click();
  246 |    await expect(page.locator('#createNotice')).toContainText('valid email');
  247 |  }
  248 |  expect(await page.evaluate(()=>window.itAdminAccountTestBackend.invoked)).toHaveLength(0);
  249 | });
  250 | 
```