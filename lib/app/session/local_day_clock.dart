import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../data/local_date.dart';

/// "Today" on the device's clock, in the device's time zone (owner's
/// decision of 2026-11-12): the default date of new entries, the latest one
/// allowed and the day the overview and the statistics are computed for.
///
/// Notifies its listeners when the day changes: at midnight, after a change
/// of the device's time zone or clock, or after the app was in the
/// background. Recorded days are calendar days ([LocalDate]): a change of
/// day or zone never moves them, only what "today" is.
class LocalDayClock extends ChangeNotifier {
  LocalDayClock({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _today = LocalDate.fromDateTime(_now());
  }

  /// Longest wait between two readings of the clock: a change of time zone
  /// sends no event, so it is noticed at the latest after this delay.
  static const checkInterval = Duration(seconds: 30);

  final DateTime Function() _now;
  late LocalDate _today;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  LocalDate get today => _today;

  /// Reads the clock again. Returns whether the day changed (listeners are
  /// notified then).
  bool check() {
    if (_disposed) return false;
    final today = LocalDate.fromDateTime(_now());
    if (today == _today) return false;
    _today = today;
    notifyListeners();
    return true;
  }

  /// Reads the clock right after each local midnight, at least every
  /// [checkInterval], and when the app comes back to the foreground. Until
  /// [watch] is called, only [check] updates the day (tests).
  void watch() {
    if (_disposed || _timer != null) return;
    _lifecycle = AppLifecycleListener(onResume: check);
    _schedule();
  }

  void _schedule() {
    final now = _now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    // A little after midnight, so that the clock already reads the new day.
    final untilMidnight =
        midnight.difference(now) + const Duration(milliseconds: 50);
    final delay = Duration(
      microseconds: math.max(
        0,
        math.min(untilMidnight.inMicroseconds, checkInterval.inMicroseconds),
      ),
    );
    _timer = Timer(delay, () {
      check();
      if (!_disposed) _schedule();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
