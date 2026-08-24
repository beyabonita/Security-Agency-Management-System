/** Username login — Supabase Auth uses email/password with a synthetic address. */
const AUTH_EMAIL_DOMAIN = 'asamanion-26858.auth';

function normalizeUsername(raw) {
    return (raw || '').trim().toLowerCase();
}

function validateUsername(raw) {
    const username = normalizeUsername(raw);
    if (username.length < 3) return 'Username must be at least 3 characters.';
    if (username.length > 32) return 'Username must be 32 characters or less.';
    if (!/^[a-z0-9._]+$/.test(username)) {
        return 'Use only letters, numbers, dots, and underscores.';
    }
    return null;
}

function usernameToAuthEmail(username) {
    return normalizeUsername(username) + '@' + AUTH_EMAIL_DOMAIN;
}

/** Login input: username, or legacy email if it contains @. */
function resolveAuthEmail(input) {
    const trimmed = (input || '').trim();
    if (trimmed.includes('@')) return trimmed.toLowerCase();
    return usernameToAuthEmail(trimmed);
}

function displayLoginId(data) {
    if (!data) return '';
    if (data.username) return data.username;
    const email = data.email || '';
    if (email.endsWith('@' + AUTH_EMAIL_DOMAIN)) {
        return email.split('@')[0];
    }
    return email;
}
