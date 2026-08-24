# Sentinel Link

Sentinel Link is a security operations platform for TwentyTwenty Security Agency, combining a Flutter mobile app for guards, web portals for staff, and a Supabase-powered backend for identity, scheduling, attendance, incidents, notifications, and authorization.

This repository is structured for a real-world agency workflow with strict role boundaries, geofenced attendance validation, and a multi-layered deployment model for mobile and web.

## Overview

The system is designed around a single beneficiary model:

- TwentyTwenty Security Agency is the active organization.
- Client sites such as Jollibee branches are deployment locations managed under that agency.
- Guards can only operate and clock in at approved scheduled sites.
- HR/Operations, Inspectors, and IT Admin each have separate responsibilities and tools.

## Core platform

### Mobile app
The Flutter application in `lib/` is the primary guard-facing experience. It includes:

- Secure login and role-based routing
- Attendance and time-in/time-out workflows
- Geofence-aware duty validation and location integrity checks
- Notifications and acknowledgement flows
- Duty requests and shift-change workflows
- Incident reporting with media capture
- Time logs and attendance summaries

### Web portals
The static web app in `web/` contains the staff-facing portal and supporting admin/inspector experiences. These are deployed to Vercel and are intended for operations workflows rather than mobile guard use.

### Backend and data layer
Supabase provides:

- authentication and session handling
- tenant-aware data access patterns
- Row Level Security boundaries
- database migrations and SQL validation
- Edge Functions for privileged operations
- notifications and workflow event data

## Roles and responsibilities

### Guard
Uses the mobile app for:

- login and attendance
- check-in/check-out at assigned duty posts
- shift and duty request management
- incident reports and evidence capture
- viewing time logs and notifications

### HR / Operations Head
Manages:

- guard and inspector accounts
- deployment sites and geofences
- schedules and assignments
- attendance approvals and operational records
- staffing and operational tracking

### Inspector
Reviews:

- shift-change requests
- guard attendance records
- site activity and compliance concerns
- inspector attendance and monitoring tasks

### IT Admin
Maintains the platform, including:

- privileged access and account operations
- platform support and recovery workflows
- configuration and deployment governance
- upgrade and release coordination

## System architecture

Sentinel Link combines client-side mobile and web apps with a managed cloud backend:

Flutter mobile app
  -> Supabase Auth + Postgres
  -> guarded business logic and RLS-backed access
  -> Edge Functions for admin-sensitive operations

Static web portal
  -> Vercel deployment
  -> admin / inspector / system access interfaces
  -> same Supabase backend

## Repository structure

```text
.
├── android/                 # Android app configuration
├── ios/                    # iOS app configuration
├── linux/                  # Linux desktop support
├── macos/                  # macOS desktop support
├── windows/                # Windows desktop support
├── web/                    # Static web application and portal assets
├── supabase/               # SQL migrations, functions, tests, config
├── lib/                    # Flutter app source code
├── test/                   # Flutter and integration tests
├── docs/                   # rollout and deployment guidance
├── assets/                 # app branding and visual assets
├── analysis_options.yaml   # Dart lint configuration
├── pubspec.yaml            # Flutter package definition
├── README.md               # project overview and setup guide
├── .gitignore              # repository ignores
├── .env.local              # local environment metadata (not for app secrets)
└── ...
```

## Tech stack

- Flutter + Dart
- Supabase
- PostgreSQL / SQL schema migrations
- Edge Functions for protected operations
- Flutter Map and geolocation APIs
- Camera and media handling for incident reporting
- Vercel for static web deployment
- GitHub Actions for CI validation

## Prerequisites

- Flutter 3.47+
- Dart SDK compatible with the project
- Node.js 20+
- A Supabase project linked to this repository
- Vercel access for static web deployment if hosting the web portal

## Quick start

### 1) Install dependencies

```bash
flutter pub get
```

### 2) Run the mobile app

```bash
flutter run
```

### 3) Build APK for testing or distribution

```bash
flutter build apk --debug
```

The output is generated under:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

For Android release signing and publishing guidance, see `docs/MOBILE_RELEASE.md`.

## Supabase setup

This project expects a linked Supabase project and a migration-based setup.

```bash
npx --yes supabase login
npx --yes supabase link --project-ref <project-ref>
npx --yes supabase db push
```

After modifying protected functions, deploy them explicitly:

```bash
npx --yes supabase functions deploy admin-create-user
npx --yes supabase functions deploy admin-manage-user
npx --yes supabase functions deploy it-provision-client
```

Important:

- Never expose a Supabase service-role key in Flutter or frontend code.
- Keep privileged logic behind Edge Functions and Row Level Security.
- Use the public publishable key only in client-facing configuration.

## Web deployment

The static web app should be deployed from the `web/` directory, not from the Flutter repository root, so build artifacts do not get published to Vercel by accident.

```bash
npx --yes vercel link --cwd web
npx --yes vercel --cwd web --prod
```

## Development and verification

Run the project checks before pushing changes:

```bash
flutter analyze --no-fatal-infos
flutter test
node web/tests/security_rendering_test.js
node web/tests/session_refresh_test.js
node supabase/tests/admin_create_user_security_test.js
node supabase/tests/edge_function_authorization_test.js
```

For database and schema changes, run the linked Supabase validation flow:

```bash
npx --yes supabase db lint --linked --level warning
```

Additional local validation is included in the repository:

```bash
npm ci --prefix web/tests
npx --prefix web/tests playwright install chromium
npm run --prefix web/tests test:playwright

npx --yes supabase start
npx --yes supabase test db supabase/tests/database
npx --yes supabase stop
```

## Security and operating model

This platform intentionally enforces a disciplined operational model:

- production is scoped to a single active beneficiary: TwentyTwenty Security Agency
- operational history is preserved by deactivating accounts instead of deleting them
- attendance must come from fresh, accurate location data and be checked against the scheduled duty geofence
- GPS spoofing cannot be fully prevented in client-only apps, so stronger mobile attestation and managed-device controls are recommended for fraud resistance

## Release notes and docs

- `docs/MOBILE_RELEASE.md` – Android release build and signing notes
- `docs/ROLLOUT_TEST_PLAN.md` – staged rollout, functional, and performance test plan
- `supabase/README.md` – Supabase-specific guidance

## GitHub-ready workflow

This repository is set up for clean collaboration and CI-driven validation. The expected workflow is:

1. create a branch for the feature or fix
2. run the relevant local tests and lint checks
3. update migrations or SQL checks when schema changes are introduced
4. verify web deployment targets and environment constraints
5. push to GitHub and let CI validate the build

## License

This project is currently configured as an internal/private application and is not intended for public package publication.

## Notes

This repository contains both app code and platform operations logic. Before deploying to production, verify:

- Supabase project linkage and migration status
- web deployment target configuration
- role access boundaries
- geofence and attendance validation behavior
- release signing and environment gating

If you are preparing this repository for a public GitHub push, make sure you review any environment-specific values, secrets, and deployment URLs before publishing.
