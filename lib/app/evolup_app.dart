import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../auth/auth_error.dart';
import '../auth/auth_repository.dart';
import '../coach/coach_repository.dart';
import '../data/data_error.dart';
import '../data/device_timezone.dart';
import '../data/metrics/metrics_repository.dart';
import '../data/profile/profile_repository.dart';
import '../features/auth/password_recovery_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../theme/evolup_theme.dart';
import 'session/app_session.dart';
import 'session/local_day_clock.dart';
import 'session/metrics_controller.dart';
import 'shell/app_shell.dart';
import 'widgets/evolup_background.dart';
import 'widgets/glass_card.dart';
import 'widgets/state_views.dart';

/// Repositories of the signed-in part of the app. `null` in [EvolupApp]
/// means Supabase is not configured.
class SessionServices {
  const SessionServices({
    required this.profiles,
    required this.metrics,
    this.coach,
    this.deviceTimezone = const PlatformDeviceTimezone(),
    this.now = DateTime.now,
  });

  final ProfileRepository profiles;
  final MetricsRepository metrics;
  final CoachRepository? coach;
  final DeviceTimezone deviceTimezone;

  /// The device's clock (tests replace it).
  final DateTime Function() now;
}

class EvolupApp extends StatefulWidget {
  const EvolupApp({
    required this.authRepository,
    required this.services,
    this.initializationError,
    super.key,
  });

  final AuthRepository? authRepository;
  final SessionServices? services;
  final String? initializationError;

  @override
  State<EvolupApp> createState() => _EvolupAppState();
}

class _EvolupAppState extends State<EvolupApp> {
  final _session = ValueNotifier<SignedInSession?>(null);
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _session.value?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _session,
    builder: (context, session, _) => ListenableBuilder(
      listenable: session?.profile ?? _session,
      builder: (context, _) {
        // Signed out: the fixed EVOLUP identity; signed in: the user's
        // palette and mode.
        final colors = session == null
            ? EvolupColors.brand
            : EvolupColors.resolve(session.profile.profile.appearance);
        return MaterialApp(
          title: 'EVOLUP',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: buildEvolupTheme(colors),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) =>
              SessionScope(session: session, child: child!),
          home: AppGate(
            authRepository: widget.authRepository,
            services: widget.services,
            initializationError: widget.initializationError,
            onSession: (value) {
              final previous = _session.value;
              if (identical(previous, value)) return;
              _navigatorKey.currentState?.popUntil((route) => route.isFirst);
              _session.value = value;
              // Disposed once the pages that listen to it are gone.
              if (previous != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => previous.dispose(),
                );
              }
            },
          ),
        );
      },
    ),
  );
}

/// Chooses the screen: password recovery → sign-in → loading of the
/// profile and the catalog → [AppShell]. The profile is created on the
/// first sign-in (no questionnaire).
class AppGate extends StatefulWidget {
  const AppGate({
    required this.authRepository,
    required this.services,
    required this.onSession,
    this.initializationError,
    super.key,
  });

  final AuthRepository? authRepository;
  final SessionServices? services;
  final String? initializationError;

  /// Publishes the signed-in session (or `null` after sign-out) above the
  /// navigator.
  final ValueChanged<SignedInSession?> onSession;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<void>? _passwordRecoverySubscription;
  StreamSubscription<AuthFailure>? _authFailureSubscription;
  String? _userId;
  SignedInSession? _session;
  Object? _loadError;
  bool _loading = true;
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
      unawaited(_openSession(_userId!));
    }
  }

  void _publish(SignedInSession? session) {
    _session = session;
    widget.onSession(session);
  }

  Future<void> _onUserChanged(String? userId) async {
    if (!mounted || userId == _userId) return;
    setState(() {
      _userId = userId;
      _loadError = null;
      _loading = userId != null;
      if (userId != null) _authFailure = null;
    });
    _publish(null);
    if (userId != null) await _openSession(userId);
  }

  Future<void> _openSession(String userId) async {
    final services = widget.services;
    final auth = widget.authRepository;
    if (services == null || auth == null) return;
    MetricsController? metrics;
    LocalDayClock? day;
    try {
      final timezone = await services.deviceTimezone.current() ?? 'UTC';
      final profile = await services.profiles.loadOrCreate(timezone: timezone);
      final clock = day = LocalDayClock(now: services.now);
      metrics = MetricsController(
        services.metrics,
        now: services.now,
        today: () => clock.today,
      );
      await metrics.load();
      if (!mounted || userId != _userId) {
        metrics.dispose();
        clock.dispose();
        return;
      }
      clock.watch();
      _publish(
        SignedInSession(
          userId: userId,
          email: auth.currentEmail,
          profile: ProfileController(services.profiles, profile),
          metrics: metrics,
          coach: services.coach,
          deviceTimezone: services.deviceTimezone,
          day: clock,
          signOut: _signOut,
        ),
      );
      setState(() => _loading = false);
    } on Object catch (error) {
      metrics?.dispose();
      day?.dispose();
      if (!mounted || userId != _userId) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
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
    _authFailureSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authRepository;
    if (_passwordRecovery && auth != null) {
      return PasswordRecoveryScreen(onUpdatePassword: _updatePassword);
    }
    if (_loading) {
      return const EvolupBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LoadingView(label: 'Chargement de vos données'),
        ),
      );
    }
    if (auth == null || widget.services == null) {
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
    final error = _loadError;
    if (error != null || _session == null) {
      return _ErrorScreen(
        message: error == null
            ? dataFailureMessage(DataFailure.unknown)
            : dataErrorMessage(error),
        onRetry: () {
          setState(() {
            _loading = true;
            _loadError = null;
          });
          unawaited(_openSession(userId));
        },
        onSignOut: () => unawaited(_signOut()),
      );
    }
    return const AppShell();
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
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 44,
                      color: EvolupColors.of(context).textSecondary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Impossible de charger vos données. $message',
                      key: const Key('session-error'),
                      textAlign: TextAlign.center,
                    ),
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
