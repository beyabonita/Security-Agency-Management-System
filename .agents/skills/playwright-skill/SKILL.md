---
name: playwright-skill
description: >-
  Playwright end-to-end browser testing, responsive viewport validation, Leaflet map mocking, and authentication route interception for Operations Head and Inspector web consoles.
---

# Playwright Web Testing Playbook

This skill outlines testing practices, route mocking strategies, and assertion standards for the web test suites in `web/tests/`.

---

## 1. Test Configuration & Server Environment

- **Configuration File**: `web/tests/playwright.config.cjs`
- **Base URL**: `http://127.0.0.1:4173`
- **Static Test Server**: `web/tests/static_server.js` serves the `web/` directory with production-matching Content-Type headers.
- **Single Threading**: Use `fullyParallel: false` to ensure shared local ports and mock states do not conflict.

---

## 2. Mocking Supabase & Leaflet Maps

- **SDK Mocking (`page.route`)**:
  Intercept external CDN scripts (`@supabase/supabase-js`, `leaflet.js`) and compatibility bridges (`supabase-firebase-bridge.js`) to return local mock objects:
  ```javascript
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.3', route => route.fulfill({
    contentType: 'text/javascript',
    body: '',
  }));
  ```
- **Clock Virtualization**:
  Use `page.clock.install({ time: new Date(...) })` to test time-dependent age calculations (e.g., GPS fix age `15s ago`, shift expiration) deterministically without relying on wall-clock drift.
- **Leaflet Mock Shapes**:
  Mock `window.L` to capture marker positions, viewports, and popups:
  ```javascript
  window.L = {
    map: () => ({ setView: (c, z) => {}, fitBounds: () => {} }),
    marker: (center, opts) => shape(center, opts),
    circleMarker: (center, opts) => shape(center, opts),
    divIcon: (opts) => ({ ...opts }),
  };
  ```

---

## 3. Responsive & Accessibility Testing

- **Desktop & Mobile Breakpoints**: Always test both desktop (`1440x960`) and mobile (`390x844` / iPhone 12/13/14 size).
- **Horizontal Overflow Guard**:
  ```javascript
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  ```
- **Accessible Attributes**:
  Check `aria-label`, `role="button"`, `tabindex="0"`, and keyboard navigation (`Escape`, `Enter`).

---

## 4. Test Execution Command

Run web integration suites via:
```powershell
Set-Location web/tests
npx playwright test <spec_file>.spec.js --config=playwright.config.cjs
```
