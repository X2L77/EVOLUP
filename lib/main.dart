import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/evolup_app.dart';
import 'auth/auth_repository.dart';
import 'config/supabase_config.dart';
import 'data/athlete_profile_repository.dart';
import 'data/preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController(
    SharedPreferencesStore(SharedPreferences.getInstance()),
  );
  await themeController.load();

  String? initializationError;
  AuthRepository? authRepository;
  AthleteProfileRepository? profileRepository;
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.projectUrl,
        publishableKey: SupabaseConfig.publishableKey,
      );
      final client = Supabase.instance.client;
      authRepository = SupabaseAuthRepository(
        client,
        passwordResetRedirectTo: SupabaseConfig.authRedirectUrl.isEmpty
            ? null
            : SupabaseConfig.authRedirectUrl,
      );
      profileRepository = SupabaseAthleteProfileRepository(client);
    } on Exception {
      initializationError =
          'Impossible d’initialiser Supabase. Vérifiez la configuration '
          'et réessayez.';
    }
  }

  runApp(
    EvolupApp(
      themeController: themeController,
      authRepository: authRepository,
      profileRepository: profileRepository,
      initializationError: initializationError,
    ),
  );
}
