import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_request.dart';
import 'user_profile.dart';

/// Profile of the signed-in user. The user always comes from the Supabase
/// session; RLS restricts each user to their own row.
abstract interface class ProfileRepository {
  /// Returns the profile, creating it with [timezone] the first time.
  Future<UserProfile> loadOrCreate({required String timezone});

  Future<UserProfile> update(ProfileChanges changes);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;
  static const _table = 'profiles';
  static const _columns =
      'display_name, timezone, theme_palette, theme_mode, coach_data_access';

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AuthSessionMissingException();
    return userId;
  }

  /// Guarded as a read: creating the row is idempotent (upsert that ignores
  /// an existing row), so retrying after any failure is always safe. The
  /// bound covers its up to four requests.
  @override
  Future<UserProfile> loadOrCreate({required String timezone}) => guardRead(
    'loadOrCreateProfile',
    () => _loadOrCreate(timezone),
    timeout: DataTimeouts.write,
  );

  Future<UserProfile> _loadOrCreate(String timezone) async {
    final userId = _userId;
    final existing = await _client
        .from(_table)
        .select(_columns)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) return UserProfile.fromMap(existing);
    try {
      await _insert(userId, timezone);
    } on PostgrestException catch (error) {
      // A zone the server does not know: start with UTC, changeable in the
      // settings.
      if (error.message != 'invalid_timezone') rethrow;
      await _insert(userId, 'UTC');
    }
    final created = await _client
        .from(_table)
        .select(_columns)
        .eq('user_id', userId)
        .single();
    return UserProfile.fromMap(created);
  }

  /// Creates the row; ignored if another device created it meanwhile.
  Future<void> _insert(String userId, String timezone) => _client
      .from(_table)
      .upsert(
        {'user_id': userId, 'timezone': timezone},
        onConflict: 'user_id',
        ignoreDuplicates: true,
      );

  @override
  Future<UserProfile> update(ProfileChanges changes) =>
      guardWrite('updateProfile', () async {
        final row = await _client
            .from(_table)
            .update(changes.toMap())
            .eq('user_id', _userId)
            .select(_columns)
            .single();
        return UserProfile.fromMap(row);
      });
}
