---
name: api-design-rest
description: >-
  PostgREST RPC design, JSON payload formatting, error code handling, and offline synchronization standards between mobile apps, web consoles, and Supabase.
---

# API & RPC Design Standards

This skill defines conventions for remote procedure calls (RPCs), REST interactions, and client-server synchronization protocols across the **Security Agency Management System**.

---

## 1. PostgREST RPC Parameter & Return Types

- **Naming Convention**:
  - Action RPCs: Use imperative verbs (`request_force_attendance_clock_in`, `decide_force_attendance`, `bind_or_verify_guard_device`).
  - Read/Snapshot RPCs: Use descriptive nouns (`live_guard_map_snapshot`, `get_guard_location_history`).
- **Consistent Parameter Prefixing**:
  Prefix all PL/pgSQL function parameters with `p_` (e.g., `p_user_id`, `p_session_id`, `p_device_id`) to avoid collision with column names in SQL statements.
- **Structured Return Objects**:
  Prefer returning single JSON objects or typed table rows instead of raw strings or primitives:
  ```sql
  return jsonb_build_object(
    'verified', true,
    'status', 'matched',
    'registered_device_id', v_profile.registered_device_id
  );
  ```

---

## 2. Error Code & Exception Conventions

- **SQL State Error Codes**:
  - Access Denied / Unauthorized: Raise `'42501'` (`raise exception '...' using errcode = '42501';`).
  - Validation / Business Logic Violation: Throw clear English messages with actionable instructions.
- **Client Error Unwrapping**:
  In web portals, unwrap Edge Function and RPC errors through `web/js/edge-function-errors.js` to preserve `Request ID` and status details for diagnostic logs.

---

## 3. Clock & Temporal Synchronization

- **Server Clock Authority**:
  Never rely on client device system clocks for shift expiration or attendance durations.
  Return `server_now` from snapshot endpoints and compute elapsed durations relative to the synchronized server clock (`createServerClock` in `web/js/live-tracking-model.js`).
- **Time Zone Consistency**:
  All database timestamps are stored in UTC (`timestamptz`). When rendering human-readable dates for operations in the Philippines, convert to `Asia/Manila` (PHT / UTC+8).
