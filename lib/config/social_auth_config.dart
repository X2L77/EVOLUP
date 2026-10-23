enum SocialAuthProvider {
  google('Google'),
  apple('Apple');

  const SocialAuthProvider(this.label);

  final String label;
}

/// Social providers whose configuration and real behaviour have been verified.
///
/// Keep a provider out of this set until it is enabled in Supabase and has
/// been tested end to end on each target platform. Its button then stays
/// visible but explains that it is not configured.
abstract final class SocialAuthConfig {
  static const Set<SocialAuthProvider> verified = {};

  static bool isAvailable(SocialAuthProvider provider) =>
      verified.contains(provider);
}
