(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.SchedulePeriod = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
  const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
  const MONTHS = Object.freeze([
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ]);

  function pad(value) {
    return String(value).padStart(2, '0');
  }

  function toLocalDateString(value) {
    if (!(value instanceof Date) || Number.isNaN(value.getTime())) return '';
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(value).reduce((result, part) => {
      result[part.type] = part.value;
      return result;
    }, {});
    return `${parts.year}-${parts.month}-${parts.day}`;
  }

  function addDays(dateValue, count) {
    if (!dtrPeriodForDate(dateValue)) return '';
    const day = new Date(`${dateValue}T00:00:00Z`);
    day.setUTCDate(day.getUTCDate() + count);
    return day.toISOString().slice(0, 10);
  }

  function timeString(value) {
    if (!(value instanceof Date) || Number.isNaN(value.getTime())) return '';
    return new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).format(value);
  }

  function parseLocalDateTime(dateValue, timeValue) {
    if (!DATE_PATTERN.test(String(dateValue || '')) || !TIME_PATTERN.test(String(timeValue || ''))) {
      return null;
    }
    if (!dtrPeriodForDate(dateValue)) return null;
    const parsed = new Date(`${dateValue}T${timeValue}:00+08:00`);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function calculate(dutyDate, startTime, endTime) {
    const startAt = parseLocalDateTime(dutyDate, startTime);
    const sameDateEnd = parseLocalDateTime(dutyDate, endTime);
    if (!startAt || !sameDateEnd || startTime === endTime) return null;

    const endAt = new Date(sameDateEnd.getTime());
    const overnight = endAt <= startAt;
    if (overnight) endAt.setTime(endAt.getTime() + 24 * 60 * 60 * 1000);

    return {
      dutyDate,
      startAt,
      endAt,
      endDate: toLocalDateString(endAt),
      overnight,
      durationMinutes: Math.round((endAt - startAt) / 60000),
    };
  }

  /**
   * Pick the first date on which a shift with the supplied times has not
   * already ended. This keeps a freshly reset schedule form usable late in
   * the day while still allowing an in-progress or upcoming shift today.
   */
  function firstSchedulableDutyDate(nowValue, startTime, endTime) {
    const now = nowValue instanceof Date ? new Date(nowValue.getTime()) : new Date(nowValue);
    if (Number.isNaN(now.getTime())) return '';

    const today = toLocalDateString(now);
    const todayShift = calculate(today, startTime, endTime);
    if (!todayShift || todayShift.endAt.getTime() > now.getTime()) return today;

    return addDays(today, 1);
  }

  const PERIOD_LABELS = Object.freeze({
    auto: 'Continuous shift', morning: 'Morning', afternoon: 'Afternoon', overtime: 'Overtime',
  });

  function buildDutyPlan(dutyDate, entries) {
    if (!dtrPeriodForDate(dutyDate)) return { error: 'Choose a valid duty date.', periods: [] };
    if (!Array.isArray(entries) || !entries.length || entries.length > 3) {
      return { error: 'Enable at least one duty period.', periods: [] };
    }
    const seen = new Set();
    const periods = [];
    for (const entry of entries) {
      const label = PERIOD_LABELS[entry.period];
      if (!label || seen.has(entry.period)) return { error: 'Each DTR period can be entered only once.', periods: [] };
      seen.add(entry.period);
      const startDate = entry.next_day ? addDays(dutyDate, 1) : dutyDate;
      const shift = calculate(startDate, entry.start_time, entry.end_time);
      if (!shift) return { error: `${label}: enter different, valid Time In and Time Out values.`, periods: [] };
      periods.push({ ...entry, ...shift, label, dutyDate });
    }
    if (seen.has('auto') && (seen.has('morning') || seen.has('afternoon'))) {
      return { error: 'Use either a continuous shift or separate DTR periods.', periods: [] };
    }
    periods.sort((left, right) => left.startAt - right.startAt);
    for (let index = 1; index < periods.length; index += 1) {
      if (periods[index].startAt < periods[index - 1].endAt) {
        return { error: `${periods[index - 1].label} and ${periods[index].label} overlap. Adjust their times.`, periods: [] };
      }
    }
    return {
      error: null, periods,
      durationMinutes: periods.reduce((total, period) => total + period.durationMinutes, 0),
      cutoff: dtrPeriodForDate(dutyDate),
    };
  }

  function firstDutyPlanDate(nowValue, entries) {
    const now = nowValue instanceof Date ? nowValue : new Date(nowValue);
    const today = toLocalDateString(now);
    if (!today) return '';
    const plan = buildDutyPlan(today, entries);
    return !plan.error && plan.periods.some(period => period.endAt <= now) ? addDays(today, 1) : today;
  }

  function formatDuration(minutes) {
    const safeMinutes = Math.max(0, Number(minutes) || 0);
    const hours = Math.floor(safeMinutes / 60);
    const remainder = safeMinutes % 60;
    if (!hours) return `${remainder} min`;
    if (!remainder) return hours === 1 ? '1 hour' : `${hours} hours`;
    return `${hours}h ${remainder}m`;
  }

  function dtrPeriodForDate(dutyDate) {
    if (!DATE_PATTERN.test(String(dutyDate || ''))) return null;
    const [year, month, day] = dutyDate.split('-').map(Number);
    const parsed = new Date(year, month - 1, day);
    if (
      Number.isNaN(parsed.getTime()) ||
      parsed.getFullYear() !== year ||
      parsed.getMonth() !== month - 1 ||
      parsed.getDate() !== day
    ) return null;

    const lastDay = new Date(year, month, 0).getDate();
    const firstCutoff = day <= 15;
    const startDay = firstCutoff ? 1 : 16;
    const endDay = firstCutoff ? 15 : lastDay;
    return {
      cutoff: firstCutoff ? 'first' : 'second',
      startDate: `${year}-${pad(month)}-${pad(startDay)}`,
      endDate: `${year}-${pad(month)}-${pad(endDay)}`,
      label: `${MONTHS[month - 1]} ${startDay}–${endDay}, ${year}`,
      shortLabel: firstCutoff ? '1st–15th' : `16th–${endDay}${endDay === 31 ? 'st' : endDay === 22 ? 'nd' : endDay === 23 ? 'rd' : 'th'}`,
    };
  }

  function dtrColumnForTime(timeValue, direction, nextDay, period = 'auto') {
    if (!TIME_PATTERN.test(String(timeValue || '')) || !['IN', 'OUT'].includes(direction)) return null;
    const hour = Number(String(timeValue).slice(0, 2));
    const section = period !== 'auto' && PERIOD_LABELS[period]
      ? PERIOD_LABELS[period]
      : (hour < 12 || (direction === 'OUT' && timeValue === '12:00') ? 'Morning' : 'Afternoon');
    const dayOffset = typeof nextDay === 'number' ? Math.max(0, nextDay) : nextDay ? 1 : 0;
    return {
      section,
      direction,
      nextDay: Boolean(nextDay),
      dayOffset,
      label: `${section} ${direction}${dayOffset === 1 ? ' (next day)' : dayOffset > 1 ? ` (${dayOffset} days later)` : ''}`,
    };
  }

  function dtrPlacement(dutyDate, startTime, endTime, dtrPeriod = 'auto', nextDay = false) {
    const shift = calculate(nextDay ? addDays(dutyDate, 1) : dutyDate, startTime, endTime);
    const period = dtrPeriodForDate(dutyDate);
    if (!shift || !period) return null;
    return {
      period,
      timeIn: dtrColumnForTime(startTime, 'IN', nextDay ? 1 : 0, dtrPeriod),
      timeOut: dtrColumnForTime(endTime, 'OUT', (nextDay ? 1 : 0) + (shift.overnight ? 1 : 0), dtrPeriod),
      overnight: shift.overnight,
    };
  }

  return Object.freeze({
    addDays,
    buildDutyPlan,
    calculate,
    dtrColumnForTime,
    dtrPeriodForDate,
    dtrPlacement,
    firstSchedulableDutyDate,
    firstDutyPlanDate,
    formatDuration,
    parseLocalDateTime,
    toLocalDateString,
    timeString,
    periodLabels: PERIOD_LABELS,
  });
});
