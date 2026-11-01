const { test, expect } = require('@playwright/test');

test('clicking personnel name opens rich profile card modal with personal and employment info', async ({ page }) => {
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/**', route => route.fulfill({
    contentType: 'text/javascript',
    body: '',
  }));
  await page.route('https://cdnjs.cloudflare.com/**', route => route.fulfill({
    contentType: 'text/javascript',
    body: '',
  }));
  await page.route('**/notification-center.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: '',
  }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      const mockGuard = {
        id: 'guard-1',
        first_name: 'Angel',
        middle_name: 'Pajarillo',
        last_name: 'Samanion',
        personnel_id: 'SEC-2026-0042',
        email: 'angel.twentyagency@gmail.com',
        mobile_number: '09105187319',
        role: 'user',
        active: true,
        employment_category: 'contract',
        contract_status: 'Active',
        contract_start_date: '2026-09-22',
        contract_end_date: '2026-12-22',
        date_of_birth: '1998-05-14',
        gender: 'Female',
        civil_status: 'Single',
        complete_address: 'Blk 12 Lot 4, Brgy. Mansilingan, Bacolod City',
        date_hired: '2025-01-15',
        license_security_url: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jvXkAAAAASUVORK5CYII=',
        license_firearms_url: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jvXkAAAAASUVORK5CYII='
      };

      const rows = {
        profiles: [
          { id: 'admin-1', role: 'admin', active: true, first_name: 'Admin', last_name: 'User' },
          mockGuard
        ],
        locations: [
          { id: 'loc-1', label: 'Robinsons Place Bacolod', address: 'Lacson St, Mandalagan, Bacolod City' }
        ],
        guard_assignment_history: [
          { id: 'assign-1', guard_id: 'guard-1', location_id: 'loc-1', assigned_at: '2026-01-15T00:00:00Z', ended_at: null, remarks: 'Assigned as primary entrance post' }
        ],
        guard_contract_history: [
          { id: 'contract-1', guard_id: 'guard-1', contract_start_date: '2026-09-22', contract_end_date: '2026-12-22', contract_status: 'Active', renewed_at: '2026-09-22T08:00:00Z', remarks: '3-Month renewal agreement' }
        ],
        schedules: []
      };

      function snapshot(data) {
        return {
          size: data.length,
          docs: data.map(row => ({ id: row.id, exists: true, data: () => ({
            ...row,
            firstName: row.first_name,
            middleName: row.middle_name,
            lastName: row.last_name,
            personnelId: row.personnel_id,
            mobileNumber: row.mobile_number,
            gender: row.gender,
            civilStatus: row.civil_status,
            employmentCategory: row.employment_category,
            contractStatus: row.contract_status,
            contractStartDate: row.contract_start_date,
            contractEndDate: row.contract_end_date,
            dateOfBirth: row.date_of_birth,
            completeAddress: row.complete_address,
            dateHired: row.date_hired,
            licenseSecurityUrl: row.license_security_url,
            licenseFirearmsUrl: row.license_firearms_url
          }) })),
          forEach(callback) { this.docs.forEach(callback); }
        };
      }

      function query(table) {
        const source = table === 'users' ? 'profiles' : table;
        const api = {
          select() { return api; },
          order() {
            return {
              limit() { return Promise.resolve({ data: rows[source] || [], error: null }); },
              then(resolve) { return resolve({ data: rows[source] || [], error: null }); }
            };
          },
          eq(field, value) {
            const filtered = (rows[source] || []).filter(r => r[field] === value);
            return {
              single: async () => ({ data: filtered[0] || null, error: null }),
              get: async () => snapshot(filtered),
              order() {
                return {
                  limit() { return Promise.resolve({ data: filtered, error: null }); },
                  then(resolve) { return resolve({ data: filtered, error: null }); }
                };
              },
              then(resolve) { return resolve({ data: filtered, error: null }); }
            };
          },
          async get() { return snapshot(rows[source] || []); },
          doc(id) {
            return {
              get: async () => ({
                exists: true,
                data: () => {
                  const r = (rows[source] || []).find(x => x.id === id) || {};
                  return {
                    ...r,
                    firstName: r.first_name,
                    middleName: r.middle_name,
                    lastName: r.last_name,
                    personnelId: r.personnel_id,
                    mobileNumber: r.mobile_number,
                    gender: r.gender,
                    civilStatus: r.civil_status,
                    employmentCategory: r.employment_category,
                    contractStatus: r.contract_status,
                    contractStartDate: r.contract_start_date,
                    contractEndDate: r.contract_end_date,
                    dateOfBirth: r.date_of_birth,
                    completeAddress: r.complete_address,
                    dateHired: r.date_hired,
                    licenseSecurityUrl: r.license_security_url,
                    licenseFirearmsUrl: r.license_firearms_url
                  };
                }
              })
            };
          },
          update() {
            return { eq: async () => ({ error: null }) };
          },
          insert() {
            return Promise.resolve({ data: null, error: null });
          },
          then(resolve) {
            return resolve({ data: rows[source] || [], error: null });
          }
        };
        return api;
      }

      window.firebase = {
        auth: () => ({
          onAuthStateChanged: callback => setTimeout(() => callback({ uid: 'admin-1', email: 'admin@twentyagency.com' }), 0),
          signOut: async () => {}
        }),
        firestore: () => ({
          collection: table => query(table)
        })
      };

      window.appSupabase = {
        from: table => query(table),
        auth: { getSession: async () => ({ data: { session: null } }) },
        functions: { invoke: async (name, opts) => {
          if (name === 'admin-manage-user' && opts?.body?.userId) {
            const p = (rows.profiles || []).find(x => x.id === opts.body.userId);
            if (p) {
              if (opts.body.personnelId) p.personnel_id = opts.body.personnelId;
              if (opts.body.completeAddress) p.complete_address = opts.body.completeAddress;
              if (opts.body.licenseSecurityUrl) p.license_security_url = opts.body.licenseSecurityUrl;
              if (opts.body.licenseFirearmsUrl) p.license_firearms_url = opts.body.licenseFirearmsUrl;
            }
          }
          return { data: {}, error: null };
        } },
        rpc: async (name, params) => {
          if (name === 'update_personnel_profile' && params?.p_user_id) {
            const p = (rows.profiles || []).find(x => x.id === params.p_user_id);
            if (p) {
              if (params.p_personnel_id) p.personnel_id = params.p_personnel_id;
              if (params.p_complete_address) p.complete_address = params.p_complete_address;
              if (params.p_license_security_url) p.license_security_url = params.p_license_security_url;
              if (params.p_license_firearms_url) p.license_firearms_url = params.p_license_firearms_url;
            }
          }
          return { data: null, error: null };
        }
      };

      window.applyAdminRoleNavigation = () => {};
      window.finishPageLoading = () => {
        const loader = document.getElementById('loadingScreen');
        if (loader) loader.style.display = 'none';
      };

      if (!window.bootstrap) {
        window.bootstrap = {
          Modal: {
            getOrCreateInstance: (el) => ({
              show: () => { if (el) { el.classList.add('show'); el.style.display = 'block'; } },
              hide: () => { if (el) { el.classList.remove('show'); el.style.display = 'none'; } }
            })
          }
        };
      }

      window.appDialog = {
        toast: (m) => { window.lastToast = m; },
        runBusy: async (btn, fn) => { await fn(); }
      };
    `
  }));

  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  page.on('pageerror', err => console.log('PAGE ERROR:', err.message));

  await page.goto('/admin/users.html');
  await expect(page.locator('#guardTableBody')).toBeVisible();

  // 1. Verify clickable personnel name and Personnel ID badge
  const nameButton = page.locator('#guardTableBody button.personnel-name-link').first();
  await expect(nameButton).toBeVisible();
  await expect(nameButton).toContainText('Angel Pajarillo Samanion');
  await expect(page.locator('.badge-personnel-id').first()).toContainText('SEC-2026-0042');

  // 2. Click the name to open the Personnel Record Profile modal
  await nameButton.click();
  const profileModal = page.locator('#personnelProfileModal');
  await expect(profileModal).toBeVisible();

  // Verify Personal Information section
  await expect(profileModal).toContainText('Personal Information');
  await expect(profileModal).toContainText('Angel Pajarillo Samanion');
  await expect(profileModal).toContainText('Female');
  await expect(profileModal).toContainText('Single');
  await expect(profileModal).toContainText('Mansilingan, Bacolod City');
  await expect(profileModal).toContainText('09105187319');

  // Verify Employment Information section
  await expect(profileModal).toContainText('Employment Information');
  await expect(profileModal).toContainText('Contract');
  await expect(profileModal).toContainText('SEC-2026-0042');
  await expect(profileModal).toContainText('Years / Months of Service');

  // Verify Uploaded Licenses section
  await expect(profileModal).toContainText('License to Exercise Security Profession (LESP)');
  await expect(profileModal).toContainText('License to Carry Firearms (LTCF)');
  await expect(profileModal.locator('img[alt="Security License"]')).toBeVisible();
  await expect(profileModal.locator('img[alt="Firearms License"]')).toBeVisible();

  // 3. Test opening Edit Profile from the profile modal
  const editBtn = page.locator('#profileModalEditBtn');
  await expect(editBtn).toBeVisible();
  await editBtn.click();

  const editModal = page.locator('#editPersonnelModal');
  await expect(editModal).toBeVisible();
  await expect(editModal.locator('#editGuardFirstName')).toHaveValue('Angel');
  await expect(editModal.locator('#editGuardMiddleName')).toHaveValue('Pajarillo');
  await expect(editModal.locator('#editGuardLastName')).toHaveValue('Samanion');
  await expect(editModal.locator('#editGuardPersonnelId')).toHaveValue('SEC-2026-0042');
  await expect(editModal.locator('#editGuardMobileNumber')).toHaveValue('09105187319');
  await expect(editModal.locator('#editGuardAddress')).toHaveValue('Blk 12 Lot 4, Brgy. Mansilingan, Bacolod City');

  // 4. Test opening History Modal
  await page.evaluate(() => viewAssignmentHistory('guard-1'));
  const historyModal = page.locator('#assignmentHistoryModal');
  await expect(historyModal).toBeVisible();
  await expect(page.locator('#assignmentHistoryGuardName')).toContainText('Angel Pajarillo Samanion');

  // Verify Contract & Renewal History tab
  const contractPane = page.locator('#historyContractTabPane');
  await expect(contractPane).toBeVisible();
  await expect(contractPane).toContainText('Contract Expiration & Renewal Status');
  await expect(contractPane).toContainText('December 22, 2026');
  await expect(contractPane).toContainText('September 22, 2026');
  await expect(contractPane).toContainText('Contract Renewal & Extension History');
  await expect(contractPane).toContainText('3-Month renewal agreement');

  // Switch to Establishments tab
  await page.locator('#historyEstablishmentsTabBtn').click();
  const establishmentsPane = page.locator('#historyEstablishmentsTabPane');
  await expect(establishmentsPane).toBeVisible();
  await expect(establishmentsPane).toContainText('Robinsons Place Bacolod');
  await expect(establishmentsPane).toContainText('Lacson St, Mandalagan, Bacolod City');
  await expect(establishmentsPane).toContainText('Current Active Home Post');
  await expect(establishmentsPane).toContainText('Assigned as primary entrance post');

  // 5. Test saving edits with updated documents and verifying in profile modal
  await page.evaluate(() => {
    bootstrap.Modal.getOrCreateInstance(document.getElementById("assignmentHistoryModal")).hide();
    openEditPersonnelModal('guard-1');
  });
  await editModal.locator('#editGuardPersonnelId').fill('SEC-2026-9999');
  await editModal.locator('#editGuardAddress').fill('Updated Guard Address, Metro Manila');
  await page.evaluate(() => {
    editSecurityLicenseData = 'data:image/png;base64,UPDATED_SECURITY_LICENSE';
    editFirearmsLicenseData = 'data:image/png;base64,UPDATED_FIREARMS_LICENSE';
  });
  await editModal.locator('#editGuardSaveBtn').click();

  // Re-open profile modal and verify updated values and license images
  await nameButton.click();
  await expect(profileModal).toContainText('SEC-2026-9999');
  await expect(profileModal).toContainText('Updated Guard Address, Metro Manila');
  const secImg = profileModal.locator('img[alt="Security License"]');
  await expect(secImg).toBeVisible();
  await expect(secImg).toHaveAttribute('src', 'data:image/png;base64,UPDATED_SECURITY_LICENSE');
  const fireImg = profileModal.locator('img[alt="Firearms License"]');
  await expect(fireImg).toBeVisible();
  await expect(fireImg).toHaveAttribute('src', 'data:image/png;base64,UPDATED_FIREARMS_LICENSE');
});

test('guard personnel search input filters with debounce, combines with dropdowns, updates count badge, clears, and stays responsive in dark mode', async ({ page }) => {
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/**', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('https://cdnjs.cloudflare.com/**', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/platform-configuration.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/admin-shell.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.applyAdminRoleNavigation = () => {};
      window.finishPageLoading = () => {
        const loader = document.getElementById('loadingScreen');
        if (loader) loader.style.display = 'none';
      };
      class MockModal {
        constructor(el) { this.el = el; }
        show() { if (this.el) { this.el.classList.add('show'); this.el.style.display = 'block'; } }
        hide() { if (this.el) { this.el.classList.remove('show'); this.el.style.display = 'none'; } }
        static getOrCreateInstance(el) { return new MockModal(el); }
      }
      window.bootstrap = { Modal: MockModal };
      window.appDialog = {
        toast: (m) => { window.lastToast = m; },
        runBusy: async (btn, fn) => { await fn(); }
      };
    `
  }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      const profiles = [
        { id: 'admin-1', role: 'admin', active: true, firstName: 'Nicor', lastName: 'Bea' },
        {
          id: 'g-1', role: 'user', active: true,
          firstName: 'Trix', middleInitial: 'E', lastName: 'Aguilar',
          personnelId: 'SEC-2026-089', email: 'trixx.twentyagency@gmail.com',
          employmentCategory: 'contract', contractStartDate: '2026-01-01', contractEndDate: '2027-04-06',
          assignedLocationId: null
        },
        {
          id: 'g-2', role: 'user', active: true,
          firstName: 'Mia', middleInitial: 'P', lastName: 'Allyssa',
          personnelId: 'SEC-2026-071', email: 'allyssa.twentyagency@gmail.com',
          employmentCategory: 'contract', contractStartDate: '2026-01-01', contractEndDate: '2026-02-01',
          assignedLocationId: 'loc-chmsu'
        },
        {
          id: 'g-3', role: 'user', active: false,
          firstName: 'Juanito', middleName: 'Golez', lastName: 'Damasco',
          personnelId: 'SEC-2026-090', email: 'juanito.twentyagency@gmail.com',
          employmentCategory: 'regular',
          assignedLocationId: 'loc-sm'
        }
      ];
      const locations = [
        { id: 'loc-chmsu', label: 'Carlos Hilado Memorial State University - Talisay', address: 'Mabini Street, Talisay, Negros Occidental' },
        { id: 'loc-sm', label: 'SM City Bacolod', address: 'Reclamation Area, Bacolod City' }
      ];
      const snapshot = (items) => ({
        size: items.length,
        forEach(cb) { items.forEach(item => cb({ id: item.id, exists: true, data: () => item })); }
      });
      window.firebase = {
        auth: () => ({ onAuthStateChanged: cb => setTimeout(() => cb({ uid: 'admin-1' }), 0), signOut: async () => {} }),
        firestore: () => ({
          collection: () => ({
            get: async () => snapshot(profiles),
            doc: id => ({ get: async () => ({ exists: true, data: () => profiles.find(p => p.id === id) || {} }) })
          })
        })
      };
      window.appSupabase = {
        from: table => ({
          select: () => {
            const data = table === 'locations' ? locations : [];
            return {
              order: async () => ({ data, error: null }),
              then: resolve => resolve({ data, error: null })
            };
          }
        })
      };
      window.applyAdminRoleNavigation = () => {};
    `
  }));

  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/admin/users.html');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('3');

  const searchInput = page.locator('#guardSearchInput');
  const clearBtn = page.locator('#guardSearchClearBtn');
  await expect(searchInput).toBeVisible();
  await expect(searchInput).toHaveAttribute('placeholder', 'Search name, ID, or email...');
  await expect(clearBtn).toBeHidden();

  // Partial case-insensitive match by Full Name (debounced ~300ms)
  await searchInput.fill('trix aguilar');
  await expect(clearBtn).toBeVisible();
  await expect(page.locator('#guardPersonnelCount')).toHaveText('1');
  await expect(page.locator('#guardTableBody tr')).toHaveCount(1);
  await expect(page.locator('#guardTableBody')).toContainText('Trix E. Aguilar');

  // Match by SEC ID
  await searchInput.fill('sec-2026-071');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('1');
  await expect(page.locator('#guardTableBody')).toContainText('Mia P. Allyssa');

  // Match by Email
  await searchInput.fill('JUANITO.TWENTYAGENCY');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('1');
  await expect(page.locator('#guardTableBody')).toContainText('Juanito Golez Damasco');

  // Match by Assigned Post
  await searchInput.fill('carlos hilado');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('1');
  await expect(page.locator('#guardTableBody')).toContainText('Mia P. Allyssa');

  // Clear (X) button restores all results immediately
  await clearBtn.click();
  await expect(searchInput).toHaveValue('');
  await expect(clearBtn).toBeHidden();
  await expect(page.locator('#guardPersonnelCount')).toHaveText('3');
  await expect(page.locator('#guardTableBody tr')).toHaveCount(3);

  // Combines with Status and Category filters
  await page.locator('#guardStatusFilter').selectOption('active');
  await searchInput.fill('twentyagency');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('2');
  await page.locator('#guardCategoryFilter').selectOption('contract_active');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('1');
  await expect(page.locator('#guardTableBody')).toContainText('Trix E. Aguilar');

  // Empty state when nothing matches
  await searchInput.fill('nonexistent-guard-xyz');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('0');
  await expect(page.locator('#guardTableBody')).toContainText('No personnel found');

  // Reset filters clears search + dropdowns
  await page.locator('#guardFilterResetBtn').click();
  await expect(searchInput).toHaveValue('');
  await expect(page.locator('#guardStatusFilter')).toHaveValue('all');
  await expect(page.locator('#guardCategoryFilter')).toHaveValue('all');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('3');

  // Dark mode + mobile responsiveness (390px)
  await page.evaluate(() => window.sentinelTheme?.set('dark'));
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.setViewportSize({ width: 390, height: 844 });
  const overflow = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    scroll: document.documentElement.scrollWidth
  }));
  expect(overflow.scroll).toBeLessThanOrEqual(overflow.viewport + 1);
  await expect(searchInput).toBeVisible();
});

test('prevents duplicate registration of an already registered mobile number or Personnel ID on create and edit', async ({ page }) => {
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/**', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('https://cdnjs.cloudflare.com/**', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/platform-configuration.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/admin-shell.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.applyAdminRoleNavigation = () => {};
      window.finishPageLoading = () => {
        const loader = document.getElementById('loadingScreen');
        if (loader) loader.style.display = 'none';
      };
      class MockModal {
        constructor(el) { this.el = el; }
        show() { if (this.el) { this.el.classList.add('show'); this.el.style.display = 'block'; } }
        hide() { if (this.el) { this.el.classList.remove('show'); this.el.style.display = 'none'; } }
        static getOrCreateInstance(el) { return new MockModal(el); }
      }
      window.bootstrap = { Modal: MockModal };
      window.appDialog = {
        toast: (m) => { window.lastToast = m; },
        runBusy: async (btn, fn) => { await fn(); }
      };
    `
  }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      const rows = {
        profiles: [
          { id: 'admin-1', role: 'admin', active: true, first_name: 'Admin', last_name: 'User', email: 'admin@twentyagency.com' },
          {
            id: 'guard-1', role: 'user', active: true,
            first_name: 'Angel', middle_name: 'Pajarillo', last_name: 'Samanion',
            personnel_id: 'SEC-2026-0042', email: 'angel.twentyagency@gmail.com',
            mobile_number: '09105187319', employment_category: 'regular', contract_status: 'Active'
          },
          {
            id: 'guard-2', role: 'user', active: true,
            first_name: 'Carlo', middle_name: 'Reyes', last_name: 'Diaz',
            personnel_id: 'SEC-2026-0043', email: 'carlo.twentyagency@gmail.com',
            mobile_number: '09171234567', employment_category: 'regular', contract_status: 'Active'
          }
        ],
        locations: []
      };

      const toClient = (r) => ({
        ...r,
        firstName: r.first_name,
        middleName: r.middle_name,
        lastName: r.last_name,
        personnelId: r.personnel_id,
        mobileNumber: r.mobile_number,
        employmentCategory: r.employment_category,
        contractStatus: r.contract_status
      });

      const snapshot = (items) => ({
        empty: items.length === 0,
        size: items.length,
        docs: items.map(r => ({ id: r.id, exists: true, data: () => toClient(r) })),
        forEach(cb) { this.docs.forEach(cb); }
      });

      window.createInvocations = 0;
      window.manageInvocations = 0;

      window.firebase = {
        auth: () => ({
          currentUser: { uid: 'admin-1' },
          onAuthStateChanged: cb => setTimeout(() => cb({ uid: 'admin-1', email: 'admin@twentyagency.com' }), 0),
          signOut: async () => {}
        }),
        firestore: () => ({
          collection: () => ({
            get: async () => snapshot(rows.profiles),
            where: (field, _op, val) => ({
              limit: () => ({
                get: async () => snapshot(rows.profiles.filter(p => String(p[field] || '').toLowerCase() === String(val || '').toLowerCase()))
              })
            }),
            doc: id => ({
              get: async () => ({ exists: true, data: () => toClient(rows.profiles.find(p => p.id === id) || {}) })
            })
          })
        })
      };

      window.appSupabase = {
        from: table => ({
          select: () => ({
            eq: (field, val) => ({
              limit: async () => ({ data: (rows[table] || []).filter(r => r[field] === val), error: null }),
              then: resolve => resolve({ data: (rows[table] || []).filter(r => r[field] === val), error: null })
            }),
            ilike: (field, val) => ({
              limit: async () => ({ data: (rows[table] || []).filter(r => String(r[field] || '').toLowerCase() === String(val || '').toLowerCase()), error: null })
            }),
            order: async () => ({ data: rows[table] || [], error: null }),
            then: resolve => resolve({ data: rows[table] || [], error: null })
          })
        }),
        auth: { getSession: async () => ({ data: { session: { access_token: 'mock-token' } } }) },
        functions: {
          invoke: async (name, opts) => {
            if (name === 'admin-create-user') {
              window.createInvocations += 1;
              const b = opts.body;
              const created = {
                id: 'guard-' + (rows.profiles.length + 1),
                role: b.role,
                active: true,
                first_name: b.firstName,
                middle_name: b.middleName,
                last_name: b.lastName,
                personnel_id: b.personnelId,
                email: b.email,
                mobile_number: b.mobileNumber,
                employment_category: b.employmentCategory || 'regular',
                contract_status: b.contractStatus || 'Active'
              };
              rows.profiles.push(created);
              return { data: { id: created.id }, error: null };
            }
            if (name === 'admin-manage-user') {
              window.manageInvocations += 1;
              const b = opts.body;
              const target = rows.profiles.find(p => p.id === b.userId);
              if (target) {
                target.first_name = b.firstName;
                target.last_name = b.lastName;
                target.mobile_number = b.mobileNumber;
                target.personnel_id = b.personnelId;
              }
              return { data: { ok: true }, error: null };
            }
            return { data: {}, error: null };
          }
        },
        rpc: async () => ({ data: null, error: null })
      };

      window.applyAdminRoleNavigation = () => {};
      window.finishPageLoading = () => {
        const loader = document.getElementById('loadingScreen');
        if (loader) loader.style.display = 'none';
      };
      if (!window.bootstrap) {
        const modalRegistry = new WeakMap();
        class MockModal {
          constructor(el) { this.el = el; }
          show() { if (this.el) { this.el.classList.add('show'); this.el.style.display = 'block'; } }
          hide() { if (this.el) { this.el.classList.remove('show'); this.el.style.display = 'none'; } }
          static getOrCreateInstance(el) {
            if (!modalRegistry.has(el)) modalRegistry.set(el, new MockModal(el));
            return modalRegistry.get(el);
          }
        }
        window.bootstrap = { Modal: MockModal };
      }
      window.appDialog = {
        toast: (m) => { window.lastToast = m; },
        runBusy: async (_btn, fn) => { await fn(); }
      };
    `
  }));

  await page.goto('/admin/users.html');
  await expect(page.locator('#guardPersonnelCount')).toHaveText('2');

  // 1. Initial state: no REQUIRED badges, no red borders, and top banner hidden
  await page.evaluate(() => openPersonnelCreate());
  await expect(page.locator('#createGuardModal')).toBeVisible();
  await expect(page.locator('#createGuardRequiredLegend')).toBeHidden();
  for (const id of [
    'newGuardRole',
    'newGuardEmploymentCategory',
    'newGuardPersonnelId',
    'newGuardFirstName',
    'newGuardLastName',
    'newGuardUsername',
    'newGuardPassword',
    'newGuardPasswordConfirm'
  ]) {
    await expect(page.locator(`label[for="${id}"] .badge-field-required`)).toBeHidden();
    await expect(page.locator(`#${id}`)).not.toHaveClass(/is-field-invalid/);
  }

  // On blur: leaving a required field empty shows its REQUIRED badge + red border; typing clears it immediately
  await page.locator('#newGuardFirstName').focus();
  await page.locator('#newGuardMiddleName').focus();
  await expect(page.locator('label[for="newGuardFirstName"] .badge-field-required')).toBeVisible();
  await expect(page.locator('#newGuardFirstName')).toHaveClass(/is-field-invalid/);
  await page.locator('#newGuardFirstName').fill('Temp');
  await expect(page.locator('label[for="newGuardFirstName"] .badge-field-required')).toBeHidden();
  await expect(page.locator('#newGuardFirstName')).not.toHaveClass(/is-field-invalid/);

  // Reset when modal is reopened: goes back to clean initial state with no badges
  await page.locator('#newGuardFirstName').fill('');
  await page.locator('#newGuardMiddleName').focus();
  await expect(page.locator('label[for="newGuardFirstName"] .badge-field-required')).toBeVisible();
  await page.evaluate(() => openPersonnelCreate());
  await expect(page.locator('#createGuardRequiredLegend')).toBeHidden();
  await expect(page.locator('label[for="newGuardFirstName"] .badge-field-required')).toBeHidden();
  await expect(page.locator('#newGuardFirstName')).not.toHaveClass(/is-field-invalid/);

  // On submit with missing fields: show top banner + REQUIRED badge/red border ONLY on empty required fields, and focus first missing field
  await page.locator('#createGuardBtn').click();
  expect(await page.evaluate(() => window.createInvocations)).toBe(0);
  await expect(page.locator('#createGuardRequiredLegend')).toBeVisible();
  await expect(page.locator('#createGuardRequiredLegend')).toContainText('Please fill out the required fields.');
  // Filled fields do NOT show REQUIRED badge
  for (const filledId of ['newGuardRole', 'newGuardEmploymentCategory', 'newGuardPersonnelId']) {
    await expect(page.locator(`label[for="${filledId}"] .badge-field-required`)).toBeHidden();
    await expect(page.locator(`#${filledId}`)).not.toHaveClass(/is-field-invalid/);
  }
  // Empty required fields DO show REQUIRED badge and red border
  for (const emptyId of ['newGuardFirstName', 'newGuardLastName', 'newGuardUsername', 'newGuardPassword', 'newGuardPasswordConfirm']) {
    await expect(page.locator(`label[for="${emptyId}"] .badge-field-required`)).toBeVisible();
    await expect(page.locator(`#${emptyId}`)).toHaveClass(/is-field-invalid/);
  }
  expect(await page.evaluate(() => document.activeElement?.id)).toBe('newGuardFirstName');

  // Inline format validation under Email and 11-digit Phone starting with 09
  await page.locator('#newGuardUsername').fill('not-an-email');
  await page.locator('#newGuardMobileNumber').focus();
  await expect(page.locator('label[for="newGuardUsername"] .badge-field-required')).toBeHidden();
  await expect(page.locator('#newGuardUsernameError')).toBeVisible();
  await expect(page.locator('#newGuardUsername')).toHaveClass(/is-field-invalid/);

  await page.locator('#newGuardMobileNumber').fill('0812345');
  await page.locator('#newGuardAddress').focus();
  await expect(page.locator('#newGuardMobileNumberError')).toBeVisible();
  await expect(page.locator('#newGuardMobileNumberError')).toContainText('11-digit mobile number starting with 09');
  await expect(page.locator('#newGuardMobileNumber')).toHaveClass(/is-field-invalid/);

  // Live fix clears badges, red borders, inline errors, and top banner immediately without clicking Create
  await page.locator('#newGuardFirstName').fill('Marco');
  await expect(page.locator('label[for="newGuardFirstName"] .badge-field-required')).toBeHidden();
  await expect(page.locator('#newGuardFirstName')).not.toHaveClass(/is-field-invalid/);

  await page.locator('#newGuardLastName').fill('Santos');
  await page.locator('#newGuardUsername').fill('marco.twentyagency@gmail.com');
  await expect(page.locator('#newGuardUsernameError')).toBeHidden();
  await expect(page.locator('#newGuardUsername')).not.toHaveClass(/is-field-invalid/);

  await page.locator('#newGuardMobileNumber').fill('09105187319');
  await expect(page.locator('#newGuardMobileNumberError')).toBeHidden();
  await expect(page.locator('#newGuardMobileNumber')).not.toHaveClass(/is-field-invalid/);

  await page.locator('#newGuardPersonnelId').fill('SEC-2026-0100');
  await page.locator('#newGuardPassword').fill('ValidPass123!');
  await page.locator('#newGuardPasswordConfirm').fill('ValidPass123!');
  // All required fields are now filled: top banner hides automatically
  await expect(page.locator('#createGuardRequiredLegend')).toBeHidden();
  await page.locator('#createGuardBtn').click();

  await expect(page.locator('#createGuardError')).toHaveText(
    'This mobile number is already registered to another personnel record.'
  );
  expect(await page.evaluate(() => window.createInvocations)).toBe(0);

  // 2. Attempt to register with a unique mobile number, but an already-registered Personnel ID (case-insensitive)
  await page.locator('#newGuardMobileNumber').fill('09189998888');
  await page.locator('#newGuardPersonnelId').fill('sec-2026-0042');
  await page.locator('#createGuardBtn').click();

  await expect(page.locator('#createGuardError')).toHaveText(
    'This Personnel ID is already registered to another personnel record.'
  );
  expect(await page.evaluate(() => window.createInvocations)).toBe(0);

  // 3. Unique mobile number and Personnel ID succeeds
  await page.locator('#newGuardPersonnelId').fill('SEC-2026-0100');
  await page.locator('#createGuardBtn').click();
  expect(await page.evaluate(() => window.createInvocations)).toBe(1);
  await expect(page.locator('#guardPersonnelCount')).toHaveText('3');

  // 4. Verify Required pill badges + top legend on Edit Personnel modal, and editing guard-2 to use guard-1's mobile number is blocked
  await page.evaluate(() => openEditPersonnelModal('guard-2'));
  await expect(page.locator('#editPersonnelModal')).toBeVisible();
  await expect(page.locator('#editGuardRequiredLegend')).toBeVisible();
  for (const id of [
    'editGuardPersonnelId',
    'editGuardEmploymentCategory',
    'editGuardFirstName',
    'editGuardLastName',
    'editGuardEmail'
  ]) {
    await expect(page.locator(`label[for="${id}"] .badge-field-required`)).toHaveText('Required');
  }
  await expect(page.locator('label[for="editGuardMobileNumber"] .badge-field-required')).toHaveCount(0);
  await expect(page.locator('#editPersonnelModal input#editGuardPassword')).toBeVisible();
  await page.locator('#editGuardMobileNumber').fill('09105187319');
  await page.locator('#editGuardSaveBtn').click();

  await expect(page.locator('#editGuardError')).toHaveText(
    'This mobile number is already registered to another personnel record.'
  );
  expect(await page.evaluate(() => window.manageInvocations)).toBe(0);

  // 5. Editing guard-2 to use guard-1's Personnel ID is blocked
  await page.locator('#editGuardMobileNumber').fill('09171234567');
  await page.locator('#editGuardPersonnelId').fill('SEC-2026-0042');
  await page.locator('#editGuardSaveBtn').click();

  await expect(page.locator('#editGuardError')).toHaveText(
    'This Personnel ID is already registered to another personnel record.'
  );
  expect(await page.evaluate(() => window.manageInvocations)).toBe(0);

  // 6. Keeping guard-2's own mobile number and Personnel ID saves cleanly without false duplicate error
  await page.locator('#editGuardPersonnelId').fill('SEC-2026-0043');
  await page.locator('#editGuardSaveBtn').click();
  expect(await page.evaluate(() => window.manageInvocations)).toBe(1);
});

