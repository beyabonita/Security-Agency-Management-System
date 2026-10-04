const { expect, test } = require('@playwright/test');

const TEST_VIDEO_PATH = '11111111-1111-4111-8111-111111111111/incident.mp4';
const TEST_SIGNED_URL = `https://syyofdcynuzgergqlaqj.supabase.co/storage/v1/object/sign/incident-videos/${TEST_VIDEO_PATH}?token=test-token`;

async function installIncidentMocks(page) {
  await page.route('**/supabase-firebase-bridge.js', (route) => route.fulfill({
    contentType: 'text/javascript',
    body: `
      window.firebase = {
        auth: () => ({ onAuthStateChanged: () => {}, signOut: async () => {} }),
        firestore: () => ({ collection: () => ({}) })
      };
      window.signedVideoRequests = [];
      window.appSupabase = {
        storage: {
          from: (bucket) => ({
            createSignedUrl: async (path, expiresIn) => {
              window.signedVideoRequests.push({ bucket, path, expiresIn });
              return { data: { signedUrl: ${JSON.stringify(TEST_SIGNED_URL)} }, error: null };
            }
          })
        }
      };
      window.appDialog = { toast: () => {}, runBusy: async (_button, action) => action() };
    `,
  }));
  await page.route('**/storage/v1/object/sign/incident-videos/**', (route) => route.fulfill({
    status: 200,
    contentType: 'video/mp4',
    body: '',
  }));
}

async function openTestIncident(page, panel) {
  await installIncidentMocks(page);
  await page.goto(`/${panel}/incidents.html`, { waitUntil: 'domcontentloaded' });
  await page.addStyleTag({ content: '#loadingScreen{display:none!important}' });
  await page.waitForFunction(() => window.incidentReportView && typeof window.openDetail === 'function');
  await page.evaluate((videoPath) => {
    incidents = [{
      id: 'incident-report-12345678',
      guardName: 'Pedro D Dela Cruz',
      guardEmail: 'guard123@sentinel-link.local',
      category: 'crime',
      description: 'The guard observed a forced entry attempt and secured the affected area.',
      detailedNarrative: 'At approximately 5:37 PM, an unidentified person attempted to enter the restricted stock room. The guard challenged the person and secured the access point.',
      immediateAction: 'Restricted the area, informed the Inspector, and preserved the scene.',
      capturedAt: { toDate: () => new Date('2026-08-22T09:37:00Z') },
      filedAt: { toDate: () => new Date('2026-08-22T09:38:00Z') },
      createdAt: { toDate: () => new Date('2026-08-22T09:38:00Z') },
      latitude: 10.75935,
      longitude: 123.02599,
      locationLabel: 'Silay Main Post',
      photoData: 'AAAA',
      videoPath,
      videoDurationSeconds: 3,
      status: 'open',
      statusNote: '',
    }];
    openDetail('incident-report-12345678');
  }, TEST_VIDEO_PATH);
}

