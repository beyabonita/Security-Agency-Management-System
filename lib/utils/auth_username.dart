/// Username-based login for Supabase Auth (email/password uses a synthetic email).
const authEmailDomain = 'asamanion-26858.auth';

String normalizeUsername(String raw) => raw.trim().toLowerCase();

String? validateUsername(String raw) {
  final username = normalizeUsername(raw);
  if (username.length < 3) {
    return 'Username must be at least 3 characters.';
  }
  if (username.length > 32) {
    return 'Username must be 32 characters or less.';
  }
  if (!RegExp(r'^[a-z0-9._]+$').hasMatch(username)) {
    return 'Use only letters, numbers, dots, and underscores.';
  }
  return null;
}

String usernameToAuthEmail(String username) {
  return '${normalizeUsername(username)}@$authEmailDomain';
}

/// Login input: username, or legacy email if it contains @.
String resolveAuthEmail(String input) {
  final trimmed = input.trim();
  if (trimmed.contains('@')) return trimmed.toLowerCase();
  return usernameToAuthEmail(trimmed);
}

String displayLoginId(Map<String, dynamic>? data) {
  if (data == null) return '';
  final username = data['username']?.toString();
  if (username != null && username.isNotEmpty) return username;
  final email = data['email']?.toString() ?? '';
  if (email.endsWith('@$authEmailDomain')) {
    return email.split('@').first;
  }
  return email;
}
