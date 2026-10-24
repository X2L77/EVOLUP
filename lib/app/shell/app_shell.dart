import 'package:flutter/material.dart';

import '../../features/stats/stats_screen.dart';
import '../../theme/evolup_theme.dart';
import 'evolup_nav_bar.dart';

/// Main destinations, in the order of the navigation bar (Home in the
/// middle).
enum AppDestination {
  coach('Coach IA', Icons.sms_outlined, Icons.sms_rounded),
  home('Home', Icons.home_outlined, Icons.home_rounded),
  stats('Statistiques', Icons.bar_chart_outlined, Icons.bar_chart_rounded);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Signed-in part of the app: the main destinations behind the floating
/// navigation bar.
///
/// Each page is built the first time it is opened, then kept alive while
/// hidden (scroll position and future inputs survive tab changes); hidden
/// pages have their animations paused.
class AppShell extends StatefulWidget {
  const AppShell({required this.home, required this.coach, super.key});

  /// The home page, built by `AppGate` with the user's profile.
  final Widget home;

  /// The Coach IA page, built by `AppGate` with the coach repository.
  final Widget coach;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _current = AppDestination.home;
  final _opened = <AppDestination>{AppDestination.home};

  void _select(AppDestination destination) {
    if (destination == _current) return;
    setState(() {
      _current = destination;
      _opened.add(destination);
    });
  }

  Widget _page(AppDestination destination) => switch (destination) {
    AppDestination.coach => widget.coach,
    AppDestination.home => widget.home,
    AppDestination.stats => const StatsScreen(),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    // The system back action returns home instead of leaving the app.
    canPop: _current == AppDestination.home,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _select(AppDestination.home);
    },
    child: Scaffold(
      backgroundColor: EvolupColors.background,
      extendBody: true,
      body: IndexedStack(
        index: _current.index,
        children: [
          for (final destination in AppDestination.values)
            _opened.contains(destination)
                ? TickerMode(
                    enabled: destination == _current,
                    child: _page(destination),
                  )
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: EvolupNavBar(
        items: [
          for (final destination in AppDestination.values)
            EvolupNavItem(
              key: Key('nav-${destination.name}'),
              label: destination.label,
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
            ),
        ],
        selectedIndex: _current.index,
        onSelected: (index) => _select(AppDestination.values[index]),
      ),
    ),
  );
}