for (const panel of ['admin', 'inspector']) {
  test(`${panel} displays video-only evidence without claiming a photo is attached`, async ({ page }) => {
    await openTestIncident(page, panel);
    await page.evaluate(() => {
      incidents[0].photoData = null;
      openDetail(incidents[0].id);
      renderTable();
    });
    await expect(page.locator('#incidentTableBody')).toContainText('3 sec video');
    await expect(page.locator('#incidentTableBody')).not.toContainText('+ photo');
    await expect(page.locator('#modalBody')).not.toContainText('Incident photo');
    await expect(page.locator('#modalBody')).not.toContainText('Required capture');
    await expect(page.locator('#incidentEvidenceVideo')).toHaveAttribute('src', TEST_SIGNED_URL);
  });
  test(`${panel} shows Emergency and attributes acknowledgement and notes to their reviewers`, async ({ page }) => {
    await openTestIncident(page, panel);
    await page.evaluate(() => {
      incidents[0].category = 'other';
      incidents[0].status = 'acknowledged';
      incidents[0].reviewHistory = [
        { reviewer_name: 'Sam Inspector', reviewer_role: 'inspector', status: 'acknowledged', note: 'Responding now', reviewed_at: '2026-09-14T01:00:00Z' },
        { reviewer_name: 'Alex Head', reviewer_role: 'admin', status: 'acknowledged', note: '<img src=x onerror=alert(1)>', reviewed_at: '2026-09-14T02:00:00Z' },
      ];
      openDetail(incidents[0].id);
      renderTable();
    });
    await expect(page.locator('#incidentTableBody')).toContainText('Emergency');
    await expect(page.locator('#modalBody')).toContainText('Emergency');
    await expect(page.locator('#modalBody')).not.toContainText('Other');
    await expect(page.locator('#modalBody')).toContainText('Acknowledged by');
    await expect(page.locator('#modalBody')).toContainText('Sam Inspector · Inspector');
    await expect(page.locator('#modalBody')).toContainText('Alex Head · Operations Head');
    await expect(page.locator('#modalBody')).toContainText('Responding now');
    await expect(page.locator('#modalBody')).toContainText('<img src=x onerror=alert(1)>');
    await expect(page.locator('#modalBody img[src="x"]')).toHaveCount(0);
  });

  test(`${panel} incident report shows detailed private video evidence`, async ({ page }) => {
    await page.setViewportSize({ width: 1100, height: 820 });
    await openTestIncident(page, panel);

    await expect(page.locator('#detailModal')).toHaveClass(/show/);
    await expect(page.getByRole('heading', { name: 'Captured evidence' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Report details' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Incident narrative' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Response and review' })).toBeVisible();
    await expect(page.locator('#modalBody')).toContainText('Pedro D Dela Cruz');
    await expect(page.locator('#modalBody')).toContainText('Silay Main Post');
    await expect(page.locator('#modalBody')).toContainText('unidentified person attempted to enter');
    await expect(page.locator('#incidentEvidenceVideo')).toHaveAttribute('controls', '');
    await expect(page.locator('#incidentEvidenceVideo')).toHaveAttribute('src', TEST_SIGNED_URL);
    await expect(page.getByRole('link', { name: 'Open video separately' })).toHaveAttribute('href', TEST_SIGNED_URL);
    await expect(page.locator('#statusNote')).toHaveJSProperty('tagName', 'TEXTAREA');
    expect(await page.evaluate(() => window.signedVideoRequests)).toEqual([{
      bucket: 'incident-videos',
      path: TEST_VIDEO_PATH,
      expiresIn: 900,
    }]);

    await page.setViewportSize({ width: 390, height: 844 });
    const modalBounds = await page.locator('#detailModal .modal-content').boundingBox();
    expect(modalBounds).not.toBeNull();
    expect(modalBounds.x).toBeGreaterThanOrEqual(-1);
    expect(modalBounds.width).toBeLessThanOrEqual(391);
  });

  test(`${panel} detailed incident modal is readable in dark mode without altering media`, async ({ page }, info) => {
    await page.addInitScript(() => localStorage.setItem('sentinel-link-theme', 'dark'));
    await page.setViewportSize({ width: 1200, height: 1000 });
    await openTestIncident(page, panel);
    await expect(page.locator('#detailModal')).toHaveClass(/show/);
    await expect(page.locator('.incident-report-card').first()).toHaveCSS('background-color', 'rgb(33, 24, 27)');
    await expect(page.locator('.incident-meta-value').first()).toHaveCSS('color', 'rgb(248, 236, 238)');
    await expect(page.locator('.incident-report-copy').first()).toHaveCSS('color', 'rgb(248, 236, 238)');
    await expect(page.locator('#incidentEvidenceVideo')).toHaveCSS('filter', 'none');
    await expect(page.locator('.incident-report-photo')).toHaveCSS('filter', 'none');
    await page.screenshot({ path: info.outputPath(panel + '-incident-dark.png') });
  });

  test(`${panel} incident report shows embedded mini map and excludes external maps link`, async ({ page }) => {
    await openTestIncident(page, panel);
    await expect(page.locator('#detailModal')).toHaveClass(/show/);
    await expect(page.locator('#modalBody')).not.toContainText('Open exact location in Maps');
    await expect(page.locator('#incidentMiniMap')).toBeVisible();
    await expect(page.locator('.incident-mini-map-wrap')).toBeVisible();

    await page.evaluate(() => {
      incidents[0].latitude = null;
      incidents[0].longitude = null;
      openDetail(incidents[0].id);
    });
    await expect(page.locator('#incidentMiniMap')).toHaveCount(0);
    await expect(page.locator('#modalBody')).not.toContainText('Open exact location in Maps');
    await expect(page.locator('#modalBody')).toContainText('Not recorded');
  });
}
