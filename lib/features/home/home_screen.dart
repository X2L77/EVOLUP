import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/evolup_logo.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../data/athlete_profile.dart';
import '../../theme/evolup_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.profile,
    required this.onEditProfile,
    required this.onSignOut,
    super.key,
  });

  final AthleteProfile profile;
  final VoidCallback onEditProfile;
  final Future<void> Function() onSignOut;

  Future<void> _signOut(BuildContext context) async {
    try {
      await onSignOut();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La déconnexion a échoué. Réessayez.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final goal = profile.goalDetails == null
        ? profile.primaryGoal
        : '${profile.primaryGoal} — ${profile.goalDetails}';
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 20,
          title: const EvolupLogo(size: 30),
          actions: [
            IconButton(
              tooltip: 'Se déconnecter',
              onPressed: () => unawaited(_signOut(context)),
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Bienvenue dans votre parcours.',
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Votre profil est enregistré. EVOLUP se construit '
                      'progressivement, à votre rythme.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: EvolupColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Votre profil sportif',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SummaryLine(label: 'Objectif', value: goal),
                          _SummaryLine(label: 'Niveau', value: profile.level),
                          _SummaryLine(
                            label: 'Séances',
                            value:
                                '${profile.weeklySessions} par semaine · '
                                '${profile.trainingDays.join(', ')}',
                          ),
                          _SummaryLine(
                            label: 'Durée',
                            value: '${profile.sessionDurationMinutes} minutes',
                          ),
                          _SummaryLine(
                            label: 'Lieux',
                            value: profile.trainingLocations.join(', '),
                          ),
                          if (profile.trainsAtHome)
                            _SummaryLine(
                              label: 'Matériel',
                              value: profile.homeEquipment.join(', '),
                            ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('home-edit-profile'),
                            onPressed: onEditProfile,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: EvolupColors.textPrimary,
                              side: const BorderSide(
                                color: EvolupColors.glassBorder,
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Modifier mon profil'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const GlassCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            color: EvolupColors.focus,
                          ),
                          SizedBox(width: 14),
                          Expanded(
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
                  ],
                ),
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
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: EvolupColors.textSecondary),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
