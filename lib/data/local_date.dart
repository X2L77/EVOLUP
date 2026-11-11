import 'package:flutter/foundation.dart';

/// A calendar day without time or time zone, as stored in
/// `metric_daily_aggregates.local_date`.
///
/// Computations go through UTC midnights so that no conversion can move a
/// day to the previous or next one.
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// The calendar day of [time] as shown by its own clock.
  factory LocalDate.fromDateTime(DateTime time) =>
      LocalDate(time.year, time.month, time.day);

  /// Today on the device's clock.
  factory LocalDate.today() => LocalDate.fromDateTime(DateTime.now());

  /// Parses `YYYY-MM-DD` (anything after the day is ignored).
  factory LocalDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (match == null) throw FormatException('Invalid date', value);
    return LocalDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// Midnight of this day on the device's clock (for date pickers).
  DateTime toDateTime() => DateTime(year, month, day);

  /// 1 = Monday … 7 = Sunday.
  int get weekday => _utc.weekday;

  LocalDate addDays(int days) =>
      LocalDate.fromDateTime(DateTime.utc(year, month, day + days));

  LocalDate addMonths(int months) {
    final target = DateTime.utc(year, month + months);
    final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
    return LocalDate(target.year, target.month, day > lastDay ? lastDay : day);
  }

  /// Number of days from [other] to this day (positive when this is later).
  int daysSince(LocalDate other) => _utc.difference(other._utc).inDays;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}
