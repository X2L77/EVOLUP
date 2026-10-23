import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_repository.dart';
import '../data/athlete_profile.dart';
import '../data/athlete_profile_repository.dart';
import '../data/preferences_store.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/password_recovery_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../theme/app_theme.dart';

class EvolupApp extends StatelessWidget {
  const EvolupApp({
    required this.themeController,
    required this.authRepository,
    required this.profileRepository,
    this.initializationError,
    super.key,
  });

  final ThemeController themeController;
  final AuthRepository? authRepository;
  final AthleteProfileRepository? profileRepository;
  final String? initializationError;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => MaterialApp(
      title: 'EVOLUP',
      debugShowCheckedModeBanner: false,
      theme: buildEvolupTheme(themeController.value.copyWith(isDark: false)),
      darkTheme: buildEvolupTheme(themeController.value.copyWith(isDark: true)),
      themeMode: themeController.value.isDark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: AppGate(
        themeController: themeController,
        authRepository: authRepository,
        profileRepository: profileRepository,
        initializationError: initializationError,
      ),
    ),
  );
}

class AppGate extends StatefulWidget {
  const AppGate({
    required this.themeController,
    required this.authRepository,
    required this.profileRepository,
    this.initializationError,
    super.key,
  });

  final ThemeController themeController;
  final AuthRepository? authRepository;
  final AthleteProfileRepository? profileRepository;
  final String? initializationError;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<void>? _passwordRecoverySubscription;
  String? _userId;
  AthleteProfile? _profile;
  Object? _loadError;
  bool _loading = true;
  bool _editingProfile = false;
  bool _passwordRecovery = false;

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
          _loadError = error;
          _loading = false;
        });
      },
    );
    _passwordRecoverySubscription = auth.passwordRecoveryEvents.listen((_) {
      if (mounted) setState(() => _passwordRecovery = true);
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
    });
    if (userId != null) await _loadProfile(userId);
  }

  Future<void> _loadProfile(String userId) async {
    final repository = widget.profileRepository;
    if (repository == null) return;
    try {
      final profile = await repository.load(userId);
      if (!mounted || userId != _userId) return;
      final resolved =
          profile ??
          AthleteProfile(
            palette: widget.themeController.value.palette,
            isDark: widget.themeController.value.isDark,
          );
      if (profile != null) {
        await widget.themeController.update(profile.themePreferences);
      }
      if (!mounted || userId != _userId) return;
      setState(() {
        _profile = resolved;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || userId != _userId) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile(AthleteProfile profile) async {
    final userId = _userId;
    final repository = widget.profileRepository;
    if (userId == null || repository == null) {
      throw StateError('Aucune session Supabase active.');
    }
    await repository.save(userId, profile);
    await widget.themeController.update(profile.themePreferences);
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _saveTheme(ThemePreferences preferences) async {
    await widget.themeController.update(preferences);
    final profile = _profile;
    final userId = _userId;
    final repository = widget.profileRepository;
    if (profile != null && userId != null && repository != null) {
      final updated = AthleteProfile.fromMap({
        ...profile.toMap(),
        'preferred_palette': preferences.palette.name,
        'is_dark_mode': preferences.isDark,
      });
      await repository.save(userId, updated);
      if (mounted) setState(() => _profile = updated);
    }
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return _ErrorScreen(
        message: _loadError is Exception
            ? 'Impossible de charger votre profil. Vérifiez votre connexion '
                  'et les migrations Supabase, puis réessayez.'
            : 'Une erreur inattendue est survenue. Réessayez.',
        onRetry: () {
          final userId = _userId;
          if (userId != null) unawaited(_loadProfile(userId));
        },
        onSignOut: auth == null ? null : () => unawaited(_signOut()),
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
    if (_userId == null) {
      return SignInScreen(authRepository: auth);
    }
    final profile = _profile;
    if (profile == null) {
      return _ErrorScreen(
        message: 'Votre profil n’a pas pu être chargé.',
        onRetry: () => unawaited(_loadProfile(_userId!)),
        onSignOut: () => unawaited(_signOut()),
      );
    }
    if (!profile.onboardingCompleted ||
        !profile.isComplete ||
        _editingProfile) {
      return OnboardingScreen(
        key: ValueKey(
          'onboarding-$_userId-${_editingProfile ? 'edit' : 'new'}',
        ),
        initialProfile: profile,
        themeController: widget.themeController,
        onSave: _saveProfile,
        onSignOut: _signOut,
      );
    }
    return HomeScreen(
      profile: profile,
      themeController: widget.themeController,
      onEditProfile: () => setState(() => _editingProfile = true),
      onThemeChanged: _saveTheme,
      onSignOut: _signOut,
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
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 44),
                const SizedBox(height: 20),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Réessayer'),
                ),
                if (onSignOut != null)
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
  );
}
