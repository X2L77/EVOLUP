import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/format/dates.dart';
import '../../../data/local_date.dart';
import '../../../data/metrics/metric_models.dart';
import '../../../data/metrics/metric_values.dart';
import '../../../theme/evolup_theme.dart';
import '../../metrics/metric_texts.dart';

/// Last day of the day, week (Monday–Sunday) or month starting at [start].
LocalDate bucketEnd(LocalDate start, SeriesBucket bucket) => switch (bucket) {
  SeriesBucket.day => start,
  SeriesBucket.week => start.addDays(6),
  SeriesBucket.month => LocalDate(
    start.year,
    start.month,
    1,
  ).addMonths(1).addDays(-1),
};

/// Start of the bucket that follows the one starting at [start].
LocalDate nextBucketStart(LocalDate start, SeriesBucket bucket) =>
    bucketEnd(start, bucket).addDays(1);

/// Days of a week or month that a chart point actually covers.
@immutable
class BucketCoverage {
  const BucketCoverage(this.covered, this.total);

  /// Days of the bucket inside the period and not after today.
  final int covered;
  final int total;

  @override
  bool operator ==(Object other) =>
      other is BucketCoverage &&
      other.covered == covered &&
      other.total == total;

  @override
  int get hashCode => Object.hash(covered, total);

  @override
  String toString() => 'BucketCoverage($covered/$total)';
}

/// For a week or a month cut by the period ([from]–[to]) or not over yet
/// ([today]): how many of its days the point covers. `null` for a complete
/// bucket, and always for days.
BucketCoverage? partialCoverage(
  LocalDate start,
  SeriesBucket bucket, {
  required LocalDate from,
  required LocalDate to,
  required LocalDate today,
}) {
  if (bucket == SeriesBucket.day) return null;
  final end = bucketEnd(start, bucket);
  final total = end.daysSince(start) + 1;
  final last = [end, to, today].reduce((a, b) => a.isBefore(b) ? a : b);
  final first = start.isBefore(from) ? from : start;
  final covered = last.isBefore(first) ? 0 : last.daysSince(first) + 1;
  return covered >= total ? null : BucketCoverage(covered, total);
}

/// The points split where a day, week or month has no value: the line of a
/// chart goes through each run and stops between runs (nothing is drawn
/// across the missing periods). Indexes into [points], in order.
List<List<int>> continuousRuns(List<SeriesPoint> points, SeriesBucket bucket) {
  final runs = <List<int>>[];
  for (var i = 0; i < points.length; i++) {
    if (i == 0 ||
        points[i].start != nextBucketStart(points[i - 1].start, bucket)) {
      runs.add([i]);
    } else {
      runs.last.add(i);
    }
  }
  return runs;
}

/// "semaine incomplète (3 jours sur 7)", "mois incomplet (12 jours sur 30)".
String partialLabel(SeriesBucket bucket, BucketCoverage coverage) {
  final kind = bucket == SeriesBucket.month
      ? 'mois incomplet'
      : 'semaine incomplète';
  final days = coverage.covered > 1 ? 'jours' : 'jour';
  return '$kind (${coverage.covered} $days sur ${coverage.total})';
}

/// Chart of any metric, built from its catalog definition: bars for totals
/// (sum aggregation), a line with points otherwise. Values are formatted in
/// the metric's unit. Touching or hovering a point shows its exact value.
/// Only real points are drawn; nothing is interpolated or smoothed: the line
/// stops where a day, week or month has no value. Weeks and months cut by
/// the period or not over yet are drawn lighter and said to be incomplete.
class MetricChart extends StatefulWidget {
  const MetricChart({
    required this.definition,
    required this.series,
    required this.from,
    required this.to,
    this.today,
    this.height = 210,
    this.secondary = false,
    super.key,
  });

  final MetricDefinition definition;
  final MetricSeries series;
  final LocalDate from;
  final LocalDate to;

  /// The device's day: the current week or month is not over yet. `null`:
  /// [to].
  final LocalDate? today;
  final double height;

  /// Second metric of a comparison: drawn with the secondary color.
  final bool secondary;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  int? _selected;

