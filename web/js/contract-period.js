(function (root) {
    'use strict';
    function valid(value) {
        if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
        const date = new Date(value + 'T00:00:00Z');
        return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
            && value >= '1900-01-01' && value <= '9998-12-31';
    }
    function validate(category, start, end) {
        if (category !== 'contract') return '';
        if (!valid(start) || !valid(end)) return 'Set valid contract start and end dates.';
        return end < start ? 'Contract end date must be on or after the start date.' : '';
    }
    function dutyError(guard, startAt, endAt) {
        if (guard.role !== 'user' || guard.employmentCategory !== 'contract') return '';
        const start = guard.contractStartDate, end = guard.contractEndDate;
        const error = validate('contract', start, end);
        if (error) return error + ' Edit this Guard in Personnel first.';
        const lower = new Date(start + 'T00:00:00+08:00');
        const upper = new Date(new Date(end + 'T00:00:00+08:00').getTime() + 86400000);
        return startAt >= lower && endAt <= upper && endAt > startAt ? ''
            : 'Duty must start and finish within the contract: ' + start + ' to ' + end + '.';
    }
    function label(guard, now = new Date()) {
        if (guard.employmentCategory !== 'contract') return 'No contract date limit';
        const start = guard.contractStartDate, end = guard.contractEndDate;
        if (validate('contract', start, end)) return 'Set contract dates';
        const today = new Date(now.getTime() + 8 * 3600000).toISOString().slice(0, 10);
        const status = today < start ? 'Not started' : today > end ? 'Expired' : 'Active contract';
        return start + ' – ' + end + ' · ' + status;
    }
    const api = { validate, dutyError, label };
    root.ContractPeriod = api;
    if (typeof module !== 'undefined') module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
