import 'package:flutter/material.dart';

import '../../../config/social_auth_config.dart';
import '../../../theme/auth_theme.dart';

/// Google and Apple buttons (build guide §1.5).
///
/// No provider is wired yet: an unverified provider never starts a sign-in.
/// Its button stays visible, is labelled « Non configuré » and explains the
/// situation when pressed.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({required this.onUnavailable, super.key});

  final ValueChanged<SocialAuthProvider> onUnavailable;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final provider in SocialAuthProvider.values) ...[
        if (provider != SocialAuthProvider.values.first)
          const SizedBox(height: 10),
        _SocialButton(
          provider: provider,
          onPressed: () => onUnavailable(provider),
        ),
      ],
    ],
  );
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.provider, required this.onPressed});

  final SocialAuthProvider provider;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final available = SocialAuthConfig.isAvailable(provider);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: available
          ? 'Continuer avec ${provider.label}'
          : 'Continuer avec ${provider.label}, non configuré',
      excludeSemantics: true,
      child: OutlinedButton(
        key: Key('auth-${provider.name}'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          backgroundColor: AuthColors.fieldFill,
          foregroundColor: AuthColors.textPrimary,
          side: const BorderSide(color: AuthColors.glassBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Opacity(
          opacity: available ? 1 : 0.6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProviderMark(provider),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Continuer avec ${provider.label}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!available)
                      Text(
                        'Non configuré',
                        style: textTheme.labelSmall?.copyWith(
                          color: AuthColors.textSecondary,
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
