/// Supabase project configuration.
///
/// The anon key is designed to be embedded in client apps -- Row Level
/// Security (see backend/database/schema.sql) is what actually protects
/// data, not the anon key's secrecy. This mirrors the same project the
/// backend talks to (see repo-root .env). To build against another project,
/// such as the local stand-in in tools/local-stack, pass
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
library;

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://jicmqxfqpbtjhwhuiohq.supabase.co',
);
const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImppY21xeGZxcGJ0amh3aHVpb2hxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyNjM2MzAsImV4cCI6MjA5ODgzOTYzMH0.krhQHMzRxzD79mFKC1iIFUhQwiSBIeTeVoBm7gVfNR8',
);
