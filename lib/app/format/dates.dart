import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _shortMonths = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// "9 novembre 2026".
String formatDate(LocalDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// "lundi 9 novembre 2026".
String formatLongDate(LocalDate date) =>
    '${_weekdays[date.weekday - 1]} ${formatDate(date)}';

/// "9 nov." (with the year when [withYear]).
String formatShortDate(LocalDate date, {bool withYear = false}) =>
    '${date.day} ${_shortMonths[date.month - 1]}'
    '${withYear ? ' ${date.year}' : ''}';

/// "nov. 2026".
String formatMonth(LocalDate date) =>
    '${_shortMonths[date.month - 1]} ${date.year}';

/// "aujourd’hui", "hier", "il y a 3 jours" or the date.
String formatRelativeDay(LocalDate date, LocalDate today) {
  final days = today.daysSince(date);
  if (days == 0) return 'aujourd’hui';
  if (days == 1) return 'hier';
  if (days > 1 && days < 7) return 'il y a $days jours';
  return 'le ${formatDate(date)}';
}

/// Label of a chart point.
String formatBucket(
  LocalDate start,
  SeriesBucket bucket, {
  bool long = false,
}) => switch (bucket) {
  SeriesBucket.day => long ? formatDate(start) : formatShortDate(start),
  SeriesBucket.week =>
    long ? 'semaine du ${formatDate(start)}' : 'sem. ${formatShortDate(start)}',
  SeriesBucket.month =>
    long ? '${_months[start.month - 1]} ${start.year}' : formatMonth(start),
};
