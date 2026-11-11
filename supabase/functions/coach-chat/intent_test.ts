import assert from 'node:assert/strict';
import {
  detectEntryIntent,
  expressions,
  isGeneralQuestion,
  relevantMetrics,
} from './intent.ts';
import { CATALOG } from './test_fixtures.ts';

const intent = (message: string) => detectEntryIntent(message, CATALOG);

Deno.test("the owner's example opens the tractions form with 8", () => {
  assert.deepEqual(intent('Je viens de faire 8 tractions.'), {
    type: 'open_metric_form',
    metric_slug: 'tractions',
    suggested_value: 8,
  });
});

Deno.test('values are converted to the storage unit', () => {
  const cases: [string, string, number | null][] = [
    ["J'ai dormi 7h30 cette nuit", 'sommeil_duree', 27000],
    ["J'ai dormi 7 h", 'sommeil_duree', 25200],
    ["j'ai fait 45 minutes de concentration", 'concentration_duree', 2700],
    ['Note 1 h 15 de lecture', 'lecture_duree', 4500],
    ["J'ai couru 5,25 km", 'course_distance', 5250],
    ["J'ai couru 800 m", 'course_distance', 800],
    ['Note mon humeur : 7/10', 'humeur', 7],
    ['Ajoute humeur 6', 'humeur', 6],
    ["J'ai fait mon 5 km en 24 min 30 s", 'course_5km', 1470],
    ["J'ai lu 30 pages", 'pages_lues', 30],
    ['Qualité du sommeil 8 sur 10, note-la', 'sommeil_qualite', 8],
    ["J'AI FAIT 12 POMPES", 'pompes', 12],
  ];
  for (const [message, slug, value] of cases) {
    assert.deepEqual(
      intent(message),
      { type: 'open_metric_form', metric_slug: slug, suggested_value: value },
      message,
    );
  }
});

Deno.test('the value is left empty unless it is certain', () => {
  const cases: [string, string][] = [
    // Two numbers: which one is the set?
    ["J'ai fait 3 séries de 8 tractions", 'tractions'],
    // No number at all.
    ['Je veux noter mon sommeil', 'sommeil_duree'],
    // Out of bounds (max 500).
    ["J'ai fait 900 tractions", 'tractions'],
    // A distance needs its unit.
    ["J'ai couru 5", 'course_distance'],
    // A score has no decimals.
    ['Note mon humeur 7,5/10', 'humeur'],
  ];
  for (const [message, slug] of cases) {
    assert.deepEqual(
      intent(message),
      { type: 'open_metric_form', metric_slug: slug, suggested_value: null },
      message,
    );
  }
});

Deno.test('no form is opened for questions, unknown, inactive or ambiguous metrics', () => {
  for (
    const message of [
      'Combien de tractions ai-je fait cette semaine ?',
      "J'ai fait 8 tractions, c'est bien ?",
      'Comment progresser en tractions',
      'Bonjour',
      "J'ai fait 20 minutes de gainage", // retired from the catalog
      "J'ai fait 8 burpees", // not in the catalog
      "J'ai fait 8 tractions et 20 pompes", // two metrics
      "J'ai couru 5 km en 25 min", // distance or 5 km time?
      'Ma concentration était de 7/10, je la note', // a score is not a duration
      'tractions 8', // no first-person report or request
    ]
  ) {
    assert.equal(intent(message), null, message);
  }
});

Deno.test('number expressions are recognised once each', () => {
  assert.deepEqual(
    expressions("j'ai dormi 7h30 et fait 8 tractions a 18h").map((e) => [
      e.kind,
      e.value,
    ]),
    [['duration', 27000], ['duration', 64800], ['plain', 8]],
  );
});

Deno.test('relevant metrics come from names, keywords and categories', () => {
  const slugs = (message: string) =>
    relevantMetrics(message, CATALOG).map((m) => m.slug);
  assert.deepEqual(slugs('Comment évoluent mes tractions ?'), ['tractions']);
  // The category brings its other metrics after the named one.
  assert.deepEqual(slugs('Parle-moi de mon sommeil'), [
    'sommeil_duree',
    'sommeil_qualite',
  ]);
  assert.ok(slugs('Et la qualité du sommeil ?').includes('sommeil_qualite'));
  assert.deepEqual(slugs('Bonjour'), []);
  // A category word brings its metrics (here: everything in Sport).
  assert.ok(slugs('Où en suis-je en sport ?').length > 0);
  assert.equal(isGeneralQuestion('Fais-moi un bilan de mes données'), true);
  assert.equal(isGeneralQuestion('Qui es-tu ?'), false);
});
