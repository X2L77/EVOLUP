import 'package:supabase_flutter/supabase_flutter.dart';

import 'athlete_profile.dart';

/// Profile of the signed-in user.
///
/// The user is always taken from the Supabase session, never from the
/// interface; row-level security restricts each user to their own row.
abstract interface class AthleteProfileRepository {
  /// Returns `null` while the initial questionnaire has not been completed.
  Future<AthleteProfile?> loadCurrent();

  /// Creates or replaces the signed-in user's profile (one row per user).
  Future<void> saveCurrent(AthleteProfile profile);
}

class SupabaseAthleteProfileRepository implements AthleteProfileRepository {
  SupabaseAthleteProfileRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'athlete_profiles';

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AuthSessionMissingException();
    return userId;
  }

  @override
  Future<AthleteProfile?> loadCurrent() async {
    final row = await _client
        .from(_table)
        .select()
        .eq('user_id', _userId)
        .maybeSingle();
    return row == null ? null : AthleteProfile.fromMap(row);
  }

  @override
  Future<void> saveCurrent(AthleteProfile profile) async {
    await _client.from(_table).upsert({
      ...profile.toMap(),
      'user_id': _userId,
    }, onConflict: 'user_id');
  }
}
