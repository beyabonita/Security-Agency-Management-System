---
name: postgres-best-practices
description: >-
  Supabase PostgreSQL database guidelines, Row Level Security (RLS) enforcement, PL/pgSQL RPC authoring, transaction advisory locking, and idempotent migration standards for Security Agency Management System.
---

# PostgreSQL & Supabase Database Best Practices

This skill provides guidelines and patterns for creating, optimizing, and maintaining PostgreSQL schemas, functions, and Row-Level Security (RLS) policies within Supabase for the **Twenty-Twenty Security Agency Management System**.

---

## 1. Schema & Migration Standards

- **Directory**: Store all migrations in `supabase/migrations/` using timestamp prefixes (e.g., `YYYYMMDDHHMMSS_feature_description.sql`).
- **Idempotency**: Always write idempotent DDL:
  ```sql
  create table if not exists public.example (...);
  create index if not exists idx_example_field on public.example (...);
  alter table public.example add column if not exists field_name data_type;
  ```
- **Constraint Safety**: Always check constraints before inserting or updating (e.g., coordinate ranges `-90` to `90`, `-180` to `180`, status checks like `status in ('open', 'closed', 'missed_timeout')`).
- **Schema Reload Notification**: End migrations that introduce RPCs or table changes with `notify pgrst, 'reload schema';`.

---

## 2. Row Level Security (RLS) Rules

- **Always Enable RLS**: Never expose a table without `alter table public.<table_name> enable row level security;`.
- **Revoke Public Grants**:
  ```sql
  revoke all on public.<table_name> from public, anon;
  grant select, insert, update on public.<table_name> to authenticated;
  ```
- **Helper Function Wrappers**: Use security definer tenant and role checks:
  - `public.current_organization_id()`
  - `public.is_admin()` (Operations Head)
  - `public.is_it_admin()` (Superadmin)
  - `public.is_active_guard()` / `public.is_active_duty_personnel()`
  - `private.can_view_live_guard(user_id)`

---

## 3. PL/pgSQL Function & RPC Authoring

- **Security Definer & Search Path**:
  ```sql
  create or replace function public.example_rpc(...)
  returns ...
  language plpgsql
  security definer
  set search_path = public
  as $$
  ```
- **Transaction Concurrency & Advisory Locks**:
  When preventing race conditions (such as double Time-In or simultaneous schedule claims), acquire transaction-level advisory locks:
  ```sql
  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_organization_id::text || ':' || auth.uid()::text, 0)
  );
  ```
- **Execution Context Sensitivity**:
  Remember that `auth.uid()` evaluates to the *caller*. If an Operations Head approves a guard's schedule or session in `decide_force_attendance`, complete schedules directly under `session.user_id`, rather than calling functions that assume `user_id = auth.uid()`.

---

## 4. Performance & Indexing

- Index all foreign keys (`user_id`, `schedule_id`, `location_id`, `organization_id`).
- Use partial indexes for active queues:
  ```sql
  create index if not exists idx_attendance_sessions_force_status
    on public.attendance_sessions (organization_id, force_attendance_status, clock_in_at desc)
    where force_attendance_requested = true;
  ```
- Limit JSON payload transfers: when writing RPC snapshots like `live_guard_map_snapshot`, return only required active columns.
