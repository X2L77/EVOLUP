import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/evolup_app.dart';
import 'auth/auth_repository.dart';
import 'coach/coach_repository.dart';
import 'config/supabase_config.dart';
import 'data/athlete_profile_repository.dart';
import 'data/questionnaire_draft_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final draftStore = SharedPreferencesDraftStore(
    SharedPreferences.getInstance(),
  );

  String? initializationError;
  AuthRepository? authRepository;
  AthleteProfileRepository? profileRepository;
  CoachRepository? coachRepository;
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.projectUrl,
        publishableKey: SupabaseConfig.publishableKey,
      );
      final client = Supabase.instance.client;
      authRepository = SupabaseAuthRepository(
        client,
        projectUrl: SupabaseConfig.projectUrl,
        publishableKey: SupabaseConfig.publishableKey,
        redirectUrl: SupabaseConfig.redirectUrl,
      );
      profileRepository = SupabaseAthleteProfileRepository(client);
      coachRepository = SupabaseCoachRepository(client);
    } on Exception {
      initializationError =
          'Impossible d’initialiser Supabase. Vérifiez la configuration '
          'et réessayez.';
    }
  }

  runApp(
    EvolupApp(
      authRepository: authRepository,
      profileRepository: profileRepository,
      draftStore: draftStore,
      coachRepository: coachRepository,
      initializationError: initializationError,
    ),
  );
}
