import 'package:my_training/data/device_timezone.dart';
import 'package:my_training/data/profile/profile_repository.dart';
import 'package:my_training/data/profile/user_profile.dart';
import 'package:my_training/theme/evolup_theme.dart';

/// In-memory `profiles` row. Tests never contact Supabase.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.profile});

  UserProfile? profile;
  Object? loadError;
  Object? updateError;
  String? createdWithTimezone;
  final updates = <ProfileChanges>[];

  @override
  Future<UserProfile> loadOrCreate({required String timezone}) async {
    if (loadError case final error?) throw error;
    if (profile == null) createdWithTimezone = timezone;
    return profile ??= UserProfile(timezone: timezone);
  }

  @override
  Future<UserProfile> update(ProfileChanges changes) async {
    updates.add(changes);
    if (updateError case final error?) throw error;
    final current = profile!;
    return profile = UserProfile(
      displayName: changes.clearDisplayName
          ? null
          : changes.displayName ?? current.displayName,
      timezone: changes.timezone ?? current.timezone,
      appearance: AppAppearance(
        palette: changes.palette ?? current.appearance.palette,
        mode: changes.mode ?? current.appearance.mode,
      ),
      coachDataAccess: changes.coachDataAccess ?? current.coachDataAccess,
    );
  }
}

class FakeDeviceTimezone implements DeviceTimezone {
  const FakeDeviceTimezone([this.zone = 'Europe/Paris']);

  final String? zone;

  @override
  Future<String?> current() async => zone;
}
