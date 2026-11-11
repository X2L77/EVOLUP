// Deterministic reading of a chat message, done by the function itself:
// Polomix's public API returns free text only, and a structured reply
// requested from the model was not followed reliably (README.md).
//
// - detectEntryIntent: "Je viens de faire 8 tractions." -> open the form of
//   an active catalog metric, with a value only when it is unambiguous.
// - relevantMetrics / isGeneralQuestion: which data to read for a question.
//
// Nothing here writes anything: an action only asks the app to open a form
// that the user fills, checks and validates.

import { type CatalogMetric, normalize } from './catalog.ts';

export type FormAction = {
  type: 'open_metric_form';
  metric_slug: string;
  /** In the metric's storage unit; null when not certain. */
  suggested_value: number | null;
};

const ENTRY_CUE = new RegExp(
  "(^|[\\s,.;:!(])(j'ai|j ai|jai|je viens de|je viens d'|viens de|note|noter|" +
    'notez|enregistre|enregistrer|enregistrez|ajoute|ajouter|ajoutez|' +
    'saisis|saisir|saisissez|renseigne|renseigner|renseignez)' +
    "(?=[\\s,.;:!'-]|$)",
);

const QUESTION_START =
  /^(combien|comment|pourquoi|quel|quelle|quels|quelles|quand|est-ce|est ce|ai-je|suis-je|dois-je|peux-tu|pourrais-tu|ou )/;

type Expression = {
  kind: 'duration' | 'distance' | 'score' | 'plain';
  value: number | null;
  start: number;
  end: number;
};

const DURATION =
  /(\d+)\s*(?:h|heures?)(?![a-z])\s*(?:(\d{1,2})(?:\s*(?:min|minutes?|mn)(?![a-z]))?)?|(\d+)\s*(?:min|minutes?|mn)(?![a-z])(?:\s*(\d{1,2})\s*(?:s|sec|secondes?)(?![a-z]))?|(\d+)\s*(?:s|sec|secondes?)(?![a-z])/g;
const DISTANCE =
  /(\d+(?:[.,]\d+)?)\s*(km|kms|kilometres?|kilometre|m|metres?)(?![a-z])/g;
const SCORE = /(\d+(?:[.,]\d+)?)\s*(?:\/|sur)\s*10(?!\d)/g;
const PLAIN = /\d+(?:[.,]\d+)?/g;

function decimal(text: string): number {
  return Number(text.replace(',', '.'));
}

/** Numbers of the message with what they look like (duration, km, /10…). */
export function expressions(text: string): Expression[] {
  const found: Expression[] = [];
  const add = (
    kind: Expression['kind'],
    value: number | null,
    match: RegExpExecArray,
  ) => {
    const start = match.index;
    const end = start + match[0].length;
    if (found.some((e) => start < e.end && end > e.start)) return;
    found.push({ kind, value, start, end });
  };
  for (const m of text.matchAll(DURATION)) {
    const seconds = m[1] !== undefined
      ? Number(m[1]) * 3600 + Number(m[2] ?? 0) * 60
      : m[3] !== undefined
      ? Number(m[3]) * 60 + Number(m[4] ?? 0)
      : Number(m[5]);
    add('duration', seconds, m);
  }
  for (const m of text.matchAll(SCORE)) add('score', decimal(m[1]), m);
  for (const m of text.matchAll(DISTANCE)) {
    const unit = m[2];
    const meters = unit.startsWith('k') ? decimal(m[1]) * 1000 : decimal(m[1]);
    add('distance', meters, m);
  }
  for (const m of text.matchAll(PLAIN)) add('plain', decimal(m[0]), m);
  return found;
}

function compatibleKinds(metric: CatalogMetric): Expression['kind'][] {
  switch (metric.value_kind) {
    case 'duration':
      return ['duration'];
    case 'score':
      return ['score', 'plain'];
    case 'integer':
      return ['plain'];
    case 'decimal':
      return metric.storage_unit === 'meter'
        ? ['distance', 'plain']
        : ['plain'];
  }
}

