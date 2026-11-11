import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/evolup_app.dart';
import 'auth/auth_repository.dart';
import 'coach/coach_repository.dart';
import 'config/supabase_config.dart';
import 'data/metrics/metrics_repository.dart';
import 'data/profile/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initializationError;
  AuthRepository? authRepository;
  SessionServices? services;
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
      services = SessionServices(
        profiles: SupabaseProfileRepository(client),
        metrics: SupabaseMetricsRepository(client),
        coach: SupabaseCoachRepository(client),
      );
    } on Exception {
      initializationError =
          'Impossible d’initialiser Supabase. Vérifiez la configuration '
          'et réessayez.';
    }
  }

  runApp(
    EvolupApp(
      authRepository: authRepository,
      services: services,
      initializationError: initializationError,
    ),
  );
}
