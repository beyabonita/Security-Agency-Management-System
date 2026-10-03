/** Email/password sign-in, with temporary compatibility for existing username accounts. */
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

    const email = data.email || '';
    if (email.endsWith('@' + AUTH_EMAIL_DOMAIN)) {
        return 'Email not added';
    }
    return email || 'Email not added';
}

function validateEmail(raw) {
    const email = normalizeUsername(raw);
    return email.length <= 254 && /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/i.test(email)
      && email.split('@')[0].length <= 64 && !email.startsWith('.') && !email.includes('..')
      && !email.split('@')[0].endsWith('.') && !email.endsWith('.auth')
      ? null : 'Enter a valid email address, such as name@gmail.com.';
}
function editableEmail(data) { return data?.email && !validateEmail(data.email) ? data.email : ''; }
function reportEmail(value) { return value && !String(value).toLowerCase().endsWith('.auth') ? value : 'Email not added'; }
