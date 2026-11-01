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
