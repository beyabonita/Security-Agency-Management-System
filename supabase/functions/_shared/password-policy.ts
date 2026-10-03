export const PASSWORD_REQUIREMENTS =
  "Use at least 8 characters with at least one uppercase letter, one lowercase letter, one number, and one symbol.";

/** Validate new passwords without trimming or changing the supplied secret. */
export function passwordError(password: string): string | null {
  const length = Array.from(password).length;
  if (new TextEncoder().encode(password).length > 72) {
    return "Password is too long. Use at most 72 bytes (72 characters for standard letters, numbers, and symbols).";
  }
  return length >= 8 && /[A-Z]/.test(password) &&
      /[a-z]/.test(password) && /[0-9]/.test(password) &&
      /[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/.test(password)
    ? null
    : PASSWORD_REQUIREMENTS;
}
