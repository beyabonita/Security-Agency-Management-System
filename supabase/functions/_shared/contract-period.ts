// Calendar dates are agency dates (Asia/Manila), never browser-local timestamps.
export function contractPeriod(
  category: string,
  start: unknown,
  end: unknown,
  allowLegacyUnset = false,
): { start: string | null; end: string | null; error?: string } {
  if (category !== "contract") return { start: null, end: null };
  if (allowLegacyUnset && !start && !end) return { start: null, end: null };
  const valid = (value: unknown): value is string => {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      return false;
    }
    const date = new Date(value + "T00:00:00Z");
    return Number.isFinite(date.getTime()) &&
      date.toISOString().slice(0, 10) === value &&
      value >= "1900-01-01" && value <= "9998-12-31";
  };
  if (!valid(start) || !valid(end)) {
    return {
      start: null,
      end: null,
      error: "Set valid contract start and end dates.",
    };
  }
  if (end < start) {
    return {
      start: null,
      end: null,
      error: "Contract end date must be on or after the start date.",
    };
  }
  return { start, end };
}
