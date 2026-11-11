import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/data/metrics/metric_values.dart';
import 'package:my_training/features/data/metric_search.dart';

import 'support/test_catalog.dart';

void main() {
  const nbsp = ' ';

  group('input', () {
    test('whole numbers for repetitions', () {
      expect(parseNumberInput(tractions, '8').stored, 8);
      expect(parseNumberInput(tractions, ' 12 ').stored, 12);
      expect(parseNumberInput(tractions, '').error, 'Saisissez une valeur.');
      expect(
        parseNumberInput(tractions, '8,5').error,
        'Saisissez un nombre entier.',
      );
      expect(parseNumberInput(tractions, '-3').isValid, isFalse);
      expect(parseNumberInput(tractions, 'abc').isValid, isFalse);
      expect(
        parseNumberInput(tractions, '501').error,
        'Valeur hors limites : entre 0${nbsp}rép. et 500${nbsp}rép.',
      );
    });

    test('kilometres are stored in whole meters', () {
      expect(parseNumberInput(courseDistance, '5,25').stored, 5250);
      expect(parseNumberInput(courseDistance, '5.2').stored, 5200);
      expect(parseNumberInput(courseDistance, '10').stored, 10000);
      // 1.1 × 1000 is not exact in floating point: still 1100 m.
      expect(parseNumberInput(courseDistance, '1,1').stored, 1100);
      expect(
        parseNumberInput(courseDistance, '5,255').error,
        'Au maximum 2 décimales.',
      );
      expect(parseNumberInput(courseDistance, '0,001').isValid, isFalse);
    });

    test('durations are stored in seconds', () {
      expect(
        parseDurationInput(sommeil, {
          DurationField.hours: '7',
          DurationField.minutes: '30',
        }).stored,
        27000,
      );
      expect(
        parseDurationInput(sommeil, {DurationField.minutes: '45'}).stored,
        2700,
      );
      expect(
        parseDurationInput(course5km, {
          DurationField.minutes: '24',
          DurationField.seconds: '30',
        }).stored,
        1470,
      );
      // Minutes alone may exceed 59 when there is no hour field.
      expect(
        parseDurationInput(course5km, {DurationField.minutes: '75'}).stored,
        4500,
      );
      expect(parseDurationInput(sommeil, {}).error, 'Saisissez une durée.');
      expect(
        parseDurationInput(sommeil, {
          DurationField.hours: '7',
          DurationField.minutes: '75',
        }).error,
        'Les minutes doivent être inférieures à 60.',
      );
      expect(
        parseDurationInput(sommeil, {DurationField.hours: '25'}).isValid,
        isFalse,
      );
    });

    test('scores stay within their bounds', () {
      expect(validateStored(humeur, 7).stored, 7);
      expect(validateStored(humeur, 0).isValid, isFalse);
      expect(validateStored(humeur, 11).isValid, isFalse);
    });

    test('a stored value is split back into the form fields', () {
      expect(splitDuration(sommeil, 27000), {
        DurationField.hours: 7,
        DurationField.minutes: 30,
      });
      expect(splitDuration(course5km, 4530), {
        DurationField.minutes: 75,
        DurationField.seconds: 30,
      });
      expect(inputText(courseDistance, 5250), '5,25');
      expect(inputText(tractions, 8), '8');
    });
  });

  group('display', () {
    test('values in French with their unit', () {
      expect(formatValue(tractions, 8), '8${nbsp}rép.');
      expect(
        formatValue(tractions, 25 / 3, aggregated: true),
        '8,3${nbsp}rép.',
      );
      expect(formatValue(tractions, 9, aggregated: true), '9${nbsp}rép.');
      expect(formatValue(courseDistance, 5250), '5,25${nbsp}km');
      expect(formatValue(courseDistance, 12000), '12${nbsp}km');
      expect(formatValue(humeur, 7), '7/10');
      expect(formatValue(sommeil, 27000), '7${nbsp}h 30');
      expect(formatValue(sommeil, 25200), '7${nbsp}h');
      expect(formatValue(concentration, 2700), '45${nbsp}min');
      expect(formatValue(course5km, 1470), '24${nbsp}min 30${nbsp}s');
      expect(formatNumber(1234567), '1 234 567');
      expect(formatDifference(tractions, -2), '−2${nbsp}rép.');
      expect(formatDifference(sommeil, 1800), '+30${nbsp}min');
    });

    test('bounds are described in display units', () {
      expect(boundsHint(courseDistance), 'Entre 0,01${nbsp}km et 300${nbsp}km');
      expect(boundsHint(humeur), 'Entre 1/10 et 10/10');
    });
  });

  group('local dates', () {
    test('no time zone can move a day', () {
      final date = LocalDate.parse('2026-03-29');
      expect(date.addDays(1).iso, '2026-03-30');
      expect(date.addDays(-29).iso, '2026-02-28');
      expect(LocalDate(2026, 12, 31).addDays(1).iso, '2027-01-01');
      expect(LocalDate(2026, 11, 9).daysSince(LocalDate(2026, 10, 31)), 9);
      expect(LocalDate(2026, 11, 9).weekday, DateTime.monday);
      expect(LocalDate(2026, 1, 31).addMonths(1).iso, '2026-02-28');
      expect(
        LocalDate.fromDateTime(DateTime(2026, 11, 9, 23, 59)).iso,
        '2026-11-09',
      );
    });
  });

  test('search ignores case and accents and uses keywords', () {
    expect(matchesSearch(sommeil, 'Sommeil', 'durée'), isTrue);
    expect(matchesSearch(sommeil, 'Sommeil', 'DUREE sommeil'), isTrue);
    expect(matchesSearch(tractions, 'Sport', 'pull-up'), isTrue);
    expect(matchesSearch(tractions, 'Sport', 'sport'), isTrue);
    expect(matchesSearch(tractions, 'Sport', 'sommeil'), isFalse);
    expect(matchesSearch(tractions, 'Sport', ''), isTrue);
  });
}
