import 'package:flutter/foundation.dart';

/// Configuration publique du projet Supabase EVOLUP.
///
/// The URL and the publishable key are public by design (they ship in every
/// build; authorization relies on RLS), so the EVOLUP project is the default
/// and the app needs no launch arguments. `--dart-define` can still point a
/// build at another project. Never place a `service_role`, secret, or
/// third-party key in this file.
abstract final class SupabaseConfig {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zhvhbtqpxorhrxfgeaen.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_LGbBBjjDjQEVpF5LLN88LQ_wlLnQZPl',
  );
  static const _redirectOverride = String.fromEnvironment(
    'SUPABASE_AUTH_REDIRECT_URL',
  );

  /// Deep link declared in `AndroidManifest.xml`.
  static const mobileRedirectUrl = 'evolup://auth-callback';

  static bool get isConfigured =>
      projectUrl.isNotEmpty && publishableKey.isNotEmpty;

  /// Where Supabase sends the user back after OAuth or a password-reset link:
  /// the current page on the web, the app's deep link on Android/iOS. It must
  /// be allow-listed in Supabase (Authentication → URL Configuration).
  static String? get redirectUrl {
    if (_redirectOverride.isNotEmpty) return _redirectOverride;
    if (kIsWeb) return Uri.base.origin;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => mobileRedirectUrl,
      _ => null,
    };
  }
}
