import 'package:flutter/material.dart';

import '../../features/coach/coach_screen.dart';
import '../../features/data/my_data_screen.dart';
import '../../features/overview/overview_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/stats/stats_screen.dart';
import '../session/app_session.dart';
import 'app_destination.dart';
import 'evolup_nav_bar.dart';

/// Signed-in part of the app: the five sections behind the floating
/// navigation bar.
///
/// Each page is built the first time it is opened, then kept alive while
/// hidden (scroll position, chat and inputs survive section changes); hidden
/// pages have their animations paused. The section shown is the session's
/// [SignedInSession.destination], so any page can switch section.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _opened = <AppDestination>{AppDestination.overview};
  ValueNotifier<AppDestination>? _destination;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final destination = SessionScope.of(context).destination;
    if (destination != _destination) {
      _destination?.removeListener(_onDestination);
      _destination = destination..addListener(_onDestination);
      _opened.add(destination.value);
    }
  }

  void _onDestination() => setState(() => _opened.add(_destination!.value));

  @override
  void dispose() {
    _destination?.removeListener(_onDestination);
    super.dispose();
  }

  Widget _page(AppDestination destination) => switch (destination) {
    AppDestination.overview => const OverviewScreen(),
    AppDestination.data => const MyDataScreen(),
    AppDestination.stats => const StatsScreen(),
    AppDestination.polomix => const CoachScreen(),
    AppDestination.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final current = _destination!.value;
    return PopScope(
      // The system back action returns to the overview instead of leaving.
      canPop: current == AppDestination.overview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _destination!.value = AppDestination.overview;
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: current.index,
          children: [
            for (final destination in AppDestination.values)
              _opened.contains(destination)
                  ? TickerMode(
                      enabled: destination == current,
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
          selectedIndex: current.index,
          onSelected: (index) =>
              _destination!.value = AppDestination.values[index],
        ),
      ),
    );
  }
}
