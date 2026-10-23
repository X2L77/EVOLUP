import 'package:flutter/material.dart';

import '../../app/evolup_logo.dart';
import '../../auth/auth_error.dart';
import '../../auth/auth_repository.dart';
import '../../config/social_auth_config.dart';
import '../../theme/auth_theme.dart';
import 'auth_messages.dart';
import 'email_auth_controller.dart';
import 'email_code_step.dart';
import 'widgets/auth_background.dart';
import 'widgets/auth_message.dart';
import 'widgets/button_spinner.dart';
import 'widgets/glass_card.dart';
import 'widgets/social_auth_buttons.dart';

/// First-launch authentication screen (build guide §1).
///
/// « Continuer » only signs in. « Créer un compte » is a separate, explicit
/// action that leads to an email code verified by Supabase.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.authRepository,
    this.configurationMessage,
    super.key,
  });

  final AuthRepository? authRepository;
  final String? configurationMessage;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final _controller = EmailAuthController(widget.authRepository);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final stepDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return Theme(
      data: buildAuthTheme(),
      child: Builder(
        builder: (context) => AuthBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 56,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _Entrance(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 450),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: EvolupLogo(),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Login',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              GlassCard(
                                child: ListenableBuilder(
                                  listenable: _controller,
                                  builder: (context, _) => AnimatedSize(
                                    duration: stepDuration,
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    child: AnimatedSwitcher(
                                      duration: stepDuration,
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      child:
                                          _controller.step == EmailAuthStep.code
                                          ? EmailCodeStep(
                                              key: const ValueKey('code-step'),
                                              controller: _controller,
                                            )
                                          : _CredentialsStep(
                                              key: const ValueKey(
                                                'credentials-step',
                                              ),
                                              controller: _controller,
                                              configurationMessage:
                                                  widget.configurationMessage,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Email, password, « Continuer », « Créer un compte », then social buttons.
class _CredentialsStep extends StatefulWidget {
  const _CredentialsStep({
    required this.controller,
    required this.configurationMessage,
    super.key,
  });

  final EmailAuthController controller;
  final String? configurationMessage;

  @override
  State<_CredentialsStep> createState() => _CredentialsStepState();
}

class _CredentialsStepState extends State<_CredentialsStep> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  SocialAuthProvider? _unavailableProvider;

  /// Action whose rules the validators currently apply.
  EmailAuthAction _validating = EmailAuthAction.signIn;

  @override
  void initState() {
    super.initState();
    _email.text = widget.controller.pendingEmail ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validateFor(EmailAuthAction action) {
    FocusScope.of(context).unfocus();
    setState(() {
      _validating = action;
      _unavailableProvider = null;
    });
    return _formKey.currentState!.validate();
  }

  Future<void> _signIn() async {
    if (!_validateFor(EmailAuthAction.signIn)) return;
    await widget.controller.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  Future<void> _signUp() async {
    if (!_validateFor(EmailAuthAction.signUp)) return;
    await widget.controller.signUp(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  Future<void> _resetPassword() async {
    if (!_validateFor(EmailAuthAction.resetPassword)) return;
    await widget.controller.sendPasswordReset(_email.text.trim());
  }

  void _onFieldChanged(String _) {
    widget.controller.clearMessages();
    if (_unavailableProvider != null) {
      setState(() => _unavailableProvider = null);
    }
  }

  void _showUnavailable(SocialAuthProvider provider) {
    widget.controller.clearMessages();
    setState(() => _unavailableProvider = provider);
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    return switch (_validating) {
      EmailAuthAction.resetPassword => null,
      EmailAuthAction.signUp when password.length < minimumPasswordLength =>
        '$minimumPasswordLength caractères minimum.',
      _ when password.isEmpty => 'Saisissez votre mot de passe.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final busy = controller.busy;
    final failure = controller.failure;
    final notice = controller.notice;
    final configurationMessage = widget.configurationMessage;
    final unavailable = _unavailableProvider;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (configurationMessage != null) ...[
            AuthMessage(
              message: configurationMessage,
              kind: AuthMessageKind.error,
            ),
            const SizedBox(height: 16),
          ],
          if (failure != null &&
              !(failure == AuthFailure.notConfigured &&
                  configurationMessage != null)) ...[
            AuthMessage(
              key: const Key('auth-failure'),
              message: authFailureMessage(failure),
              kind: AuthMessageKind.error,
            ),
            if (failure == AuthFailure.emailNotConfirmed)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('auth-request-code'),
                  onPressed: busy == null ? controller.requestCode : null,
                  child: busy == EmailAuthAction.requestCode
                      ? const ButtonSpinner(color: AuthColors.textPrimary)
                      : const Text('Recevoir un code'),
                ),
              ),
            const SizedBox(height: 16),
          ],
          if (notice != null) ...[
            AuthMessage(message: authNoticeMessage(notice)),
            const SizedBox(height: 16),
          ],
          if (unavailable != null) ...[
            AuthMessage(
              key: const Key('auth-social-unavailable'),
              message:
                  'La connexion avec ${unavailable.label} n’est pas encore '
                  'configurée. Utilisez votre adresse e-mail.',
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('auth-email'),
            controller: _email,
            readOnly: busy != null,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            onChanged: _onFieldChanged,
            decoration: const InputDecoration(
              labelText: 'Adresse e-mail',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) => isValidEmail(value?.trim() ?? '')
                ? null
                : 'Saisissez une adresse e-mail valide.',
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('auth-password'),
            controller: _password,
            readOnly: busy != null,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            onChanged: _onFieldChanged,
            onFieldSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                key: const Key('auth-password-visibility'),
                tooltip: _obscurePassword
                    ? 'Afficher le mot de passe'
                    : 'Masquer le mot de passe',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: _validatePassword,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('auth-forgot'),
              onPressed: busy == null ? _resetPassword : null,
              child: busy == EmailAuthAction.resetPassword
                  ? const ButtonSpinner(color: AuthColors.textPrimary)
                  : const Text('Mot de passe oublié ?'),
            ),
          ),
          const SizedBox(height: 4),
          FilledButton(
            key: const Key('auth-submit'),
            onPressed: busy == null ? _signIn : null,
            child: busy == EmailAuthAction.signIn
                ? const ButtonSpinner()
                : const Text('Continuer'),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('auth-create'),
            onPressed: busy == null ? _signUp : null,
            child: busy == EmailAuthAction.signUp
                ? const ButtonSpinner(color: AuthColors.textPrimary)
                : const Text('Créer un compte'),
          ),
          const SizedBox(height: 14),
          const Divider(color: AuthColors.glassBorder, height: 1),
          const SizedBox(height: 18),
          SocialAuthButtons(onUnavailable: _showUnavailable),
        ],
      ),
    );
  }
}

/// Discreet fade and rise when the screen first appears.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
