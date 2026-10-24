import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SocialAuthProvider {
  google('Google', OAuthProvider.google),
  apple('Apple', OAuthProvider.apple);

  const SocialAuthProvider(this.label, this.oauthProvider);

  final String label;
  final OAuthProvider oauthProvider;
}

/// OAuth returns to the app through a browser redirect: on the web to the
/// page itself, on Android/iOS through the `evolup://auth-callback` link.
/// Desktop builds have no such callback.
bool get socialAuthSupportedOnThisPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Whether a provider button can start a sign-in.
enum SocialAvailability {
  /// Enabled in the Supabase project and supported here.
  available,

  /// Supabase settings are being read.
  checking,

  /// Disabled in the Supabase project.
  notConfigured,

  /// The Supabase settings could not be read (network).
  unknown,

  /// This platform has no OAuth callback.
  unsupportedPlatform,
}
