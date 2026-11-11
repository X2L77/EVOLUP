import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_session.dart';
import 'metrics_controller.dart';

/// For pages that load recorded data: [reload] runs once the session is
/// available, then each time the data changes anywhere in the app (entry,
/// correction, deletion). The page also rebuilds when the tracked metrics
/// change (added, removed, favourite).
mixin RevisionReload<T extends StatefulWidget> on State<T> {
  MetricsController? _watched;
  int? _seenRevision;

  MetricsController get metrics => _watched!;

  Future<void> reload();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = SessionScope.of(context).metrics;
    if (current != _watched) {
      _watched?.removeListener(_onMetricsChanged);
      _watched = current..addListener(_onMetricsChanged);
      _seenRevision = current.revision;
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

  @override
  void dispose() {
    _watched?.removeListener(_onMetricsChanged);
    super.dispose();
  }
}
