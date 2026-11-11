import 'package:flutter/material.dart';

import '../../theme/evolup_theme.dart';

enum StatusMessageKind { error, info, success }

/// Inline confirmation, information or error, announced to screen readers.
class StatusMessage extends StatelessWidget {
  const StatusMessage({
    required this.message,
    this.kind = StatusMessageKind.info,
    super.key,
  });

  final String message;
  final StatusMessageKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final color = switch (kind) {
      StatusMessageKind.error => colors.error,
      StatusMessageKind.info => colors.accent,
      StatusMessageKind.success => colors.success,
    };
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
            color: kind == StatusMessageKind.error
                ? colors.error
                : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
