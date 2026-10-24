import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/widgets/button_spinner.dart';
import '../../../theme/evolup_theme.dart';
import '../coach_controller.dart';

/// One message of the conversation: the user's on the right, the coach's
/// (selectable, announced to screen readers) on the left.
class CoachMessageBubble extends StatelessWidget {
  const CoachMessageBubble({required this.message, super.key});

  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.author == CoachAuthor.user;
    final style = Theme.of(context).textTheme.bodyLarge;
    return _Bubble(
      fromUser: fromUser,
      child: Semantics(
        container: true,
        liveRegion: !fromUser,
        label: fromUser ? 'Vous' : 'Coach IA',
        child: fromUser
            ? Text(message.text, style: style)
            : SelectableText(message.text, style: style),
      ),
    );
  }
}

/// Shown while the server is waiting for the coach's reply. It contains no
/// text from the coach.
class CoachPendingBubble extends StatelessWidget {
  const CoachPendingBubble({super.key});

  @override
  Widget build(BuildContext context) => _Bubble(
    fromUser: false,
    child: Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ButtonSpinner(color: EvolupColors.focus),
          const SizedBox(width: 10),
          Text(
            'Réponse en cours…',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: EvolupColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.child});

  final bool fromUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(18);
    const tail = Radius.circular(6);
    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.82, 560.0);
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fromUser
                  ? EvolupColors.navSelected
                  : EvolupColors.glassFillTop,
              border: Border.all(
                color: fromUser
                    ? EvolupColors.focus.withValues(alpha: 0.35)
                    : EvolupColors.glassBorder,
              ),
              borderRadius: BorderRadius.only(
                topLeft: round,
                topRight: round,
                bottomLeft: fromUser ? round : tail,
                bottomRight: fromUser ? tail : round,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
