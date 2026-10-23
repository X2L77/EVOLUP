import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/evolup_app.dart';
import 'package:my_training/app/evolup_logo.dart';
import 'package:my_training/data/athlete_profile.dart';
import 'package:my_training/data/athlete_profile_repository.dart';
import 'package:my_training/data/preferences_store.dart';
import 'package:my_training/features/auth/sign_in_screen.dart';
import 'package:my_training/features/auth/widgets/auth_background.dart';
import 'package:my_training/features/auth/widgets/glass_card.dart';
import 'package:my_training/features/home/home_screen.dart';
import 'package:my_training/features/onboarding/onboarding_screen.dart';
import 'package:my_training/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_repository.dart';

void _useSurfaceSize(WidgetTester tester, Size size, {double bottomInset = 0}) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..viewInsets = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

class _MemoryPreferencesStore implements PreferencesStore {
  ThemePreferences? stored;

  @override
  Future<ThemePreferences?> load() async => stored;

  @override
  Future<void> save(ThemePreferences preferences) async {
    stored = preferences;
  }
}

class _FakeProfileRepository implements AthleteProfileRepository {
  _FakeProfileRepository({this.profile});

  AthleteProfile? profile;
  final List<AthleteProfile> saved = [];
  int loadCalls = 0;

  @override
  Future<AthleteProfile?> load(String userId) async {
    loadCalls++;
    return profile;
  }

  @override
  Future<void> save(String userId, AthleteProfile value) async {
    saved.add(value);
    profile = value;
  }
}

Future<ThemeController> _themeController({
  _MemoryPreferencesStore? store,
}) async {
  final controller = ThemeController(store ?? _MemoryPreferencesStore());
  await controller.load();
  return controller;
}

AthleteProfile _completedProfile() => const AthleteProfile(
  age: 30,
  sports: ['Musculation'],
  weeklyFrequency: 3,
  level: 'Intermédiaire',
  primaryGoal: 'Force',
  trainingLocations: ['Salle de sport'],
  onboardingCompleted: true,
);

