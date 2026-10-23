import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ThemePreferencesScreen extends StatelessWidget {
  const ThemePreferencesScreen({
    required this.preferences,
    required this.onChanged,
    super.key,
  });

  final ThemePreferences preferences;
  final ValueChanged<ThemePreferences> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Votre univers', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: EvolupPalette.values
            .map(
              (palette) => ChoiceChip(
                label: Text(palette.label),
                selected: preferences.palette == palette,
                avatar: CircleAvatar(backgroundColor: palette.seedColor),
                onSelected: (_) =>
                    onChanged(preferences.copyWith(palette: palette)),
              ),
            )
            .toList(),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Mode sombre'),
        subtitle: const Text('Choisissez un affichage confortable.'),
        value: preferences.isDark,
        onChanged: (value) => onChanged(preferences.copyWith(isDark: value)),
      ),
    ],
  );
}
