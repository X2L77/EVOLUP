import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:my_training/features/settings/settings_screen.dart';
import 'package:my_training/theme/evolup_theme.dart';

import 'support/fake_coach_repository.dart';
import 'support/fake_metrics_repository.dart';
import 'support/fake_profile_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

void main() {
  Future<FakeProfileRepository> pumpSettings(
    WidgetTester tester, {
    FakeCoachRepository? coach,
    FakeMetricsRepository? metrics,
  }) async {
    final profiles = FakeProfileRepository();
    await pumpApp(
      tester,
      TestWorld(profiles: profiles, coach: coach, metrics: metrics),
    );
    await openSection(tester, 'settings');
    return profiles;
  }

  Color background(WidgetTester tester) =>
      EvolupColors.of(tester.element(find.byType(SettingsScreen))).background;

  testWidgets('palette and mode are saved, then applied everywhere', (
    tester,
  ) async {
    final profiles = await pumpSettings(tester);
    expect(background(tester), EvolupBrand.background);

    await tapKey(tester, 'palette-violet');
    expect(profiles.profile!.appearance.palette, AppPalette.violet);
    expect(
      background(tester),
      EvolupColors.resolve(
        const AppAppearance(palette: AppPalette.violet),
      ).background,
    );

    await tester.ensureVisible(find.text('Clair'));
    await tester.tap(find.text('Clair'));
    await tester.pumpAndSettle();
    expect(profiles.profile!.appearance.mode, AppThemeMode.light);
    expect(
      background(tester),
      EvolupColors.resolve(
        const AppAppearance(
          palette: AppPalette.violet,
          mode: AppThemeMode.light,
        ),
      ).background,
    );
  });

  testWidgets('name, time zone and Polomix consent are saved', (tester) async {
    final profiles = await pumpSettings(tester);
    await tapKey(tester, 'settings-name');
    await tester.enterText(
      find.byKey(const Key('settings-name-field')),
      '  Léo ',
    );
    await tapKey(tester, 'settings-name-save');
    expect(profiles.profile!.displayName, 'Léo');

    await tapKey(tester, 'settings-timezone');
    await tester.enterText(find.byKey(const Key('timezone-search')), 'tokyo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asia/Tokyo'));
    await tester.pumpAndSettle();
    expect(profiles.profile!.timezone, 'Asia/Tokyo');

    await tapKey(tester, 'settings-coach-access');
    expect(profiles.profile!.coachDataAccess, isTrue);
  });

  testWidgets(
    'connections are announced for a next version, nothing simulated',
    (tester) async {
      await pumpSettings(tester);
      await tester.ensureVisible(find.byKey(const Key('settings-connections')));
      expect(find.textContaining('prochaine version'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-connections')),
          matching: find.byType(Switch),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('the real Polomix state and the compatibility test are shown', (
    tester,
  ) async {
    final coach = FakeCoachRepository()
      ..probeValue = CoachProbe(
        ok: false,
        checkedAt: DateTime(2026, 11, 9, 10, 30),
        secret: true,
        reachable: true,
        authorized: false,
      );
    await pumpSettings(tester, coach: coach);
    await tester.ensureVisible(find.byKey(const Key('polomix-state')));
    expect(find.textContaining('Configuré sur le serveur'), findsOneWidget);
    await tapKey(tester, 'polomix-probe');
    expect(coach.probeCalls, 1);
    expect(find.text('Clé acceptée par Polomix : non'), findsOneWidget);
    expect(
      find.text('Réponse conforme au contrat documenté : non vérifié'),
      findsOneWidget,
    );
    expect(find.textContaining('Test échoué'), findsOneWidget);
  });

  testWidgets('without Supabase, Polomix is shown as unavailable', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('polomix-state')));
    expect(find.textContaining('Indisponible'), findsOneWidget);
    expect(find.byKey(const Key('polomix-probe')), findsNothing);
  });

  testWidgets('the data summary uses French plurals, not "(s)"', (
    tester,
  ) async {
    String summary() => tester
        .widget<Text>(
          find.byKey(const Key('settings-data-summary'), skipOffstage: false),
        )
        .data!;

    final metrics = FakeMetricsRepository();
    metrics.seed(metrics.addTracked(tractions), 8);
    metrics.addTracked(sommeil);
    await pumpSettings(tester, metrics: metrics);
    expect(
      summary(),
      '2 indicateurs dans votre espace · 1 journée renseignée · '
      '1 saisie intégrée.',
    );
  });

  testWidgets('the data summary is singular when nothing is tracked', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('settings-data-summary'), skipOffstage: false),
          )
          .data,
      '0 indicateur dans votre espace · 0 journée renseignée · '
      '0 saisie intégrée.',
    );
  });

  testWidgets('all tracking data can be deleted after confirmation', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository();
    metrics.seed(metrics.addTracked(tractions), 8);
    metrics.addTracked(sommeil);
    await pumpSettings(tester, metrics: metrics);
    await tapKey(tester, 'settings-delete-all');
    expect(metrics.tracked, hasLength(2));
    await tapKey(tester, 'confirm-accept');
    expect(metrics.tracked, isEmpty);
  });
}
