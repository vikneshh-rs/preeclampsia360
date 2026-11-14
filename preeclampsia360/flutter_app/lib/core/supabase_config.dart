/// Client-safe Supabase configuration.
/// The publishable key is designed to be included in client applications.
/// Database access must still be protected by Row Level Security (RLS).
class SupabaseConfig {
  static const String url = 'https://ymkqatqxuohrwlfajpdc.supabase.co';
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_FNAATy1IbIUOzPwM_-u5vw_whbpz165',
  );
}
