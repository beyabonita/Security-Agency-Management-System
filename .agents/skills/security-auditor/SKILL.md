---
name: security-auditor
description: >-
  Security auditing, Content Security Policy (CSP), host isolation, XSS prevention, and credential guardrails for the web portals and API services.
---

# Security Auditor & Defensive Guardrails

This skill provides an audit framework to ensure the **Security Agency Management System** remains resilient against unauthorized access, privilege escalation, cross-site scripting (XSS), and data leakage.

---

## 1. Subdomain & Host Isolation

- **Domain Separation**:
  - `sams-it-portal.vercel.app` & `it.tts-agency.site` $\rightarrow$ Dedicated to IT Superadmin (`/system-access-7d92a4/`).
  - `security-agency-ms.vercel.app` & `tts-agency.site` / `www.tts-agency.site` $\rightarrow$ Dedicated to Operations Head & Inspectors (`/staff/`, `/admin/`, `/inspector/`).
- **Strict Redirects**:
  Enforce explicit redirect rules in `web/vercel.json` preventing cross-portal leakage:
  - If a user accesses `/admin/*` or `/inspector/*` on `it.tts-agency.site`, redirect to `/system-access-7d92a4/login.html`.
  - If a user accesses `/it-admin/*` on `tts-agency.site`, redirect to `/staff/login.html`.

---

## 2. Content Security Policy (CSP) & HTTP Headers

Inspect `web/vercel.json` headers to maintain these strict security directives:
- `default-src 'self'`: Disallow untrusted third-party origins.
- `object-src 'none'`: Block Flash and legacy object plugins.
- `frame-ancestors 'none'`: Block clickjacking attempts.
- `X-Frame-Options: DENY`: Disallow framing in iframes.
- `X-Content-Type-Options: nosniff`: Prevent MIME confusion attacks.
- `Strict-Transport-Security: max-age=31536000; includeSubDomains`: Mandate HTTPS.
- Whitelist only required tile and geocoding services:
  `https://*.tile.openstreetmap.org`, `https://nominatim.openstreetmap.org`.

---

## 3. XSS Prevention & DOM Sanitization

- **Template Escaping**:
  Never interpolate unsanitized database or user inputs directly into `innerHTML`.
  Always use the repository's standard `escapeHtml()` helper:
  ```javascript
  function escapeHtml(text) {
    return String(text ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
  ```
- **Inline Handlers**:
  Avoid dynamic string interpolation inside inline `onclick` handlers (e.g., `onclick="view('${name}')"` can be exploited if `name` contains single quotes or HTML). Pass strictly UUIDs or bind event listeners via `addEventListener`.

---

## 4. Audit Checklist Before Pushing

1. Run `node web/tests/security_rendering_test.js` to verify DOM and script order rules.
2. Run `node web/tests/vercel_security_headers_test.js` to verify CSP and header syntax.
3. Run `node web/tests/google_icons_test.js` to ensure no unbundled Material Icons are referenced.
4. Verify RLS policies on all newly created PostgreSQL tables in `supabase/migrations/`.
