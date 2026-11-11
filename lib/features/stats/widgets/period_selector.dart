import 'package:flutter/material.dart';

import '../../../data/local_date.dart';
import '../../../data/metrics/metric_models.dart';

/// Periods offered by the statistics.
enum StatsPeriod {
  days7('7 j', 7),
  days30('30 j', 30),
  days90('90 j', 90),
  year('1 an', 365),
  all('Tout', null);

  const StatsPeriod(this.label, this.days);

  final String label;

  /// `null` for the whole history.
  final int? days;

  /// Days of the period ending [today]; the whole history starts at
  /// [firstDate] (today when nothing is recorded yet).
  (LocalDate, LocalDate) range(LocalDate today, LocalDate? firstDate) {
    final days = this.days;
    if (days == null) {
      final from = firstDate == null || firstDate.isAfter(today)
          ? today
          : firstDate;
      return (from, today);
    }
    return (today.addDays(1 - days), today);
  }

  /// The period of the same length just before [range], or `null` for the
  /// whole history.
  (LocalDate, LocalDate)? previous(LocalDate today) {
    final days = this.days;
    if (days == null) return null;
    final (from, _) = range(today, null);
    return (from.addDays(-days), from.addDays(-1));
  }
}

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final StatsPeriod value;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<StatsPeriod>(
      key: const Key('period-selector'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final period in StatsPeriod.values)
          ButtonSegment(
            value: period,
            label: Text(period.label, key: Key('period-${period.name}')),
          ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    ),
  );
}

/// Grouping of the chart: automatic (by period length), day, week or month.
class BucketSelector extends StatelessWidget {
  const BucketSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// `null` = automatic.
  final SeriesBucket? value;
  final ValueChanged<SeriesBucket?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<SeriesBucket?>(
      key: const Key('bucket-selector'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        const ButtonSegment(value: null, label: Text('Auto')),
        for (final bucket in SeriesBucket.values)
          ButtonSegment(
            value: bucket,
            label: Text(bucket.label, key: Key('bucket-${bucket.name}')),
          ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    ),
  );
}