  @override
  void didUpdateWidget(MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) _selected = null;
  }

  bool get _bars => widget.definition.aggregation == MetricAggregation.sum;

  BucketCoverage? _coverage(SeriesPoint point) => partialCoverage(
    point.start,
    widget.series.bucket,
    from: widget.from,
    to: widget.to,
    today: widget.today ?? widget.to,
  );

  void _select(Offset position, _ChartLayout layout) {
    final points = widget.series.points;
    if (points.isEmpty) return;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (layout.x(points[i].start) - position.dx).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    if (best != _selected) setState(() => _selected = best);
  }

  String _describe(SeriesPoint point) {
    final d = widget.definition;
    final aggregated = point.sampleCount > 1;
    final coverage = _coverage(point);
    final partial = coverage == null
        ? ''
        : ' · ${partialLabel(widget.series.bucket, coverage)}';
    return '${formatBucket(point.start, widget.series.bucket, long: true)} : '
        '${formatValue(d, point.value, aggregated: aggregated)}'
        ' · ${entriesLabel(point.sampleCount)}$partial';
  }

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final points = widget.series.points;
    final selected = _selected == null || _selected! >= points.length
        ? null
        : points[_selected!];
    final values = points.map((p) => p.value);
    final partial = [for (final p in points) _coverage(p) != null];
    final partialCount = partial.where((p) => p).length;
    final runs = continuousRuns(points, widget.series.bucket);
    final partialName = widget.series.bucket == SeriesBucket.month
        ? (partialCount > 1 ? 'mois incomplets' : 'mois incomplet')
        : (partialCount > 1 ? 'semaines incomplètes' : 'semaine incomplète');
    final summary = points.isEmpty
        ? 'Aucune donnée'
        : 'Graphique de ${widget.definition.name}, ${points.length} points '
              '(${widget.series.bucket.label.toLowerCase()}), du '
              '${formatDate(points.first.start)} au '
              '${formatDate(points.last.start)}. Minimum '
              '${formatValue(widget.definition, values.reduce(math.min), aggregated: true)}'
              ', maximum '
              '${formatValue(widget.definition, values.reduce(math.max), aggregated: true)}.'
              '${partialCount == 0 ? '' : ' $partialCount $partialName, affichés en clair.'}'
              '${runs.length > 1 && !_bars ? ' Ligne interrompue là où il manque des valeurs.' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 20,
          child: Text(
            selected == null
                ? 'Touchez un point pour voir sa valeur'
                : _describe(selected),
            key: const Key('chart-selection'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: selected == null
                  ? colors.textSecondary
                  : colors.textPrimary,
              fontWeight: selected == null ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: summary,
          excludeSemantics: true,
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = _ChartLayout.compute(
                  size: Size(constraints.maxWidth, widget.height),
                  definition: widget.definition,
                  series: widget.series,
                  from: widget.from,
                  to: widget.to,
                  labelStyle: textTheme.labelSmall!.copyWith(
                    color: colors.textSecondary,
                  ),
                );
                return MouseRegion(
                  onHover: (event) => _select(event.localPosition, layout),
                  child: GestureDetector(
                    key: const Key('metric-chart'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _select(d.localPosition, layout),
                    onHorizontalDragUpdate: (d) =>
                        _select(d.localPosition, layout),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, widget.height),
                      painter: _ChartPainter(
                        layout: layout,
                        points: points,
                        partial: partial,
                        runs: runs,
                        selected: _selected,
                        bars: _bars,
                        color: widget.secondary
                            ? colors.chartSecondary
                            : colors.chartPrimary,
                        grid: colors.chartGrid,
                        background: colors.background,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (partialCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            widget.series.bucket == SeriesBucket.month
                ? 'Points en clair : mois en partie hors de la période ou en '
                      'cours. Leur valeur ne porte que sur les jours couverts.'
                : 'Points en clair : semaines en partie hors de la période ou '
                      'en cours. Leur valeur ne porte que sur les jours '
                      'couverts.',
            key: const Key('chart-partial-note'),
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Geometry shared by the painter and the touch handling.
class _ChartLayout {
  _ChartLayout._({
    required this.plot,
    required this.domainFrom,
    required this.domainDays,
    required this.yMin,
    required this.yMax,
    required this.yLabels,
    required this.xLabels,
    required this.slotWidth,
  });

  factory _ChartLayout.compute({
    required Size size,
    required MetricDefinition definition,
    required MetricSeries series,
    required LocalDate from,
    required LocalDate to,
    required TextStyle labelStyle,
  }) {
    final points = series.points;
    var domainFrom = from;
    var domainTo = to;
    if (points.isNotEmpty) {
      if (points.first.start.isBefore(domainFrom)) {
        domainFrom = points.first.start;
      }
      if (points.last.start.isAfter(domainTo)) domainTo = points.last.start;
    }
    final domainDays = math.max(1, domainTo.daysSince(domainFrom));

    final bars = definition.aggregation == MetricAggregation.sum;
    var minValue = points.isEmpty
        ? 0.0
        : points.map((p) => p.value).reduce(math.min);
    var maxValue = points.isEmpty
        ? 1.0
        : points.map((p) => p.value).reduce(math.max);
    if (bars) minValue = math.min(0, minValue);
    final range = maxValue - minValue;
    final pad = range == 0 ? (maxValue.abs() * 0.1 + 1) : range * 0.12;
    var yMin = bars ? minValue : minValue - pad;
    if (minValue >= 0 && yMin < 0) yMin = 0;
    final yMax = maxValue + pad;

    TextPainter label(String text) => TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final yValues = [yMax, (yMin + yMax) / 2, yMin];
    final yLabels = [
      for (final v in yValues)
        (v, label(formatValue(definition, v, aggregated: true))),
    ];
    final gutter = yLabels.map((l) => l.$2.width).reduce(math.max) + 10;
    const bottom = 20.0;
    final plot = Rect.fromLTRB(gutter, 8, size.width - 6, size.height - bottom);

    final buckets = switch (series.bucket) {
      SeriesBucket.day => domainDays + 1,
      SeriesBucket.week => domainDays ~/ 7 + 1,
      SeriesBucket.month => domainDays ~/ 30 + 1,
    };
    final slotWidth = plot.width / math.max(1, buckets);

    final xLabels = <(double, TextPainter)>[];
    LocalDate bucketStart(LocalDate d) => switch (series.bucket) {
      SeriesBucket.day => d,
      SeriesBucket.week => d.addDays(1 - d.weekday),
      SeriesBucket.month => LocalDate(d.year, d.month, 1),
    };
    final first = bucketStart(domainFrom);
    final last = bucketStart(domainTo);
    for (final date in {first, last}) {
      final x =
          plot.left + plot.width * date.daysSince(domainFrom) / domainDays;
      xLabels.add((x, label(formatBucket(date, series.bucket))));
    }

    return _ChartLayout._(
      plot: plot,
      domainFrom: domainFrom,
      domainDays: domainDays,
      yMin: yMin,
      yMax: yMax,
      yLabels: [
        for (var i = 0; i < yLabels.length; i++)
          (plot.top + plot.height * i / (yLabels.length - 1), yLabels[i].$2),
      ],
      xLabels: xLabels,
      slotWidth: slotWidth,
    );
  }

  final Rect plot;
  final LocalDate domainFrom;
  final int domainDays;
  final double yMin;
  final double yMax;
  final List<(double, TextPainter)> yLabels;
  final List<(double, TextPainter)> xLabels;
  final double slotWidth;

  double x(LocalDate date) =>
      plot.left + plot.width * date.daysSince(domainFrom) / domainDays;

  double y(double value) =>
      plot.bottom - plot.height * (value - yMin) / math.max(1e-9, yMax - yMin);
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.layout,
    required this.points,
    required this.partial,
    required this.runs,
    required this.selected,
    required this.bars,
    required this.color,
    required this.grid,
    required this.background,
  });

  final _ChartLayout layout;
  final List<SeriesPoint> points;

  /// Per point: an incomplete week or month (drawn lighter).
  final List<bool> partial;

  /// Consecutive points joined by the line ([continuousRuns]).
  final List<List<int>> runs;
  final int? selected;
  final bool bars;
  final Color color;
  final Color grid;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = layout.plot;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final (y, painter) in layout.yLabels) {
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      painter.paint(
        canvas,
        Offset(plot.left - painter.width - 8, y - painter.height / 2),
      );
    }
    for (final (x, painter) in layout.xLabels) {
      final left = (x - painter.width / 2).clamp(
        plot.left,
        size.width - painter.width,
      );
      painter.paint(canvas, Offset(left, plot.bottom + 5));
    }
    if (points.isEmpty) return;

    if (bars) {
      final width = (layout.slotWidth * 0.62).clamp(2.0, 26.0);
      for (var i = 0; i < points.length; i++) {
        final x = layout.x(points[i].start);
        final top = layout.y(points[i].value);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTRB(
            x - width / 2,
            top,
            x + width / 2,
            layout.y(layout.yMin),
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        final alpha = partial[i] ? 0.3 : (i == selected ? 1.0 : 0.7);
        canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: alpha));
        if (partial[i]) {
          canvas.drawRRect(
            rect,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
      }
    } else {
      final line = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      Offset at(int i) =>
          Offset(layout.x(points[i].start), layout.y(points[i].value));
      // One path per run of consecutive points: no line across a missing
      // day, week or month.
      for (final run in runs) {
        if (run.length < 2) continue;
        final path = Path()..moveTo(at(run.first).dx, at(run.first).dy);
        for (final i in run.skip(1)) {
          path.lineTo(at(i).dx, at(i).dy);
        }
        canvas.drawPath(path, line);
      }
      final radius = points.length > 60 ? 2.0 : 3.2;
      for (var i = 0; i < points.length; i++) {
        final offset = at(i);
        canvas.drawCircle(offset, radius + 1.4, Paint()..color = background);
        if (partial[i]) {
          // Hollow: an incomplete week or month.
          canvas.drawCircle(
            offset,
            radius,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        } else {
          canvas.drawCircle(offset, radius, Paint()..color = color);
        }
      }
    }

    final index = selected;
    if (index != null && index < points.length) {
      final x = layout.x(points[index].start);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      if (!bars) {
        final offset = Offset(x, layout.y(points[index].value));
        canvas.drawCircle(offset, 6, Paint()..color = color);
        canvas.drawCircle(offset, 3, Paint()..color = background);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      !listEquals(oldDelegate.partial, partial) ||
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      oldDelegate.layout.plot != layout.plot ||
      oldDelegate.layout.yMax != layout.yMax;
}
