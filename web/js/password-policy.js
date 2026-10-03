(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.PasswordPolicy = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const requirements = 'Use at least 8 characters with at least one uppercase letter, one lowercase letter, one number, and one symbol.';
  function error(password) {
    if (typeof password !== 'string') return requirements;
    const length = Array.from(password).length;
    if (new TextEncoder().encode(password).length > 72) {
      return 'Password is too long. Use at most 72 bytes (72 characters for standard letters, numbers, and symbols).';
    }
    return length >= 8 && /[A-Z]/.test(password) &&
      /[a-z]/.test(password) && /[0-9]/.test(password) &&
      /[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/.test(password)
      ? null : requirements;
  }
  return Object.freeze({ error, requirements });
});
