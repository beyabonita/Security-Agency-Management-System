# Local Android duty GPS test

These changes are local only. No new release APK, web deployment, or database migration is required for this test. The existing live-map RPC and permission checks are unchanged.

1. Stop the existing Flutter run completely, then run `flutter run` again on a physical Android phone. Hot reload alone cannot install the new Android service and manifest.
2. Allow precise location, notifications, and the one-time Android background battery request. The on-duty location panel has been removed. Android's ongoing duty notification remains visible while tracking.
3. Open attendance at the assigned post. GPS starts acquiring automatically; the page consumes ongoing measurements and recovers without repeated Retry taps. Record Time In.
4. Open the supervisor's Live Guard Map. A real fix captured after Time In places the marker; until then the guard remains listed as waiting for GPS. Walk and check that the marker moves between actual reported locations.
5. Lock the phone and leave it screen-off for at least five minutes. Continue walking and check the map's capture time. Check a longer screen-off interval too, especially on phones with manufacturer battery management.
6. Briefly disconnect and reconnect data, then toggle location off and on. Updates should resume automatically. The last known marker should retain its original timestamp during the interruption.
7. Time Out. Confirm the marker disappears and the duty notification stops (the attendance screen may temporarily acquire location while visible). Also verify that a short test shift stops at its scheduled end while the phone is locked.

`flutter run` prints `[Duty GPS]` status changes without coordinates or credentials. Android foreground-service compilation and automated lifecycle tests do not substitute for this physical screen-off test. No phone was connected during implementation. Force-stop, device shutdown, permission revocation, and an OS-killed Flutter process cannot be treated as uninterrupted tracking; reopening the app verifies duty before restarting. Emulator mock fixes remain rejected by the production attendance and location rules.

Implementation: an app-level owner receives successful attendance results immediately and keeps a short GPS handoff subscription while an older duty query finishes. Android holds a location foreground service, CPU/Wi-Fi locks, and a native duty deadline. GPS, network, and platform fused providers remain registered through acquisition; only a provider silent for two minutes is restarted. Valid timestamps, measured accuracy, mock checks, duty boundaries, and server authorization remain enforced. Background uploads refresh the guard's expiring auth session without requiring the screen to resume.
