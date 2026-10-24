import 'package:flutter/material.dart';

import '../../app/widgets/coming_soon_page.dart';

/// Statistics destination. Statistics are not specified yet: no data is
/// shown, sampled or invented.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ComingSoonPage(
    key: Key('stats-coming-soon'),
    title: 'Statistiques',
    icon: Icons.bar_chart_rounded,
    message:
        'Les statistiques seront bientôt disponibles. Aucune donnée n’est '
        'affichée pour le moment.',
  );
}
