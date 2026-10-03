# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: account_email.spec.js >> staff email login normalizes Gmail and retains legacy access
- Location: web\tests\account_email.spec.js:3:55

# Error details

```
Error: page.evaluate: ReferenceError: Cannot access 'auth' before initialization
    at login (http://127.0.0.1:4173/staff/login.html:189:610)
    at eval (eval at evaluate (:311:30), <anonymous>:1:7)
    at UtilityScript.evaluate (<anonymous>:313:16)
    at UtilityScript.<anonymous> (<anonymous>:1:44)
```

# Page snapshot

```yaml
- generic [ref=e1]:
  - link "Skip to sign in" [ref=e2] [cursor=pointer]:
    - /url: "#staffLoginForm"
  - status [ref=e3]:
    - generic [ref=e4]: Verifying your account…
  - main [ref=e7]:
    - region "Twenty-Twenty Security Agency staff access" [ref=e8]:
      - complementary [ref=e9]:
        - generic [ref=e16]:
          - strong [ref=e17]: Twenty-Twenty Security Agency
          - generic [ref=e18]: Security Agency Management System
        - generic [ref=e19]:
          - paragraph [ref=e20]: Staff access
          - heading [level=1] [ref=e22]:
            - text: Twenty-Twenty
            - emphasis [ref=e23]: Security Agency
          - paragraph [ref=e24]: Security Agency Management System
        - generic "Staff roles" [ref=e25]:
          - article [ref=e26]:
            - generic [ref=e27]: business
            - generic [ref=e29]:
              - strong [ref=e30]: Operations Head
              - generic [ref=e31]: Personnel and deployment
          - article [ref=e32]:
            - generic [ref=e33]: verified_user
            - generic [ref=e35]:
              - strong [ref=e36]: Inspector
              - generic [ref=e37]: Field review and response
        - region [ref=e38]:
          - link "Download the Android Guard app directly" [ref=e39] [cursor=pointer]:
            - /url: https://security-agency-management-system-download.vercel.app/downloads/security-agency-management-system-guard.apk?v=1.0.17
            - img "Scan to download the Android Guard app APK directly" [ref=e40]
          - generic [ref=e41]:
            - paragraph [ref=e42]: Guard mobile app
            - heading "Scan. Install. Report for duty." [level=2] [ref=e43]
            - paragraph [ref=e44]: Scan to download the Android app directly.
            - generic "App details" [ref=e45]:
              - generic [ref=e46]: Android
              - generic [ref=e47]: v1.0.17
              - generic [ref=e48]: Build 18
            - link "Open mobile setup" [ref=e49] [cursor=pointer]:
              - /url: ./app-download.html
              - generic [ref=e50]: download
              - text: Open mobile setup
      - generic [ref=e51]:
        - generic [ref=e52]:
          - generic [ref=e53]: Secure staff access
          - button "Switch to dark mode" [ref=e56] [cursor=pointer]:
            - generic [ref=e57]: dark_mode
            - generic [ref=e58]: Dark mode
        - generic [ref=e59]:
          - generic [ref=e60]:
            - paragraph [ref=e61]: Authorized personnel
            - heading "Welcome back" [level=2] [ref=e62]
            - generic [ref=e63]: Sign in using your agency account.
          - generic [ref=e64]:
            - generic [ref=e65]:
              - generic [ref=e66]: Email
              - generic [ref=e67]:
                - generic: person
                - textbox "Email" [ref=e68]:
                  - /placeholder: name@gmail.com
                  - text: Guard.Name@gmail.com
            - generic [ref=e69]:
              - generic [ref=e70]: Password
              - generic [ref=e72]:
                - generic: lock
                - textbox "Password" [active] [ref=e73]:
                  - /placeholder: Enter your password
                  - text: AppPass1!
                - button "Show password" [ref=e74] [cursor=pointer]
            - alert [ref=e78]
            - button "Signing in…" [disabled] [ref=e79]:
              - generic [ref=e81]: arrow_forward
          - generic [ref=e82]: Protected agency workspace
          - generic [ref=e84]:
            - generic [ref=e85]: smartphone
            - generic [ref=e86]:
              - strong [ref=e87]: Are you a Guard?
              - generic [ref=e88]: Use the mobile attendance app.
            - link "Get app" [ref=e89] [cursor=pointer]:
              - /url: ./app-download.html
        - generic [ref=e90]:
          - generic [ref=e91]: © 2026 Twenty-Twenty Security Agency
          - generic [ref=e92]: System online
```