void main() {
  Future<FakeAuthRepository> pumpSignIn(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    Size size = const Size(400, 900),
  }) async {
    _useSurfaceSize(tester, size);
    final repository = auth ?? FakeAuthRepository();
    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authRepository: repository)),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> fillCredentials(
    WidgetTester tester, {
    String email = 'athlete@evolup.fr',
    String password = 'password-123',
  }) async {
    await tester.enterText(find.byKey(const Key('auth-email')), email);
    await tester.enterText(find.byKey(const Key('auth-password')), password);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  const codeSentNotice =
      'Si cette adresse peut être utilisée, un code de vérification vient d’y '
      'être envoyé. Vous avez déjà un compte ? Modifiez l’adresse puis '
      'utilisez « Mot de passe oublié ? ».';

  testWidgets('Sign-in screen follows the build guide', (tester) async {
    _useSurfaceSize(tester, const Size(400, 900));
    final auth = FakeAuthRepository();
    final theme = await _themeController();
    await tester.pumpWidget(
      EvolupApp(
        themeController: theme,
        authRepository: auth,
        profileRepository: _FakeProfileRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(AuthBackground), findsOneWidget);
    expect(find.byType(GlassCard), findsOneWidget);
    expect(find.byType(EvolupLogo), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('Mot de passe oublié ?'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsOneWidget);
    expect(find.text('Non configuré'), findsNWidgets(2));
    // No separate sign-up mode and no theme picker on this screen.
    expect(find.byType(SegmentedButton<Object>), findsNothing);
    expect(find.text('Gold'), findsNothing);
    expect(find.text('Violet'), findsNothing);
    expect(theme.value.isDark, isTrue);

    // Logo left-aligned above « Login », then the card content in order.
    final logo = tester.getTopLeft(find.byType(EvolupLogo));
    final title = tester.getTopLeft(find.text('Login'));
    expect(logo.dy, lessThan(title.dy));
    expect((logo.dx - title.dx).abs(), lessThan(2));
    double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
    expect(top('auth-email'), lessThan(top('auth-password')));
    expect(top('auth-password'), lessThan(top('auth-submit')));
    expect(top('auth-submit'), lessThan(top('auth-create')));
    expect(top('auth-create'), lessThan(top('auth-google')));
    expect(top('auth-google'), lessThan(top('auth-apple')));
    await auth.dispose();
  });

  testWidgets('Authentication validates fields without calling Supabase', (
    tester,
  ) async {
    final auth = await pumpSignIn(tester);
    await tapKey(tester, 'auth-submit');

    expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
    expect(auth.signInCalls, 0);
    expect(auth.signUpCalls, 0);
    await auth.dispose();
  });

  testWidgets('Continuer shows loading, then understandable errors', (
    tester,
  ) async {
    final auth = await pumpSignIn(
      tester,
      auth: FakeAuthRepository()
        ..signInCompleter = Completer<void>()
        ..signInError = const AuthException(
          'Invalid login credentials',
          code: 'invalid_credentials',
        ),
    );
    await fillCredentials(tester);
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    auth.signInCompleter!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Adresse e-mail ou mot de passe incorrect.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    auth.signInError = AuthRetryableFetchException(message: 'offline');
    await tapKey(tester, 'auth-submit');
    expect(
      find.text(
        'Connexion impossible. Vérifiez votre accès à Internet et réessayez.',
      ),
      findsOneWidget,
    );
    await auth.dispose();
  });

  testWidgets('A failed sign-in never creates an account', (tester) async {
    final auth = await pumpSignIn(tester);
    await fillCredentials(tester);
    final failures = <Object>[
      const AuthException('Invalid', code: 'invalid_credentials'),
      const AuthException('Not confirmed', code: 'email_not_confirmed'),
      AuthRetryableFetchException(message: 'offline'),
      TimeoutException('slow network'),
      const AuthException('Too many', code: 'over_request_rate_limit'),
      const AuthException('Server', statusCode: '400'),
    ];
    for (final failure in failures) {
      auth.signInError = failure;
      await tapKey(tester, 'auth-submit');
      expect(find.byKey(const Key('auth-failure')), findsOneWidget);
    }

    expect(auth.signInCalls, failures.length);
    expect(auth.signUpCalls, 0);
    expect(auth.resendCalls, 0);
    expect(auth.verifyCalls, 0);
    expect(find.byKey(const Key('auth-code')), findsNothing);
    await auth.dispose();
  });

  testWidgets('An unconfirmed account requests a code only when asked', (
    tester,
  ) async {
    final auth = await pumpSignIn(
      tester,
      auth: FakeAuthRepository()
        ..signInError = const AuthException(
          'Email not confirmed',
          code: 'email_not_confirmed',
        ),
    );
    await fillCredentials(tester);
    await tapKey(tester, 'auth-submit');
    expect(find.textContaining('pas encore confirmée'), findsOneWidget);
    expect(auth.resendCalls, 0);

    await tapKey(tester, 'auth-request-code');
    expect(auth.resendCalls, 1);
    expect(auth.lastResentEmail, 'athlete@evolup.fr');
    expect(auth.signUpCalls, 0);
    expect(find.byKey(const Key('auth-code')), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('Creating an account requires 8 characters', (tester) async {
    final auth = await pumpSignIn(tester);
    await fillCredentials(tester, password: 'short');
    await tapKey(tester, 'auth-create');

    expect(find.text('8 caractères minimum.'), findsOneWidget);
    expect(auth.signUpCalls, 0);
    await auth.dispose();
  });

  testWidgets('Account creation leads to a code checked by Supabase', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 900));
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      EvolupApp(
        themeController: await _themeController(),
        authRepository: auth,
        profileRepository: _FakeProfileRepository(profile: _completedProfile()),
      ),
    );
    await tester.pumpAndSettle();
    await fillCredentials(tester, email: 'new@evolup.fr');
    await tapKey(tester, 'auth-create');

    expect(auth.signUpCalls, 1);
    expect(auth.signInCalls, 0);
    expect(find.text('Vérifiez votre adresse e-mail'), findsOneWidget);
    expect(find.text('new@evolup.fr'), findsOneWidget);
    expect(find.text(codeSentNotice), findsOneWidget);

    await tester.enterText(find.byKey(const Key('auth-code')), '12');
    await tapKey(tester, 'auth-verify');
    expect(find.text('Saisissez le code reçu par e-mail.'), findsOneWidget);
    expect(auth.verifyCalls, 0);

    auth.verifyError = const AuthException(
      'Token has expired or is invalid',
      code: 'otp_expired',
    );
    await tester.enterText(find.byKey(const Key('auth-code')), '123456');
    await tapKey(tester, 'auth-verify');
    expect(find.textContaining('Code incorrect ou expiré'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    auth.verifyError = null;
    await tapKey(tester, 'auth-verify');
    expect(auth.verifyCalls, 2);
    expect(auth.lastVerifiedEmail, 'new@evolup.fr');
    expect(auth.lastVerifiedCode, '123456');
    expect(find.byType(HomeScreen), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('A registered address gets the same neutral code step', (
    tester,
  ) async {
    final auth = await pumpSignIn(
      tester,
      auth: FakeAuthRepository()
        ..signUpError = const AuthException(
          'User already registered',
          code: 'user_already_exists',
        ),
    );
    await fillCredentials(tester);
    await tapKey(tester, 'auth-create');

    expect(find.text(codeSentNotice), findsOneWidget);
    expect(find.byKey(const Key('auth-code')), findsOneWidget);
    expect(find.textContaining('déjà'), findsOneWidget);
    expect(find.byKey(const Key('auth-failure')), findsNothing);
    await auth.dispose();
  });

  testWidgets('A new code can be requested once per minute', (tester) async {
    final auth = await pumpSignIn(tester);
    await fillCredentials(tester);
    await tapKey(tester, 'auth-create');

    expect(find.text('Renvoyer le code (60 s)'), findsOneWidget);
    await tapKey(tester, 'auth-resend');
    expect(auth.resendCalls, 0);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Renvoyer le code (30 s)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Renvoyer le code'), findsOneWidget);

    await tapKey(tester, 'auth-resend');
    expect(auth.resendCalls, 1);
    expect(auth.lastResentEmail, 'athlete@evolup.fr');
    expect(find.textContaining('un nouveau code'), findsOneWidget);
    expect(find.text('Renvoyer le code (60 s)'), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('Changing the address returns to the credentials', (
    tester,
  ) async {
    final auth = await pumpSignIn(tester);
    await fillCredentials(tester, email: 'typo@evolup.fr');
    await tapKey(tester, 'auth-create');
    await tapKey(tester, 'auth-change-email');

    expect(find.byKey(const Key('auth-code')), findsNothing);
    expect(find.text('typo@evolup.fr'), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('The password can be shown and hidden', (tester) async {
    final auth = await pumpSignIn(tester);
    EditableText passwordField() => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('auth-password')),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordField().obscureText, isTrue);
    await tapKey(tester, 'auth-password-visibility');
    expect(passwordField().obscureText, isFalse);
    await tapKey(tester, 'auth-password-visibility');
    expect(passwordField().obscureText, isTrue);
    await auth.dispose();
  });

  testWidgets('Google and Apple explain that they are not configured', (
    tester,
  ) async {
    final auth = await pumpSignIn(tester);
    await tapKey(tester, 'auth-google');
    expect(
      find.text(
        'La connexion avec Google n’est pas encore configurée. '
        'Utilisez votre adresse e-mail.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'auth-apple');
    expect(find.textContaining('avec Apple n’est pas encore'), findsOneWidget);
    expect(auth.signInCalls + auth.signUpCalls, 0);
    expect(find.byType(SignInScreen), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('Password recovery sends the existing reset link', (
    tester,
  ) async {
    final auth = await pumpSignIn(tester);
    await tapKey(tester, 'auth-forgot');
    expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
    expect(auth.resetCalls, 0);

    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'athlete@evolup.fr',
    );
    await tapKey(tester, 'auth-forgot');
    expect(auth.resetCalls, 1);
    expect(auth.signUpCalls, 0);
    expect(
      find.textContaining('lien de réinitialisation vient de lui être envoyé'),
      findsOneWidget,
    );
    await auth.dispose();
  });

  testWidgets('Without Supabase configuration nothing is simulated', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 900));
    await tester.pumpWidget(
      const MaterialApp(
        home: SignInScreen(
          authRepository: null,
          configurationMessage: 'Supabase n’est pas configuré.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await fillCredentials(tester);
    await tapKey(tester, 'auth-submit');

    expect(find.text('Supabase n’est pas configuré.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets(
    'Password recovery validates and updates through auth repository',
    (tester) async {
      _useSurfaceSize(tester, const Size(400, 900));
      final auth = FakeAuthRepository();
      final profiles = _FakeProfileRepository(profile: _completedProfile());
      await tester.pumpWidget(
        EvolupApp(
          themeController: await _themeController(),
          authRepository: auth,
          profileRepository: profiles,
        ),
      );
      await tester.pumpAndSettle();

      auth.currentUserId = 'user-1';
      auth.changes.add('user-1');
      auth.recoveryChanges.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Choisissez un nouveau mot de passe'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'short',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirmation')),
        'different',
      );
      await tester.tap(find.text('Enregistrer le mot de passe'));
      await tester.pumpAndSettle();
      expect(find.text('8 caractères minimum.'), findsOneWidget);
      expect(
        find.text('Les mots de passe ne correspondent pas.'),
        findsOneWidget,
      );
      expect(auth.passwordUpdates, 0);

      await tester.enterText(
        find.byKey(const Key('recovery-password')),
        'new-password',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirmation')),
        'new-password',
      );
      await tester.tap(find.text('Enregistrer le mot de passe'));
      await tester.pumpAndSettle();
      expect(auth.passwordUpdates, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
      await auth.dispose();
    },
  );

  testWidgets(
    'Signed-out users see auth; incomplete profiles resume onboarding',
    (tester) async {
      _useSurfaceSize(tester, const Size(400, 900));
      final auth = FakeAuthRepository();
      final profiles = _FakeProfileRepository();
      final theme = await _themeController();
      await tester.pumpWidget(
        EvolupApp(
          themeController: theme,
          authRepository: auth,
          profileRepository: profiles,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(profiles.loadCalls, 0);

      profiles.profile = const AthleteProfile(
        age: 28,
        onboardingCompleted: true,
        onboardingStep: 1,
      );
      auth.currentUserId = 'user-1';
      auth.changes.add('user-1');
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Étape 2 sur 3'), findsOneWidget);
      await auth.dispose();
    },
  );

  testWidgets('Questionnaire saves each step and routes completed users home', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 900));
    final auth = FakeAuthRepository(currentUserId: 'user-1');
    final profiles = _FakeProfileRepository();
    final theme = await _themeController();
    await tester.pumpWidget(
      EvolupApp(
        themeController: theme,
        authRepository: auth,
        profileRepository: profiles,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(
      find.text('Indiquez un âge compris entre 13 et 120 ans.'),
      findsOneWidget,
    );
    expect(find.text('Choisissez au moins un sport pratiqué.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('profile-age')));
    await tester.enterText(find.byKey(const Key('profile-age')), '29');
    await tester.ensureVisible(find.text('Musculation'));
    await tester.tap(find.text('Musculation'));
    await tester.ensureVisible(find.byKey(const Key('profile-frequency')));
    await tester.tap(find.byKey(const Key('profile-frequency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-level')));
    await tester.tap(find.byKey(const Key('profile-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intermédiaire').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Étape 2 sur 3'), findsOneWidget);
    expect(profiles.saved.last.onboardingStep, 1);
    expect(profiles.saved.last.onboardingCompleted, isFalse);

    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez votre objectif principal.'), findsOneWidget);
    await tester.ensureVisible(find.text('Force').first);
    await tester.tap(find.text('Force').first);
    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Étape 3 sur 3'), findsOneWidget);
    expect(profiles.saved.last.onboardingStep, 2);

    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(
      find.text('Choisissez au moins un lieu d’entraînement disponible.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Domicile'));
    await tester.tap(find.text('Domicile'));
    await tester.ensureVisible(find.byKey(const Key('profile-height')));
    await tester.enterText(find.byKey(const Key('profile-height')), '1');
    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(
      find.text('Taille : valeur comprise entre 80.0 et 250.0.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('profile-height')), '');
    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Coach IA'), findsOneWidget);
    expect(find.textContaining('n’est pas connecté'), findsOneWidget);
    expect(profiles.profile?.onboardingCompleted, isTrue);
    expect(profiles.profile?.primaryGoal, 'Force');
    expect(profiles.profile?.trainingLocations, contains('Domicile'));
    await auth.dispose();
  });

  testWidgets('Completed profiles bypass onboarding and can be edited', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 900));
    final auth = FakeAuthRepository(currentUserId: 'user-1');
    final profiles = _FakeProfileRepository(profile: _completedProfile());
    await tester.pumpWidget(
      EvolupApp(
        themeController: await _themeController(),
        authRepository: auth,
        profileRepository: profiles,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    await tester.tap(find.text('Modifier mon profil'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('Signed-in theme preferences restore and sync to the profile', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 900));
    final auth = FakeAuthRepository(currentUserId: 'user-1');
    final profiles = _FakeProfileRepository(
      profile: AthleteProfile.fromMap({
        ..._completedProfile().toMap(),
        'preferred_palette': 'blue',
        'is_dark_mode': false,
      }),
    );
    final store = _MemoryPreferencesStore();
    final theme = await _themeController(store: store);
    await tester.pumpWidget(
      EvolupApp(
        themeController: theme,
        authRepository: auth,
        profileRepository: profiles,
      ),
    );
    await tester.pumpAndSettle();

    expect(theme.value.palette, EvolupPalette.blue);
    expect(theme.value.isDark, isFalse);
    expect(store.stored?.palette, EvolupPalette.blue);
    await tester.tap(find.byTooltip('Préférences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Violet'));
    await tester.pumpAndSettle();
    expect(theme.value.palette, EvolupPalette.violet);
    expect(profiles.saved.last.palette, EvolupPalette.violet);
    expect(profiles.saved.last.isDark, isFalse);

    Navigator.of(tester.element(find.text('Votre univers'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byType(SignInScreen), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('Reduced motion shows the sign-in screen without animation', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 900));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: SignInScreen(authRepository: FakeAuthRepository()),
      ),
    );
    expect(
      find.ancestor(of: find.text('Login'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('Auth screen scrolls with the keyboard on narrow phones', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(320, 600), bottomInset: 250);
    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authRepository: FakeAuthRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('auth-password')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('auth-apple')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
