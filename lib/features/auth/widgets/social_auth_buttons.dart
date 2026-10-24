import 'package:flutter/material.dart';

import '../../../app/widgets/button_spinner.dart';
import '../../../auth/social_auth_provider.dart';
import '../../../theme/evolup_theme.dart';

/// Google and Apple buttons (build guide §1.5).
///
/// A provider only starts a sign-in when it is enabled in the Supabase
/// project and this platform can receive the OAuth callback. Otherwise the
/// button stays visible, says why, and explains it when pressed.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    required this.availabilityOf,
    required this.loadingProvider,
    required this.onPressed,
    super.key,
  });

  final SocialAvailability Function(SocialAuthProvider provider) availabilityOf;
  final SocialAuthProvider? loadingProvider;
  final ValueChanged<SocialAuthProvider> onPressed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final provider in SocialAuthProvider.values) ...[
        if (provider != SocialAuthProvider.values.first)
          const SizedBox(height: 10),
        _SocialButton(
          provider: provider,
          availability: availabilityOf(provider),
          loading: loadingProvider == provider,
          onPressed: () => onPressed(provider),
        ),
      ],
    ],
  );
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.provider,
    required this.availability,
    required this.loading,
    required this.onPressed,
  });

  final SocialAuthProvider provider;
  final SocialAvailability availability;
  final bool loading;
  final VoidCallback onPressed;

  String? get _status => switch (availability) {
    SocialAvailability.available => null,
    SocialAvailability.checking => 'Vérification…',
    SocialAvailability.notConfigured => 'Non configuré',
    SocialAvailability.unknown => 'Indisponible',
    SocialAvailability.unsupportedPlatform => 'Non disponible ici',
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final textTheme = Theme.of(context).textTheme;
    final label = 'Continuer avec ${provider.label}';
    return Semantics(
      button: true,
      label: status == null ? label : '$label, ${status.toLowerCase()}',
      excludeSemantics: true,
      child: OutlinedButton(
        key: Key('auth-${provider.name}'),
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          backgroundColor: EvolupColors.fieldFill,
          foregroundColor: EvolupColors.textPrimary,
          side: const BorderSide(color: EvolupColors.glassBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const ButtonSpinner(color: EvolupColors.textPrimary)
            : Opacity(
                opacity: status == null ? 1 : 0.6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ProviderMark(provider),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, overflow: TextOverflow.ellipsis),
                          if (status != null)
                            Text(
                              status,
                              style: textTheme.labelSmall?.copyWith(
                                color: EvolupColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark(this.provider);

  final SocialAuthProvider provider;

  @override
  Widget build(BuildContext context) => switch (provider) {
    SocialAuthProvider.apple => const Icon(Icons.apple, size: 20),
    SocialAuthProvider.google => const Text(
      'G',
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
    ),
  };
}
