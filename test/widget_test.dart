import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/evolup_logo.dart';
import 'package:my_training/app/widgets/evolup_background.dart';
import 'package:my_training/app/widgets/glass_card.dart';
import 'package:my_training/auth/auth_error.dart';
import 'package:my_training/auth/social_auth_provider.dart';
import 'package:my_training/features/auth/sign_in_screen.dart';
import 'package:my_training/features/home/home_screen.dart';
import 'package:my_training/features/onboarding/questionnaire_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';
import 'support/test_helpers.dart';

void main() {
  Future<FakeAuthRepository> pumpSignIn(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    Size size = const Size(400, 900),
    bool socialPlatformSupported = true,
  }) async {
    useSurfaceSize(tester, size);
    final repository = auth ?? FakeAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          authRepository: repository,
          socialPlatformSupported: socialPlatformSupported,
        ),
      ),
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

  const codeSentNotice =
      'Si cette adresse peut être utilisée, un code de vérification vient d’y '
      'être envoyé. Vous avez déjà un compte ? Modifiez l’adresse puis '
      'utilisez « Mot de passe oublié ? ».';

  group('Sign-in screen', () {
    testWidgets('follows the build guide', (tester) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth, profiles: FakeProfileRepository());

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(EvolupBackground), findsOneWidget);
      expect(find.byType(GlassCard), findsOneWidget);
      expect(find.byType(EvolupLogo), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(find.text('Mot de passe oublié ?'), findsOneWidget);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      expect(find.text('Continuer avec Apple'), findsOneWidget);
      expect(find.byType(SegmentedButton<Object>), findsNothing);
      // Themes are postponed to V1.1.0: no palette picker anywhere.
      expect(find.text('Gold'), findsNothing);
      expect(find.text('Violet'), findsNothing);

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

    testWidgets('validates fields without calling Supabase', (tester) async {
      final auth = await pumpSignIn(tester);
      await tapKey(tester, 'auth-submit');

      expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
      expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
      expect(auth.signInCalls, 0);
      expect(auth.signUpCalls, 0);
      await auth.dispose();
    });

    testWidgets('shows loading, then understandable errors', (tester) async {
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

    testWidgets('a failed sign-in never creates an account', (tester) async {
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

    testWidgets('an unconfirmed account requests a code only when asked', (
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

    testWidgets('creating an account requires 8 characters', (tester) async {
      final auth = await pumpSignIn(tester);
      await fillCredentials(tester, password: 'short');
      await tapKey(tester, 'auth-create');

      expect(find.text('8 caractères minimum.'), findsOneWidget);
      expect(auth.signUpCalls, 0);
      await auth.dispose();
    });

    testWidgets('a registered address gets the same neutral code step', (
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
      expect(find.byKey(const Key('auth-failure')), findsNothing);
      await auth.dispose();
    });

    testWidgets('a new code can be requested once per minute', (tester) async {
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
      await auth.dispose();
    });

    testWidgets('changing the address returns to the credentials', (
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

    testWidgets('the password can be shown and hidden', (tester) async {
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

    testWidgets('password recovery sends the existing reset link', (
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
        find.textContaining(
          'lien de réinitialisation vient de lui être envoyé',
        ),
        findsOneWidget,
      );
      await auth.dispose();
    });

    testWidgets('without Supabase configuration nothing is simulated', (
      tester,
    ) async {
      useSurfaceSize(tester, const Size(400, 900));
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

    testWidgets('scrolls with the keyboard on narrow phones', (tester) async {
      await pumpSignIn(tester, size: const Size(320, 600));
      useSurfaceSize(tester, const Size(320, 600), bottomInset: 250);
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('auth-password')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('auth-apple')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion shows the screen without animation', (
      tester,
    ) async {
      useSurfaceSize(tester, const Size(400, 900));
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
  });

  group('Google and Apple', () {
    testWidgets('stay unavailable while disabled in Supabase', (tester) async {
      final auth = await pumpSignIn(tester);
      expect(find.text('Non configuré'), findsNWidgets(2));

      await tapKey(tester, 'auth-google');
      expect(
        find.text(
          'La connexion avec Google n’est pas encore configurée. '
          'Utilisez votre adresse e-mail.',
        ),
        findsOneWidget,
      );
      expect(auth.socialSignIns, isEmpty);
      expect(auth.signInCalls + auth.signUpCalls, 0);
      await auth.dispose();
    });

    testWidgets('start a real OAuth sign-in once enabled in Supabase', (
      tester,
    ) async {
      final auth = await pumpSignIn(
        tester,
        auth: FakeAuthRepository(enabledProviders: {SocialAuthProvider.google}),
      );
      expect(find.text('Non configuré'), findsOneWidget);

      await tapKey(tester, 'auth-google');
      expect(auth.socialSignIns, [SocialAuthProvider.google]);
      expect(find.textContaining('Terminez la connexion'), findsOneWidget);

      await tapKey(tester, 'auth-apple');
      expect(auth.socialSignIns, [SocialAuthProvider.google]);
      await auth.dispose();
    });

    testWidgets('say when the provider list cannot be checked', (tester) async {
      final auth = await pumpSignIn(
        tester,
        auth: FakeAuthRepository()
          ..providersError = TimeoutException('offline'),
      );
      expect(find.text('Indisponible'), findsNWidgets(2));
      await tapKey(tester, 'auth-apple');
      expect(find.textContaining('n’a pas pu être vérifiée'), findsOneWidget);
      expect(auth.socialSignIns, isEmpty);
      await auth.dispose();
    });

    testWidgets('are unavailable on platforms without an OAuth callback', (
      tester,
    ) async {
      final auth = await pumpSignIn(
        tester,
        auth: FakeAuthRepository(enabledProviders: {SocialAuthProvider.google}),
        socialPlatformSupported: false,
      );
      expect(find.text('Non disponible ici'), findsNWidgets(2));
      await tapKey(tester, 'auth-google');
      expect(auth.socialSignIns, isEmpty);
      await auth.dispose();
    });

    testWidgets('a cancelled OAuth return is shown on the sign-in screen', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth, profiles: FakeProfileRepository());

      auth.failures.add(AuthFailure.oauthCancelled);
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.textContaining('Connexion annulée'), findsOneWidget);
      await auth.dispose();
    });
  });

  group('Session and profile routing', () {
    testWidgets('a session without a profile opens the questionnaire', (
      tester,
    ) async {
      final auth = FakeAuthRepository(currentUserId: 'user-1');
      final profiles = FakeProfileRepository();
      await pumpApp(tester, auth: auth, profiles: profiles);

      expect(profiles.loadCalls, 1);
      expect(find.byType(QuestionnaireScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await auth.dispose();
    });

    testWidgets('a restored session with a profile opens the home screen', (
      tester,
    ) async {
      final auth = FakeAuthRepository(currentUserId: 'user-1');
      await pumpApp(
        tester,
        auth: auth,
        profiles: FakeProfileRepository(profile: completedProfile),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(QuestionnaireScreen), findsNothing);
      expect(
        find.text('3 par semaine · Lundi, Mercredi, Vendredi'),
        findsOneWidget,
      );
      await auth.dispose();
    });

    testWidgets('account creation then code leads to the questionnaire', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth, profiles: FakeProfileRepository());
      await fillCredentials(tester, email: 'new@evolup.fr');
      await tapKey(tester, 'auth-create');

      expect(auth.signUpCalls, 1);
      expect(auth.signInCalls, 0);
      expect(find.text('Vérifiez votre adresse e-mail'), findsOneWidget);
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
      expect(find.byType(QuestionnaireScreen), findsNothing);

      auth.verifyError = null;
      await tapKey(tester, 'auth-verify');
      expect(auth.lastVerifiedEmail, 'new@evolup.fr');
      expect(auth.lastVerifiedCode, '123456');
      expect(find.byType(QuestionnaireScreen), findsOneWidget);
      await auth.dispose();
    });

    testWidgets(
      'a profile loading error offers a retry, not the questionnaire',
      (tester) async {
        final auth = FakeAuthRepository(currentUserId: 'user-1');
        final profiles = FakeProfileRepository()
          ..loadError = TimeoutException('offline');
        await pumpApp(tester, auth: auth, profiles: profiles);

        expect(
          find.textContaining('Impossible de charger votre profil'),
          findsOneWidget,
        );
        expect(find.byType(QuestionnaireScreen), findsNothing);

        profiles
          ..loadError = null
          ..profile = completedProfile;
        await tester.tap(find.text('Réessayer'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        await auth.dispose();
      },
    );

    testWidgets('password recovery updates through the auth repository', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpApp(
        tester,
        auth: auth,
        profiles: FakeProfileRepository(profile: completedProfile),
      );
      auth
        ..openSession()
        ..recoveryChanges.add(null);
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
    });

    testWidgets('signing out from home returns to the sign-in screen', (
      tester,
    ) async {
      final auth = FakeAuthRepository(currentUserId: 'user-1');
      await pumpApp(
        tester,
        auth: auth,
        profiles: FakeProfileRepository(profile: completedProfile),
      );
      await tester.tap(find.byTooltip('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect(find.byType(SignInScreen), findsOneWidget);
      await auth.dispose();
    });
  });
}
