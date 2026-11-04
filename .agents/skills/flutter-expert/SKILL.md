---
name: flutter-expert
description: >-
  Flutter (3.x+) & Dart (3.x+) engineering standards, mobile device verification, in-app camera face capture, GPS geofencing, image watermarking, and resilient state handling for the Guard Mobile App.
---

# Flutter & Dart Mobile App Engineering Guidelines

This skill provides expert patterns for developing, debugging, and testing the **Security Agency Management System Guard App** (`lib/`, `test/`).

---

## 1. Architecture & State Management

- **Controller Architecture**: Use ChangeNotifier and ValueNotifier patterns (e.g., `AttendanceStateController`, `LiveLocationController`) to keep UI decoupled from data services.
- **Async Lifecycles & Mounted Checks**: Always verify `if (!mounted) return;` after any `await` point before calling `setState()`, `Navigator`, or `ScaffoldMessenger`.
- **Text Controller Cleanup**: Prefer `TextFormField(initialValue: ...)` or dispose of `TextEditingController` cleanly in `dispose()`.

---

## 2. Hardware, Camera & Biometric Verification

- **Front-Camera Prioritization**:
  When capturing selfies for identity verification (`attendance_face_capture_dialog.dart`), prioritize `CameraLensDirection.front`.
  Provide a fallback using `ImagePicker(preferredCameraDevice: CameraDevice.front)` if the camera controller preview fails.
- **Device Hardware ID Binding**:
  - Store a persistent device installation identifier using `SharedPreferences`.
  - Validate device identity against `profiles.registered_device_id` via `bind_or_verify_guard_device`.
  - Scope cached verification results to `_cachedUserId` to prevent cross-account credential leakage.

---

## 3. GPS Geofencing & Evidence Watermarking

- **GPS Distance Calculations**:
  Use the Haversine formula (`geofence_service.dart`) to calculate distance between current device GPS and post center:
  - If inside radius $\rightarrow$ regular Time In.
  - If outside radius $\rightarrow$ Force Attendance workflow with mandatory reason prompt and geotagged selfie.
- **Geotag Watermark Overlay**:
  Every attendance photo or incident evidence photo must be stamped with a tamper-evident banner (`geotag_watermark_service.dart`) containing:
  - PHT (UTC+8) timestamp formatted as `YYYY-MM-DD HH:MM:SS AM/PM PHT`
  - Decimal GPS Coordinates (`lat, lng ±accuracy m`)
  - Post / Client Label
  - Bound Device / Hardware ID
- **Memory Optimization**: Resize high-resolution camera captures to max dimension `1280` (or `640` for attendance thumbnails) before encoding JPEG buffers to prevent Out-Of-Memory (OOM) crashes on low-end Android hardware.

---

## 4. Mobile Testing & Verification

- **Widget & Unit Tests**: Store automated tests under `test/` (e.g., `attendance_session_test.dart`, `letter_request_screen_test.dart`).
- **Mock Supabase & HTTP**: Use `MockClient` from `package:http/testing.dart` to simulate REST and RPC responses without live network dependencies.
- **Physical Size in Tests**: Configure `tester.view.physicalSize = Size(430, 932)` with `addTearDown(tester.view.resetPhysicalSize)` when testing responsive sheets.
