import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_error.dart';
import '../../theme/auth_theme.dart';
import 'auth_messages.dart';
import 'email_auth_controller.dart';
import 'widgets/auth_message.dart';
import 'widgets/button_spinner.dart';

/// Second step of account creation: the code sent by email. The code is
/// checked by Supabase, which only opens a session when it is valid.
class EmailCodeStep extends StatefulWidget {
  const EmailCodeStep({required this.controller, super.key});

  final EmailAuthController controller;

  @override
  State<EmailCodeStep> createState() => _EmailCodeStepState();
}

class _EmailCodeStepState extends State<EmailCodeStep> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await widget.controller.verifyCode(_code.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final failure = controller.failure;
    final notice = controller.notice;
    final secondsLeft = controller.resendSecondsLeft;
    final verifying = controller.busy == EmailAuthAction.verifyCode;
    final resending = controller.busy == EmailAuthAction.resendCode;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vérifiez votre adresse e-mail',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            controller.pendingEmail ?? '',
            key: const Key('auth-code-email'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AuthColors.textSecondary,
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 16),
            AuthMessage(message: authNoticeMessage(notice)),
          ],
          if (failure != null) ...[
            const SizedBox(height: 16),
            AuthMessage(
              message: authFailureMessage(failure),
              kind: AuthMessageKind.error,
            ),
          ],
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('auth-code'),
            controller: _code,
            readOnly: controller.isBusy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            onChanged: (_) {
              if (failure == AuthFailure.invalidCode) {
                controller.clearMessages();
              }
            },
            onFieldSubmitted: (_) => _verify(),
            decoration: const InputDecoration(
              labelText: 'Code de vérification',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            validator: (value) => isValidCode(value?.trim() ?? '')
                ? null
                : 'Saisissez le code reçu par e-mail.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('auth-verify'),
            onPressed: controller.isBusy ? null : _verify,
            child: verifying ? const ButtonSpinner() : const Text('Valider'),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('auth-resend'),
            onPressed: controller.isBusy || secondsLeft > 0
                ? null
                : controller.resendCode,
            child: resending
                ? const ButtonSpinner(color: AuthColors.textPrimary)
                : Text(
                    secondsLeft > 0
                        ? 'Renvoyer le code ($secondsLeft s)'
                        : 'Renvoyer le code',
                  ),
          ),
          TextButton(
            key: const Key('auth-change-email'),
            onPressed: controller.isBusy ? null : controller.changeEmail,
            child: const Text('Modifier l’adresse'),
          ),
        ],
      ),
    );
  }
}