/** The single value of the metric's kind in the message, if certain. */
function certainValue(
  metric: CatalogMetric,
  found: Expression[],
): number | null {
  const kinds = compatibleKinds(metric);
  // A plain number is not a distance: its unit is unknown.
  const usable = found.filter((e) =>
    kinds.includes(e.kind) &&
    !(metric.storage_unit === 'meter' && e.kind === 'plain')
  );
  // For a score, an explicit "7/10" wins over other plain numbers.
  const scores = usable.filter((e) => e.kind === 'score');
  const exact = metric.value_kind === 'score' && scores.length > 0
    ? scores
    : usable;
  if (exact.length !== 1 || exact[0].value === null) return null;
  const value = exact[0].value;
  const scale = 10 ** metric.storage_scale;
  if (Math.round(value * scale) / scale !== value) return null;
  if (metric.min_value !== null && value < metric.min_value) return null;
  if (metric.max_value !== null && value > metric.max_value) return null;
  return value;
}

function wordPattern(phrase: string): RegExp {
  const escaped = phrase.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^a-z0-9])(${escaped})(?=$|[^a-z0-9])`);
}

type Match = { score: number; start: number; end: number };

/** The longest keyword (or the name) of [metric] found in [text]. */
function bestMatch(metric: CatalogMetric, text: string): Match | null {
  let best: Match | null = null;
  for (const phrase of [...metric.keywords, normalize(metric.name)]) {
    if (best && phrase.length <= best.score) continue;
    const m = wordPattern(phrase).exec(text);
    if (m) {
      const start = m.index + m[1].length;
      best = { score: phrase.length, start, end: start + phrase.length };
    }
  }
  return best;
}

/** Length of the longest keyword (or name) of [metric] found in [text]. */
export function matchScore(metric: CatalogMetric, text: string): number {
  return bestMatch(metric, text)?.score ?? 0;
}

export function isQuestion(message: string): boolean {
  return message.includes('?') || QUESTION_START.test(normalize(message));
}

/**
 * A request to record a value for one active catalog metric, or null. Never
 * for a question, never for an inactive metric, never when two metrics
 * could be meant, and the value only when exactly one number of the right
 * kind and within the catalog bounds is found.
 */
export function detectEntryIntent(
  message: string,
  catalog: CatalogMetric[],
): FormAction | null {
  if (isQuestion(message)) return null;
  const text = normalize(message);
  if (!ENTRY_CUE.test(text)) return null;
  const found = expressions(text);
  const candidates = catalog
    .filter((m) => m.is_active)
    .flatMap((metric) => {
      const match = bestMatch(metric, text);
      return match ? [{ metric, match }] : [];
    })
    // A number that cannot belong to the metric (7/10 for a duration…).
    .filter((c) =>
      found.length === 0 ||
      found.some((e) => compatibleKinds(c.metric).includes(e.kind))
    );
  // "sommeil" inside "qualité du sommeil" designates the more precise one.
  const remaining = candidates.filter((c) =>
    !candidates.some((other) =>
      other !== c &&
      other.match.start <= c.match.start &&
      other.match.end >= c.match.end &&
      other.match.score > c.match.score
    )
  );
  if (remaining.length !== 1) return null;
  const metric = remaining[0].metric;
  return {
    type: 'open_metric_form',
    metric_slug: metric.slug,
    suggested_value: certainValue(metric, found),
  };
}

/** Catalog metrics a message is about (keywords, names, categories). */
export function relevantMetrics(
  message: string,
  catalog: CatalogMetric[],
  limit = 4,
): CatalogMetric[] {
  const text = normalize(message);
  const scored = catalog.map((metric) => {
    const category = normalize(metric.category);
    const categoryHit = category.length > 0 && wordPattern(category).test(text);
    return {
      metric,
      score: Math.max(matchScore(metric, text), categoryHit ? 1 : 0),
    };
  }).filter((s) => s.score > 0);
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((s) => s.metric);
}

const GENERAL_WORDS = [
  'progress',
  'evolu',
  'bilan',
  'resume',
  'statistique',
  'donnees',
  'tendance',
  'analyse',
  'conseil',
  'objectif',
  'comment je',
  "ou j'en suis",
  'point sur',
  'cette semaine',
  'ce mois',
  'lacune',
  'manque',
];

/** A question about the user's data as a whole. */
export function isGeneralQuestion(message: string): boolean {
  const text = normalize(message);
  return GENERAL_WORDS.some((word) => text.includes(word));
}
