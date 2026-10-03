/// Public client configuration. Access is controlled by Supabase Row Level
/// Security; never put a service-role key in a Flutter app.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://uqtupmpofjqrnefgrexm.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_WhymBQujSZgXctoTe0hwCA_Q4DRCPcw',
  );
}
