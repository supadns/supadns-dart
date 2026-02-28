import 'package:supabase/supabase.dart';
import 'connection_manager.dart';
import 'doh_resolver.dart';

/// Drop-in replacement for SupabaseClient with DoH fallback.
///
/// ```dart
/// import 'package:supadns/supadns.dart';
///
/// final supabase = createSmartClient(
///   'https://myproject.supabase.co',
///   'your-anon-key',
/// );
/// ```
SupabaseClient createSmartClient(
  String supabaseUrl,
  String supabaseKey, {
  Map<String, String>? headers,
}) {
  return SupabaseClient(
    supabaseUrl,
    supabaseKey,
    headers: headers,
  );
}
