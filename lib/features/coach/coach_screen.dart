import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/session/app_session.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/status_message.dart';
import '../../coach/coach_repository.dart';
import '../../data/data_error.dart';
import '../../data/profile/user_profile.dart';
import '../../theme/evolup_theme.dart';
import '../metrics/metric_navigation.dart';
import 'coach_controller.dart';
import 'coach_messages.dart';
import 'widgets/coach_action_card.dart';
import 'widgets/coach_composer.dart';
import 'widgets/coach_message_bubble.dart';

/// Polomix, the user's analyst: a temporary chat whose answers come only
/// from Polomix, through the `coach-chat` Edge Function.
///
/// When the user reports a value ("Je viens de faire 8 tractions"), the
/// server returns a form to open: the app checks the metric against the
/// catalog, offers to track it if needed, then opens the form with a short
/// transition. Nothing is recorded before the user validates the form.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  CoachController? _controller;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _itemCount = 0;
  bool _savingConsent = false;
  // Read in build: whether this section is shown and motion is reduced.
  bool _visible = true;
  bool _reduceMotion = false;

  CoachController get _chat => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= CoachController(SessionScope.of(context).coach)
      ..addListener(_onChatChanged);
  }

  int get _currentItemCount =>
      _chat.messages.length + (_chat.isSending ? 1 : 0);

  void _onChatChanged() {
    setState(() {});
    final count = _currentItemCount;
    if (count > _itemCount) _scrollToLatest();
    _itemCount = count;
    final action = _chat.pendingAction;
    if (action != null) {
      _chat.consumeAction();
      // Opens by itself only while the page is shown; otherwise the card
      // stays in the conversation with its button.
      if (_visible) {
        final delay = _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 420);
        Future.delayed(delay, () {
          if (mounted) unawaited(_openAction(action.action!));
        });
      }
    }
  }

  Future<void> _openAction(CoachAction action) async {
    final definition = SessionScope.read(
      context,
    ).metrics.activeDefinition(action.metricSlug);
    // Only an active catalog metric can be opened.
    if (definition == null) return;
    FocusScope.of(context).unfocus();
    await startEntry(
      context,
      definition,
      suggestedValue: action.suggestedValue,
      fromPolomix: true,
    );
  }

  /// The list is reversed: the latest message is at offset 0.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset == 0) return;
      if (_reduceMotion) {
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

  Future<void> _allowDataAccess() async {
    setState(() => _savingConsent = true);
    try {
      await SessionScope.read(
        context,
      ).profile.update(const ProfileChanges(coachDataAccess: true));
    } on Object catch (error) {
      if (mounted) showMessage(context, dataErrorMessage(error));
    } finally {
      if (mounted) setState(() => _savingConsent = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _item(BuildContext context, CoachMessage message) {
    final metrics = SessionScope.of(context).metrics;
    switch (message.author) {
      case CoachAuthor.action:
        final action = message.action!;
        return CoachActionCard(
          key: ValueKey(message.id),
          action: action,
          definition: metrics.activeDefinition(action.metricSlug),
          onOpen: () => unawaited(_openAction(action)),
        );
      case CoachAuthor.coach:
        final names = [
          for (final slug in message.consultedMetrics)
            if (metrics.catalog.where((d) => d.slug == slug).firstOrNull
                case final d?)
              d.name,
        ];
        return Column(
          key: ValueKey(message.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoachMessageBubble(message: message),
            if (names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 4),
                child: Text(
                  'Données consultées : ${names.join(', ')}',
                  key: Key('coach-consulted-${message.id}'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: EvolupColors.of(context).textSecondary,
                  ),
                ),
              ),
          ],
        );
      case CoachAuthor.user:
        return CoachMessageBubble(key: ValueKey(message.id), message: message);
    }
  }

  @override
  Widget build(BuildContext context) {
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final session = SessionScope.of(context);
    final messages = _chat.messages;
    final failure = _chat.failure;
    final consent = session.profile.profile.coachDataAccess;
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Polomix'),
              Text(
                'Votre analyste personnel',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  // Hidden while typing: the conversation keeps the room.
                  if (_chat.isAvailable &&
                      !consent &&
                      MediaQuery.viewInsetsOf(context).bottom == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _ConsentBanner(
                        saving: _savingConsent,
                        onAllow: () => unawaited(_allowDataAccess()),
                      ),
                    ),
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
                              return _item(
                                context,
                                messages[messages.length - 1 - index],
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

class _ConsentBanner extends StatelessWidget {
  const _ConsentBanner({required this.saving, required this.onAllow});

  final bool saving;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    return GlassCard(
      key: const Key('coach-consent'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, color: colors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Polomix ne consulte pas vos données. Autorisez-le pour '
                  'obtenir des analyses : seuls les indicateurs liés à votre '
                  'question lui sont transmis.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('coach-consent-allow'),
              onPressed: saving ? null : onAllow,
              child: const Text('Autoriser'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
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
                  available ? Icons.forum_outlined : Icons.cloud_off_outlined,
                  size: 40,
                  color: available ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  available ? 'Posez votre question' : 'Polomix indisponible',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  available
                      ? 'Interrogez Polomix sur vos données, ou dites ce que '
                            'vous venez de faire (« Je viens de faire 8 '
                            'tractions ») pour préparer la saisie. Chaque '
                            'message est traité séparément et la conversation '
                            'n’est pas conservée.'
                      : 'La connexion au serveur d’EVOLUP n’est pas '
                            'configurée : Polomix ne peut pas être joint. Vos '
                            'données restent accessibles.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (available) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Les réponses de l’IA peuvent être inexactes. Rien n’est '
                    'enregistré sans votre validation.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
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
