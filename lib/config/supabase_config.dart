/// Configuration publique fournie au lancement de l'application.
///
/// Never place a `service_role`, secret, or third-party key in this file.
/// These values are injected with `--dart-define` for the Flutter client.
abstract final class SupabaseConfig {
  static const projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured =>
      projectUrl.isNotEmpty && publishableKey.isNotEmpty;
}
