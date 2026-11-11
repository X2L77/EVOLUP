import 'package:flutter/material.dart';

/// The five sections of EVOLUP, in the order of the navigation bar.
enum AppDestination {
  overview('Vue d’ensemble', Icons.dashboard_outlined, Icons.dashboard_rounded),
  data('Mes données', Icons.dataset_outlined, Icons.dataset_rounded),
  stats('Statistiques', Icons.insights_outlined, Icons.insights_rounded),
  polomix('Polomix', Icons.forum_outlined, Icons.forum_rounded),
  settings('Paramètres', Icons.settings_outlined, Icons.settings_rounded);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