test('guard profile customization syncs live to Personnel Record Profile without refresh and Operations Head can remove/replace photo', async ({ page }) => {
  const samplePhoto = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jvXkAAAAASUVORK5CYII=';

  await page.route('https://cdn.jsdelivr.net/npm/@supabase/**', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('https://cdnjs.cloudflare.com/**', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/notification-center.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/platform-configuration.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route('**/admin-shell.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.applyAdminRoleNavigation = () => {};
      window.finishPageLoading = () => {
        const loader = document.getElementById('loadingScreen');
        if (loader) loader.style.display = 'none';
      };
      class MockModal {
        constructor(el) { this.el = el; }
        show() { if (this.el) { this.el.classList.add('show'); this.el.style.display = 'block'; } }
        hide() { if (this.el) { this.el.classList.remove('show'); this.el.style.display = 'none'; } }
        static getOrCreateInstance(el) { return new MockModal(el); }
      }
      window.bootstrap = { Modal: MockModal };
      window.appDialog = {
        toast: (m) => { window.lastToast = m; },
        runBusy: async (btn, fn) => { await fn(); }
      };
    `
  }));
  await page.route('**/supabase-firebase-bridge.js', route => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.photoEdgeCalls = [];
      const rows = {
        profiles: [
          { id: 'admin-1', role: 'admin', active: true, first_name: 'Admin', last_name: 'User' },
          {
            id: 'guard-ta',
            first_name: 'Tomas',
            last_name: 'Aquino',
            personnel_id: 'SEC-2026-0099',
            email: 'tomas.aquino@gmail.com',
            mobile_number: '09171234567',
            complete_address: 'Old Address, Bacolod City',
            emergency_contact: 'Juan Aquino (Brother) — 09180001111',
            profile_photo_url: null,
            role: 'user',
            active: true,
            employment_category: 'regular',
            contract_status: 'Active'
          }
        ],
        locations: [],
        guard_assignment_history: [],
        guard_contract_history: [],
        schedules: []
      };

      function mapRow(row) {
        return {
          ...row,
          firstName: row.first_name,
          middleName: row.middle_name,
          lastName: row.last_name,
          personnelId: row.personnel_id,
          mobileNumber: row.mobile_number,
          completeAddress: row.complete_address,
          emergencyContact: row.emergency_contact,
          profilePhotoUrl: row.profile_photo_url,
          employmentCategory: row.employment_category,
          contractStatus: row.contract_status
        };
      }

      function snapshot(data) {
        return {
          size: data.length,
          docs: data.map(r => ({ id: r.id, exists: true, data: () => mapRow(r) })),
          forEach(fn) { this.docs.forEach(fn); }
        };
      }

      function query(table) {
        const source = table === 'users' ? 'profiles' : table;
        const api = {
          select() { return api; },
          order() {
            return {
              limit() { return Promise.resolve({ data: rows[source] || [], error: null }); },
              then(resolve) { return resolve({ data: rows[source] || [], error: null }); }
            };
          },
          eq(field, value) {
            const filtered = (rows[source] || []).filter(r => r[field] === value);
            return {
              neq(f2, v2) {
                const sub = filtered.filter(r => r[f2] !== v2);
                return { limit: async () => ({ data: sub, error: null }), then: res => res({ data: sub, error: null }) };
              },
              single: async () => ({ data: filtered[0] || null, error: null }),
              maybeSingle: async () => ({ data: filtered[0] || null, error: null }),
              get: async () => snapshot(filtered),
              order() {
                return {
                  limit() { return Promise.resolve({ data: filtered, error: null }); },
                  then(resolve) { return resolve({ data: filtered, error: null }); }
                };
              },
              then(resolve) { return resolve({ data: filtered, error: null }); }
            };
          },
          ilike() {
            return {
              neq() {
                return { limit: async () => ({ data: [], error: null }) };
              }
            };
          },
          async get() { return snapshot(rows[source] || []); },
          doc(id) {
            return {
              get: async () => {
                const found = (rows[source] || []).find(r => r.id === id);
                return { id, exists: !!found, data: () => found ? mapRow(found) : undefined };
              }
            };
          },
          then(resolve) { return resolve({ data: rows[source] || [], error: null }); }
        };
        return api;
      }

      window.appSupabase = {
        auth: {
          getSession: async () => ({ data: { session: null } }),
          getUser: async () => ({ data: { user: { id: 'admin-1', email: 'admin@twentyagency.com' } }, error: null })
        },
        channel(name) {
          return {
            on(type, filter, cb) {
              window.realtimeProfileCallback = cb;
              return this;
            },
            subscribe() { return this; }
          };
        },
        from: table => query(table),
        rpc: async () => ({ data: null, error: null }),
        functions: {
          invoke: async (fnName, opts) => {
            if (fnName === 'profile-photo') {
              window.photoEdgeCalls.push(opts.body);
              const g = rows.profiles.find(p => p.id === opts.body.targetUserId);
              if (opts.body.action === 'remove') {
                if (g) g.profile_photo_url = null;
                return { data: { ok: true, profilePhotoUrl: null }, error: null };
              }
              if (g) g.profile_photo_url = opts.body.photoBase64;
              return { data: { ok: true, profilePhotoUrl: opts.body.photoBase64 }, error: null };
            }
            if (fnName === 'admin-manage-user') {
              const b = opts?.body || {};
              const g = rows.profiles.find(p => p.id === b.userId);
              if (g) {
                g.mobile_number = b.mobileNumber;
                g.complete_address = b.completeAddress;
                g.emergency_contact = b.emergencyContact;
              }
              return { data: { ok: true }, error: null };
            }
            return { data: { ok: true }, error: null };
          }
        }
      };

      window.firebase = {
        auth: () => ({
          currentUser: { uid: 'admin-1', email: 'admin@twentyagency.com' },
          onAuthStateChanged: cb => setTimeout(() => cb({ uid: 'admin-1', email: 'admin@twentyagency.com' }), 0),
          signOut: async () => {}
        }),
        firestore: () => ({
          collection: table => query(table)
        })
      };
    `,
  }));

  await page.goto('/admin/users.html');
  await expect(page.locator('#guardTableBody tr')).toHaveCount(1);

  // 1. Guard with no photo shows colored initials ("TA") in table row and Personnel Record Profile modal
  await page.locator('.personnel-name-link', { hasText: 'Tomas Aquino' }).click();
  await expect(page.locator('#personnelProfileModal')).toBeVisible();
  const modalAvatar = page.locator('#personnelProfileBody .profile-modal-avatar');
  await expect(modalAvatar).toContainText('TA');
  await expect(modalAvatar.locator('img.personnel-avatar-img')).toHaveCount(0);
  await expect(page.locator('[data-profile-field="mobile_number"] .profile-data-value')).toHaveText('09171234567');
  await expect(page.locator('[data-profile-field="complete_address"] .profile-data-value')).toHaveText('Old Address, Bacolod City');
  await expect(page.locator('[data-profile-field="emergency_contact"] .profile-data-value')).toHaveText('Juan Aquino (Brother) — 09180001111');

  // 2. Simulate live Realtime update from Guard mobile app while modal is open (NO page refresh!)
  await page.evaluate(photo => {
    window.realtimeProfileCallback({
      eventType: 'UPDATE',
      new: {
        id: 'guard-ta',
        role: 'user',
        active: true,
        first_name: 'Tomas',
        last_name: 'Aquino',
        personnel_id: 'SEC-2026-0099',
        email: 'tomas.aquino@gmail.com',
        mobile_number: '09995554444',
        complete_address: 'Lot 8 Blk 3, Brgy. Villamonte, Bacolod City',
        emergency_contact: 'Maria Aquino (Spouse) — 09201112222',
        profile_photo_url: photo,
        employment_category: 'regular',
        contract_status: 'Active'
      }
    });
  }, samplePhoto);

  // Photo replaces "TA" avatar and updated contact number, address, and emergency contact appear immediately!
  await expect(modalAvatar.locator('img.personnel-avatar-img')).toHaveAttribute('src', samplePhoto);
  await expect(page.locator('[data-profile-field="mobile_number"] .profile-data-value')).toHaveText('09995554444');
  await expect(page.locator('[data-profile-field="complete_address"] .profile-data-value')).toHaveText('Lot 8 Blk 3, Brgy. Villamonte, Bacolod City');
  await expect(page.locator('[data-profile-field="emergency_contact"] .profile-data-value')).toHaveText('Maria Aquino (Spouse) — 09201112222');

  // 3. Operations Head opens Edit Profile and removes the guard's photo
  await page.locator('#profileModalEditBtn').click();
  await expect(page.locator('#editPersonnelModal')).toBeVisible();
  await expect(page.locator('#editGuardRemovePhotoBtn')).toBeVisible();
  await page.locator('#editGuardRemovePhotoBtn').click();
  await expect(page.locator('#editGuardRemovePhotoBtn')).toBeHidden();
  await page.locator('#editGuardSaveBtn').click();

  expect(await page.evaluate(() => window.photoEdgeCalls)).toEqual([
    { action: 'remove', targetUserId: 'guard-ta' }
  ]);
  await expect(page.locator('#guardTableBody .personnel-row-avatar img.personnel-avatar-img')).toHaveCount(0);
});
