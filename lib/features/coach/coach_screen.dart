import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/status_message.dart';
import '../../coach/coach_repository.dart';
import '../../theme/evolup_theme.dart';
import 'coach_controller.dart';
import 'coach_messages.dart';
import 'widgets/coach_composer.dart';
import 'widgets/coach_message_bubble.dart';

/// Coach IA destination: a temporary chat whose answers come only from
/// Polomix, through the `coach-chat` Edge Function. No profile data is sent.
class CoachScreen extends StatefulWidget {
  const CoachScreen({required this.repository, super.key});

  /// `null` when Supabase is not configured.
  final CoachRepository? repository;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  late final CoachController _chat = CoachController(widget.repository)
    ..addListener(_onChatChanged);
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _itemCount = 0;

  int get _currentItemCount =>
      _chat.messages.length + (_chat.isSending ? 1 : 0);

  void _onChatChanged() {
    setState(() {});
    final count = _currentItemCount;
    if (count > _itemCount) _scrollToLatest();
    _itemCount = count;
  }

  /// The list is reversed: the latest message is at offset 0.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset == 0) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (!_chat.isAvailable || _chat.isSending || text.trim().isEmpty) return;
    final tooLong = text.trim().length > coachMaxMessageLength;
    unawaited(_chat.send(text));
    if (!tooLong) _input.clear();
  }

  @override
  void dispose() {
    _chat.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _chat.messages;
    final failure = _chat.failure;
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 20,
          title: const Text(
            'Coach IA',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Expanded(
                    child: messages.isEmpty && !_chat.isSending
                        ? _EmptyState(available: _chat.isAvailable)
                        : ListView.builder(
                            key: const Key('coach-messages'),
                            controller: _scroll,
                            reverse: true,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            itemCount: _currentItemCount,
                            itemBuilder: (context, index) {
                              if (_chat.isSending) {
                                if (index == 0) {
                                  return const CoachPendingBubble(
                                    key: Key('coach-pending'),
                                  );
                                }
                                index -= 1;
                              }
                              final message =
                                  messages[messages.length - 1 - index];
                              return CoachMessageBubble(
                                key: ValueKey(message.id),
                                message: message,
                              );
                            },
                          ),
                  ),
                  if (failure != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusMessage(
                            key: const Key('coach-failure'),
                            message: coachFailureMessage(failure),
                            kind: StatusMessageKind.error,
                          ),
                          if (_chat.canRetry)
                            TextButton.icon(
                              key: const Key('coach-retry'),
                              onPressed: () => unawaited(_chat.retry()),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Réessayer'),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: CoachComposer(
                      controller: _input,
                      focusNode: _focus,
                      enabled: _chat.isAvailable,
                      sending: _chat.isSending,
                      onSend: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        key: const Key('coach-empty'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available ? Icons.sms_outlined : Icons.cloud_off_outlined,
                  size: 40,
                  color: available
                      ? EvolupColors.focus
                      : EvolupColors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  available ? 'Posez votre question' : 'Coach indisponible',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  available
                      ? 'Le coach IA répond grâce au service Polomix. Chaque '
                            'message est traité séparément et la conversation '
                            'n’est pas conservée.'
                      : 'La connexion au serveur d’EVOLUP n’est pas '
                            'configurée : le coach ne peut pas être joint.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: EvolupColors.textSecondary,
                  ),
                ),
                if (available) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Les réponses de l’IA peuvent être inexactes. Ne partagez '
                    'pas d’informations sensibles.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: EvolupColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
