import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_error.dart';
import '../auth/auth_repository.dart';
import '../coach/coach_repository.dart';
import '../data/athlete_profile.dart';
import '../data/athlete_profile_repository.dart';
import '../data/questionnaire_draft_store.dart';
import '../features/auth/password_recovery_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/questionnaire_screen.dart';
import '../theme/evolup_theme.dart';
import 'shell/app_shell.dart';
import 'widgets/evolup_background.dart';
import 'widgets/glass_card.dart';

class EvolupApp extends StatelessWidget {
  const EvolupApp({
    required this.authRepository,
    required this.profileRepository,
    required this.draftStore,
    this.coachRepository,
    this.initializationError,
    super.key,
  });

  final AuthRepository? authRepository;
  final AthleteProfileRepository? profileRepository;
  final QuestionnaireDraftStore draftStore;
  final CoachRepository? coachRepository;
  final String? initializationError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EVOLUP',
    debugShowCheckedModeBanner: false,
    theme: buildEvolupBrandTheme(),
    home: AppGate(
      authRepository: authRepository,
      profileRepository: profileRepository,
      draftStore: draftStore,
      coachRepository: coachRepository,
      initializationError: initializationError,
    ),
  );
}

/// Chooses the screen: password recovery → sign-in → questionnaire (no
/// profile yet, or editing) → [AppShell] (home and the other main
/// destinations). A session alone never means a completed profile: the
/// profile row is loaded for every signed-in user.
class AppGate extends StatefulWidget {
  const AppGate({
    required this.authRepository,
    required this.profileRepository,
    required this.draftStore,
    this.coachRepository,
    this.initializationError,
    super.key,
  });

  final AuthRepository? authRepository;
  final AthleteProfileRepository? profileRepository;
  final QuestionnaireDraftStore draftStore;
  final CoachRepository? coachRepository;
  final String? initializationError;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<void>? _passwordRecoverySubscription;
  StreamSubscription<AuthFailure>? _authFailureSubscription;
  String? _userId;
  AthleteProfile? _profile;
  Object? _loadError;
  bool _loading = true;
  bool _editingProfile = false;
  bool _passwordRecovery = false;
  AuthFailure? _authFailure;

  @override
  void initState() {
    super.initState();
    final auth = widget.authRepository;
    if (auth == null) {
      _loading = false;
      return;
    }
    _authSubscription = auth.userIdChanges.listen(
      _onUserChanged,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _authFailure = classifyAuthError(error);
          _loading = false;
        });
      },
    );
    _passwordRecoverySubscription = auth.passwordRecoveryEvents.listen((_) {
      if (mounted) setState(() => _passwordRecovery = true);
    });
    _authFailureSubscription = auth.authFailures.listen((failure) {
      if (mounted) setState(() => _authFailure = failure);
    });
    _userId = auth.currentUserId;
    if (_userId == null) {
      _loading = false;
    } else {
      unawaited(_loadProfile(_userId!));
    }
  }

  Future<void> _onUserChanged(String? userId) async {
    if (!mounted || userId == _userId) return;
    setState(() {
      _userId = userId;
      _profile = null;
      _loadError = null;
      _editingProfile = false;
      _loading = userId != null;
      if (userId != null) _authFailure = null;
    });
    if (userId != null) await _loadProfile(userId);
  }

  Future<void> _loadProfile(String userId) async {
    final repository = widget.profileRepository;
    if (repository == null) return;
    try {
      final profile = await repository.loadCurrent();
      if (!mounted || userId != _userId) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || userId != _userId) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  /// Saves the questionnaire. The screen stays on the confirmation until the
  /// user continues ([_onQuestionnaireFinished]).
  Future<void> _saveProfile(AthleteProfile profile) async {
    final userId = _userId;
    final repository = widget.profileRepository;
    if (userId == null || repository == null) {
      throw StateError('Aucune session Supabase active.');
    }
    await repository.saveCurrent(profile);
    try {
      await widget.draftStore.clear(userId);
    } on Object {
      // The profile is saved; a stale local draft is ignored once it exists.
    }
  }

  void _onQuestionnaireFinished(AthleteProfile profile) {
    setState(() {
      _profile = profile;
      _editingProfile = false;
    });
  }

  Future<void> _signOut() async {
    final auth = widget.authRepository;
    if (auth == null) throw StateError('Supabase n’est pas configuré.');
    await auth.signOut();
  }

  Future<void> _updatePassword(String password) async {
    final auth = widget.authRepository;
    if (auth == null) throw StateError('Supabase n’est pas configuré.');
    await auth.updatePassword(password);
    if (mounted) setState(() => _passwordRecovery = false);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _passwordRecoverySubscription?.cancel();
    _authFailureSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authRepository;
    final profileRepository = widget.profileRepository;
    if (_passwordRecovery && auth != null) {
      return PasswordRecoveryScreen(onUpdatePassword: _updatePassword);
    }
    if (_loading) {
      return const EvolupBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (auth == null || profileRepository == null) {
      return SignInScreen(
        authRepository: null,
        configurationMessage:
            widget.initializationError ??
            'Pour activer la connexion, configurez SUPABASE_URL et '
                'SUPABASE_PUBLISHABLE_KEY au lancement.',
      );
    }
    final userId = _userId;
    if (userId == null) {
      return SignInScreen(authRepository: auth, initialFailure: _authFailure);
    }
    if (_loadError != null) {
      return _ErrorScreen(
        message: _loadError is Exception
            ? 'Impossible de charger votre profil. Vérifiez votre connexion, '
                  'puis réessayez.'
            : 'Une erreur inattendue est survenue. Réessayez.',
        onRetry: () {
          setState(() {
            _loading = true;
            _loadError = null;
          });
          unawaited(_loadProfile(userId));
        },
        onSignOut: () => unawaited(_signOut()),
      );
    }
    final profile = _profile;
    if (profile == null || _editingProfile) {
      return QuestionnaireScreen(
        key: ValueKey(
          'questionnaire-$userId-${_editingProfile ? 'edit' : 'new'}',
        ),
        userId: userId,
        draftStore: widget.draftStore,
        initialProfile: _editingProfile ? profile : null,
        onSave: _saveProfile,
        onFinished: _onQuestionnaireFinished,
        onSignOut: _signOut,
        onCancel: _editingProfile
            ? () => setState(() => _editingProfile = false)
            : null,
      );
    }
    return AppShell(
      home: HomeScreen(
        profile: profile,
        onEditProfile: () => setState(() => _editingProfile = true),
        onSignOut: _signOut,
      ),
      coach: CoachScreen(repository: widget.coachRepository),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => EvolupBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 44,
                      color: EvolupColors.textSecondary,
                    ),
                    const SizedBox(height: 20),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Réessayer'),
                    ),
                    TextButton(
                      onPressed: onSignOut,
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
