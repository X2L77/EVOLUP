import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

abstract interface class PreferencesStore {
  Future<ThemePreferences?> load();
  Future<void> save(ThemePreferences preferences);
}

class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore(this._preferences);

  final Future<SharedPreferences> _preferences;

  @override
  Future<ThemePreferences?> load() async {
    final preferences = await _preferences;
    final paletteName = preferences.getString('evolup.palette');
    final isDark = preferences.getBool('evolup.isDark');
    if (paletteName == null && isDark == null) return null;
    return ThemePreferences(
      palette: EvolupPalette.fromName(paletteName),
      isDark: isDark ?? true,
    );
  }

  @override
  Future<void> save(ThemePreferences value) async {
    final preferences = await _preferences;
    await preferences.setString('evolup.palette', value.palette.name);
    await preferences.setBool('evolup.isDark', value.isDark);
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController(this._store);

  final PreferencesStore _store;
  ThemePreferences _value = const ThemePreferences();

  ThemePreferences get value => _value;

  Future<void> load() async {
    _value = await _store.load() ?? const ThemePreferences();
    notifyListeners();
  }

  Future<void> update(ThemePreferences value) async {
    await _store.save(value);
    _value = value;
    notifyListeners();
  }
}
