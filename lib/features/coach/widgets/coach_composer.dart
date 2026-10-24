import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../coach/coach_repository.dart';
import '../../../theme/evolup_theme.dart';

/// Message field and send button.
///
/// With a hardware keyboard (web, desktop) Enter sends and Shift+Enter adds
/// a line; on Android/iOS the keyboard's send key sends.
class CoachComposer extends StatelessWidget {
  const CoachComposer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.sending,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// `false` when the coach cannot be reached at all.
  final bool enabled;

  /// A message is being answered: sending another one is disabled.
  final bool sending;
  final VoidCallback onSend;

  static bool get _enterSends =>
      kIsWeb ||
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enterSends ||
        event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final length = value.text.trim().length;
          final canSend = enabled && !sending && length > 0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (length > coachMaxMessageLength * 0.9)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, right: 60),
                  child: Text(
                    '$length / $coachMaxMessageLength',
                    key: const Key('coach-counter'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: length > coachMaxMessageLength
                          ? EvolupColors.error
                          : EvolupColors.textSecondary,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: _onKey,
                      child: TextField(
                        key: const Key('coach-input'),
                        controller: controller,
                        focusNode: focusNode,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: _enterSends
                            ? TextInputAction.newline
                            : TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        decoration: InputDecoration(
                          hintText: enabled
                              ? 'Écrire au coach…'
                              : 'Envoi impossible',
                          border: _border(EvolupColors.fieldBorder),
                          enabledBorder: _border(EvolupColors.fieldBorder),
                          disabledBorder: _border(EvolupColors.fieldBorder),
                          focusedBorder: _border(EvolupColors.focus, 1.5),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    key: const Key('coach-send'),
                    tooltip: 'Envoyer',
                    onPressed: canSend ? onSend : null,
                    style: IconButton.styleFrom(
                      backgroundColor: EvolupColors.primaryButton,
                      foregroundColor: EvolupColors.primaryButtonText,
                      disabledBackgroundColor: EvolupColors.fieldFill,
                      disabledForegroundColor: EvolupColors.textSecondary,
                      fixedSize: const Size.square(50),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          );
        },
      );

  static OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: color, width: width),
      );
}
