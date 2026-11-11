import 'package:flutter/foundation.dart';

import '../../theme/evolup_theme.dart';

/// The signed-in user's profile (`public.profiles`).
@immutable
class UserProfile {
  const UserProfile({
    required this.timezone,
    this.displayName,
    this.appearance = const AppAppearance(),
    this.coachDataAccess = false,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    displayName: map['display_name'] as String?,
    timezone: map['timezone'] as String? ?? 'UTC',
    appearance: AppAppearance(
      palette: AppPalette.fromStorage(map['theme_palette'] as String?),
      mode: AppThemeMode.fromStorage(map['theme_mode'] as String?),
    ),
    coachDataAccess: map['coach_data_access'] as bool? ?? false,
  );

  final String? displayName;

  /// IANA zone used to compute "today" for the user (e.g. Europe/Paris).
  final String timezone;
  final AppAppearance appearance;

  /// Whether Polomix may read the tracked data relevant to a question.
  final bool coachDataAccess;
}

/// Fields to change; `null` keeps the current value. [clearDisplayName]
/// removes the display name.
@immutable
class ProfileChanges {
  const ProfileChanges({
    this.displayName,
    this.clearDisplayName = false,
    this.timezone,
    this.palette,
    this.mode,
    this.coachDataAccess,
  });

  final String? displayName;
  final bool clearDisplayName;
  final String? timezone;
  final AppPalette? palette;
  final AppThemeMode? mode;
  final bool? coachDataAccess;

  Map<String, dynamic> toMap() => {
    if (clearDisplayName)
      'display_name': null
    else if (displayName != null)
      'display_name': displayName,
    'timezone': ?timezone,
    'theme_palette': ?palette?.storageValue,
    'theme_mode': ?mode?.storageValue,
    'coach_data_access': ?coachDataAccess,
  };
}
