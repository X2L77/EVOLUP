import 'package:supabase_flutter/supabase_flutter.dart';

import 'athlete_profile.dart';

abstract interface class AthleteProfileRepository {
  Future<AthleteProfile?> load(String userId);
  Future<void> save(String userId, AthleteProfile profile);
}

class SupabaseAthleteProfileRepository implements AthleteProfileRepository {
  SupabaseAthleteProfileRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'athlete_profiles';

  @override
  Future<AthleteProfile?> load(String userId) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : AthleteProfile.fromMap(row);
  }

  @override
  Future<void> save(String userId, AthleteProfile profile) async {
    await _client.from(_table).upsert({
      'user_id': userId,
      ...profile.toMap(),
    }, onConflict: 'user_id');
  }
}
