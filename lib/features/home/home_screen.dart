import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme_preferences_screen.dart';
import '../../data/athlete_profile.dart';
import '../../data/preferences_store.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.profile,
    required this.themeController,
    required this.onEditProfile,
    required this.onThemeChanged,
    required this.onSignOut,
    super.key,
  });

  final AthleteProfile profile;
  final ThemeController themeController;
  final VoidCallback onEditProfile;
  final Future<void> Function(ThemePreferences) onThemeChanged;
  final Future<void> Function() onSignOut;

  Future<void> _showPreferences(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var preferences = themeController.value;
        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: ThemePreferencesScreen(
                preferences: preferences,
                onChanged: (value) async {
                  setModalState(() => preferences = value);
                  try {
                    await onThemeChanged(value);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Les préférences de thème n’ont pas pu être '
                            'enregistrées. Vérifiez votre connexion et '
                            'réessayez.',
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await onSignOut();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La déconnexion a échoué. Réessayez.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('EVOLUP'),
        actions: [
          IconButton(
            tooltip: 'Préférences',
            onPressed: () => unawaited(_showPreferences(context)),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: () => unawaited(_signOut(context)),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bienvenue dans votre parcours.',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Votre profil est enregistré. EVOLUP se construit '
                    'progressivement, à votre rythme.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Votre profil sportif',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SummaryLine(
                            label: 'Objectif principal',
                            value: profile.primaryGoal ?? 'Non renseigné',
                          ),
                          _SummaryLine(
                            label: 'Sports',
                            value: profile.sports.join(', '),
                          ),
                          _SummaryLine(
                            label: 'Niveau',
                            value: profile.level ?? 'Non renseigné',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: onEditProfile,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Modifier mon profil'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Coach IA',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Le coach IA n’est pas connecté pour le '
                                  'moment. Aucune analyse ni proposition de '
                                  'programme n’est disponible à cette étape.',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? 'Non renseigné' : value)),
      ],
    ),
  );
}
