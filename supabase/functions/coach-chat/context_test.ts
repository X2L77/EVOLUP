import assert from 'node:assert/strict';
import { formatValue } from './catalog.ts';
import {
  buildPrompt,
  type CoachContext,
  dataSection,
  MAX_CONTEXT_CHARS,
} from './context.ts';
import { CATALOG, TRACTIONS_STATS } from './test_fixtures.ts';

const base: CoachContext = {
  today: '2026-11-09',
  timezone: 'Europe/Paris',
  dataAccess: true,
  catalog: CATALOG,
  metrics: [],
};
const metric = (slug: string) => CATALOG.find((m) => m.slug === slug)!;

Deno.test('values are written in the metric unit, like the app', () => {
  assert.equal(formatValue(metric('tractions'), 9.25, true), '9,3 rép.');
  assert.equal(formatValue(metric('course_distance'), 5250), '5,25 km');
  assert.equal(formatValue(metric('sommeil_duree'), 27000), '7 h 30');
  assert.equal(formatValue(metric('course_5km'), 1470), '24 min 30 s');
  assert.equal(formatValue(metric('humeur'), 7), '7/10');
});

Deno.test('the prompt has the rules, the data, then the user message', () => {
  const prompt = buildPrompt('Comment évoluent mes tractions ?', {
    ...base,
    metrics: [{
      metric: metric('tractions'),
      tracked: true,
      active: true,
      stats: TRACTIONS_STATS,
      weeks: [],
      days: [{ local_date: '2026-11-08', daily_value: 10, sample_count: 2 }],
    }],
  });
  assert.match(prompt, /^Tu es Polomix/);
  assert.match(prompt, /n’invente aucune valeur/);
  assert.match(prompt, /ne peux ni enregistrer, ni modifier, ni supprimer/);
  assert.match(prompt, /ne prouvent pas que l’un cause/);
  assert.match(prompt, /Tractions \(Sport\)/);
  assert.match(prompt, /30 derniers jours : 9,3 rép\. sur 4 journée/);
  assert.match(prompt, /Meilleure saisie : 14 rép\. \(2026-10-05\)/);
  assert.match(prompt, /moins de 5 journées/);
  assert.match(prompt, /2026-11-08 10 rép\. \(2 saisies\)/);
  assert.ok(
    prompt.endsWith(
      'Message de l’utilisateur :\nComment évoluent mes tractions ?',
    ),
  );
  // Nothing about metrics the question is not about.
  assert.doesNotMatch(prompt, /Durée de sommeil \(/);
});

Deno.test('without consent no value is given, and Polomix is told so', () => {
  const text = dataSection({ ...base, dataAccess: false });
  assert.match(text, /n’a pas autorisé Polomix/);
  assert.match(text, /Paramètres → Confidentialité/);
  assert.doesNotMatch(text, /journée/);
});

Deno.test('untracked and empty metrics are described as such, never invented', () => {
  const text = dataSection({
    ...base,
    metrics: [
      { metric: metric('pompes'), tracked: false, active: false },
      {
        metric: metric('sommeil_duree'),
        tracked: true,
        active: true,
        stats: null,
      },
    ],
  });
  assert.match(
    text,
    /Pompes \(Sport\) : non suivi par l’utilisateur, aucune donnée/,
  );
  assert.match(
    text,
    /Durée de sommeil \(Sommeil\) : suivi, aucune valeur enregistrée/,
  );
});

Deno.test('the data part never exceeds its limit', () => {
  const many = Array.from({ length: 200 }, (_, i) => ({
    metric: { ...metric('tractions'), name: `Indicateur ${i}` },
    tracked: true,
    active: true,
    stats: TRACTIONS_STATS,
    weeks: [],
    days: [],
  }));
  const text = dataSection({ ...base, metrics: many });
  assert.ok(text.length <= MAX_CONTEXT_CHARS + 30);
  assert.match(text, /données tronquées/);
});
