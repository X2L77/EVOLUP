import 'package:flutter/material.dart';

import '../../theme/evolup_theme.dart';
import 'glass_card.dart';

/// Page-level loading indicator.
class LoadingView extends StatelessWidget {
  const LoadingView({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label ?? 'Chargement',
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: CircularProgressIndicator(
          color: EvolupColors.of(context).accent,
        ),
      ),
    ),
  );
}

/// Explains why there is nothing to show (no data, not enough data…) and
/// optionally offers the next step. Never shows sample content.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Smaller version without its own card, used inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 30 : 40, color: colors.accent),
        SizedBox(height: compact ? 10 : 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: (compact ? textTheme.titleMedium : textTheme.titleLarge)
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: content,
      );
    }
    return GlassCard(child: content);
  }
}

/// Error with a retry action, for a section or a whole page.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 36,
          color: EvolupColors.of(context).textSecondary,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Réessayer'),
        ),
      ],
    ),
  );
}

/// Title of a section of a page, with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Standard scrolling page body: centered, width-limited, padded above the
/// floating navigation bar.
class PageBody extends StatelessWidget {
  const PageBody({required this.children, this.maxWidth = 720, super.key});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      // Pull-to-refresh also works when the content is short.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}
