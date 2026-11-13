import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/local_date.dart';
import 'app_session.dart';
import 'local_day_clock.dart';
import 'metrics_controller.dart';

/// For pages that load recorded data: [reload] runs once the session is
/// available, then each time the data changes anywhere in the app (entry,
/// correction, deletion) and each time the device's day changes (midnight,
/// time zone): "today", the 30-day windows and the periods depend on it.
/// The page also rebuilds when the tracked metrics change (added, removed,
/// favourite).
mixin RevisionReload<T extends StatefulWidget> on State<T> {
  MetricsController? _watched;
  LocalDayClock? _day;
  int? _seenRevision;
  LocalDate? _seenDay;

  MetricsController get metrics => _watched!;

  /// The device’s day now (the session’s [LocalDayClock]).
  LocalDate get deviceToday => _day!.today;

  Future<void> reload();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = SessionScope.of(context);
    final current = session.metrics;
    if (current != _watched) {
      _watched?.removeListener(_onMetricsChanged);
      _day?.removeListener(_onDayChanged);
      _watched = current..addListener(_onMetricsChanged);
      _day = session.day..addListener(_onDayChanged);
      _seenRevision = current.revision;
      _seenDay = session.day.today;
      unawaited(reload());
    }
  }

  void _onMetricsChanged() {
    if (!mounted) return;
    if (_watched!.revision != _seenRevision) {
      _seenRevision = _watched!.revision;
      unawaited(reload());
    }
    setState(() {});
  }

  void _onDayChanged() {
    if (!mounted || _day!.today == _seenDay) return;
    _seenDay = _day!.today;
    unawaited(reload());
    setState(() {});
  }

  @override
  void dispose() {
    _watched?.removeListener(_onMetricsChanged);
    _day?.removeListener(_onDayChanged);
    super.dispose();
  }
}
