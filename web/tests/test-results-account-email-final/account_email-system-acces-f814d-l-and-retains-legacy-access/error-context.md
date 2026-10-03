# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: account_email.spec.js >> system-access-7d92a4 email login normalizes Gmail and retains legacy access
- Location: web\tests\account_email.spec.js:3:55

# Error details

```
Error: page.evaluate: ReferenceError: Cannot access 'auth' before initialization
    at login (http://127.0.0.1:4173/system-access-7d92a4/login.html:88:685)
    at eval (eval at evaluate (:311:30), <anonymous>:1:7)
    at UtilityScript.evaluate (<anonymous>:313:16)
    at UtilityScript.<anonymous> (<anonymous>:1:44)
```

# Page snapshot

```yaml
- main [ref=e2]:
  - generic [ref=e3]:
    - img "Twenty-Twenty Security Agency" [ref=e5]
    - generic [ref=e6]: Twenty-Twenty Security Agency
    - heading "Security Agency Management System" [level=1] [ref=e7]
    - paragraph [ref=e8]: Private platform administration for maintenance, upgrades, privileged access, and system governance.
    - generic [ref=e9]: Restricted IT administrator access
  - generic [ref=e11]:
    - button "Switch to dark mode" [ref=e13] [cursor=pointer]:
      - generic [ref=e14]: dark_mode
      - generic [ref=e15]: Dark mode
    - generic [ref=e16]:
      - paragraph [ref=e17]: Private access
      - heading "Welcome back" [level=2] [ref=e18]
      - paragraph [ref=e19]: Sign in with your IT administrator credentials.
      - generic [ref=e20]: Email
      - textbox "Email" [ref=e21]:
        - /placeholder: name@gmail.com
        - text: Guard.Name@gmail.com
      - generic [ref=e22]: Password
      - generic [ref=e23]:
        - textbox "Password" [active] [ref=e24]:
          - /placeholder: Enter password
          - text: AppPass1!
        - button "Show password" [ref=e25]
      - alert [ref=e29]
      - button "Verifying access…" [disabled] [ref=e30]
```