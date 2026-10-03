# Guard roster and shift DTR

Scheduling uses 2 Shifts (06:00–18:00 and 18:00–06:00 next day) or 3 Shifts
(06:00–14:00, 14:00–22:00, and 22:00–06:00 next day). Each slot belongs to a
different active Guard. The roster is saved atomically with existing contract,
conflict and permission checks.

## Saved shifting setups

Operations Head → Duty Scheduling → **Create a new shifting setup** lets an
active Operations Head save an agency-owned roster with a name and 2–12 shifts.
The initial 2 Shifts and 3 Shifts are saved once as ordinary, editable and removable
setups for each agency. Saved setups appear by name
in the same dropdown and load again on subsequent visits.

Enter start/end times in Philippine time, from the earliest start to the latest.
Each shift must end exactly when the next starts; the final shift ends at the
first shift's start time the following day. This covers 24 hours without gaps
or overlaps. For example, four shifts can run 00:00–06:00, 06:00–12:00,
12:00–18:00, and 18:00–00:00 (+1 day). Setup names are unique within an agency
(ignoring case); saving the identical setup again safely returns the existing one.

Saving a setup creates no assignments or attendance. After saving, choose the
schedule date, deployment site, and a different active Guard for each remaining
shift, then assign the roster. On today's date, ended slots are skipped. Future
dates require a Guard for every slot. Contract and conflicting-duty safeguards
still apply, and the whole assignment is atomic.

Select any setup, including 2 Shifts or 3 Shifts, to use **Edit setup** or **Remove setup**. Editing
changes its name/times for future assignments. Removing archives the template
and hides it from the dropdown; existing schedules retain their assigned timestamps, DTR
starting date, and attendance. The existing Time Out verification and overtime
rules use those stored timestamps, including custom overnight shifts. This
feature needs a portal/database update; the Guard app already reads assigned
start/end timestamps and needs no new build.

Duplicate setup names or shift times are rejected within an agency, including
copies of another saved setup. Removed setups stay removed on reload. If all
setups are removed, create a new one before assigning Guards. The management migration archives earlier duplicates rather than
deleting them. Updates, removal, and assignments check the version the Head
reviewed so concurrent edits cannot silently change assignment times. Reload
saved setups to see changes made in another session.

The custom duty editor and the explanatory DTR/overtime panel are removed.
The scheduling preview and schedule history show one scheduled IN/OUT pair
per shift instead of the former Morning/Afternoon/Overtime grid.

## New Daily Time Record

Both the Operational Head and Inspector preview and PDF download use:

- Duty date
- Assigned shift / deployment site, including planned duration
- Actual Time In
- Actual Time Out
- Worked hours (H:MM)

Each attendance session gets a separate row. Multiple sessions on a duty date
are not merged into a first-IN/last-OUT pair. Blank dates remain blank, without
being automatically marked absent. Existing legacy overtime attendance remains
visible as a labeled assignment rather than a separate pair of overtime columns.

The starting duty date determines the row and the 1–15 or 16–month-end cut-off.
Next-day times are marked (+1), including across month boundaries. Actual
attendance is never filled from planned times. Missing or unverified late Time
Out excludes that session's hours until Operational Head verification. Completed
worked hours and unique completed duty-day totals keep their existing rules.

The new layout changes presentation only. It does not approve overtime pay,
change attendance records, change database authorization, or alter app punches.

## Automatic overtime hours

The DTR now places Total Overtime Hours immediately before Total Worked Hours.
For completed attendance with a known scheduled end:

- Overtime is the recorded interval after the scheduled end, rounded down to
  complete minutes. It cannot exceed the actual worked interval.
- A late Time Out must be verified by the Operations Head before either its
  worked hours or overtime hours contribute to totals.
- Total Worked Hours remains actual Time Out minus actual Time In. Overtime
  is already included; it is never added a second time.
- A 06:00–18:00 shift verified as worked 06:00–19:00 shows 1:00 overtime and
  13:00 worked. Finishing at 18:00 shows 0:00 overtime and 12:00 worked.
- Early arrival does not count as overtime under the selected rule. Overnight
  overtime stays on the shift's original duty date and cutoff.
- Missing attendance or a missing scheduled end leaves overtime blank. Completed
  attendance with no work after the scheduled end shows 0:00.
- Cutoff totals include total overtime and total worked hours in H:MM format.

This calculation does not introduce automatic overtime pay or change the existing
Time Out verification process. It applies consistently to historical sessions
using their stored scheduled end, including labeled overtime assignments.

## Shifting setup protection

A saved setup cannot be edited or removed while it has an unfinished approved,
changed, or pending assignment whose end time is still in the future. This
includes ongoing overnight shifts and future roster dates, across all sites.
Completed, cancelled, and ended assignments do not lock a setup. Historical
attendance and DTR timestamps remain independent of the setup.

New roster assignments retain their setup ID. For older assignments without an
ID, the protection matches the complete slot times in Philippine time; ambiguous
legacy slots conservatively lock each matching setup. The database checks usage
under the same setup row lock used by roster assignment. The page refreshes the
server's usage status without replacing unchanged guard selection controls and
disables editing/removal if usage cannot be checked.

Deployed on September 13, 2026: `20260913000001_lock_used_roster_setups.sql`
was applied before the updated scheduling page was published. Production includes
the setup protection, portal cleanup, six-column DTR, and readable time evaluation.
