import 'package:flutter/material.dart';

import '../../../theme/auth_theme.dart';

enum AuthMessageKind { error, info }

class AuthMessage extends StatelessWidget {
  const AuthMessage({
    required this.message,
    this.kind = AuthMessageKind.info,
    super.key,
  });

  final String message;
  final AuthMessageKind kind;

  @override
  Widget build(BuildContext context) {
    final color = kind == AuthMessageKind.error
        ? AuthColors.error
        : AuthColors.success;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: kind == AuthMessageKind.error
                ? AuthColors.error
                : AuthColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
