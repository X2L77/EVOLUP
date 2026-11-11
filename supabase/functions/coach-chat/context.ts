// The text sent to Polomix: rules, the EVOLUP data relevant to the message
// (never the whole database), then the user's message.
//
// Polomix's documented endpoint takes a single `message` field (no system
// role), so the rules and the data are placed before the user's text.

import {
  AGGREGATION_LABEL,
  type CatalogMetric,
  formatValue,
} from './catalog.ts';
import type { Day, OverviewMetric, Point, Statistics } from './data.ts';

/** Upper bound of the data part, whatever the number of metrics. */
export const MAX_CONTEXT_CHARS = 3500;

export type MetricContext = {
  metric: CatalogMetric;
  tracked: boolean;
  active: boolean;
  stats?: Statistics | null;
  weeks?: Point[];
  days?: Day[];
};

export type CoachContext = {
  today: string;
  timezone: string;
  dataAccess: boolean;
  /** The data could not be read (database error). */
  unavailable?: boolean;
  catalog: CatalogMetric[];
  metrics: MetricContext[];
  /** Summary of every tracked metric, for questions about the whole. */
  overview?: { metric: CatalogMetric; item: OverviewMetric }[];
};

const RULES = [
  'Tu es Polomix, l’analyste personnel de l’application EVOLUP. Réponds en ' +
  'français, clairement et brièvement.',
  'Règles :',
  '- Appuie-toi uniquement sur les données EVOLUP ci-dessous. Si une ' +
  'information manque, dis-le : n’invente aucune valeur, date ou tendance.',
  '- Tu ne peux ni enregistrer, ni modifier, ni supprimer de données : ' +
  'l’utilisateur saisit et valide lui-même ses valeurs dans les ' +
  'formulaires EVOLUP.',
  '- Deux indicateurs qui évoluent ensemble ne prouvent pas que l’un cause ' +
  'l’autre.',
  '- Signale les limites de ton analyse (peu de journées, données ' +
  'manquantes).',
].join('\n');

function label(metric: CatalogMetric): string {
  return metric.category ? `${metric.name} (${metric.category})` : metric.name;
}

function metricBlock(entry: MetricContext): string[] {
  const { metric } = entry;
  const head = `• ${label(metric)}`;
  if (!entry.tracked) {
    return [`${head} : non suivi par l’utilisateur, aucune donnée.`];
  }
  const stats = entry.stats;
  if (!stats || stats.all_time.days_count === 0) {
    return [`${head} : suivi, aucune valeur enregistrée.`];
  }
  const v = (n: number, aggregated = true) =>
    formatValue(metric, n, aggregated);
  const lines = [
    `${head} — plusieurs saisies le même jour : ${
      AGGREGATION_LABEL[metric.aggregation]
    }` +
    (entry.active ? '.' : ' (retiré de la liste active, historique conservé).'),
  ];
  const all = stats.all_time;
  lines.push(
    `  Historique : ${all.days_count} journée(s) du ${all.first_date} au ` +
      `${all.last_date}, ${all.sample_count ?? 0} saisie(s).`,
  );
  const p = stats.period;
  lines.push(
    p.days_count === 0 || p.value === null
      ? `  30 derniers jours : aucune journée enregistrée.`
      : `  30 derniers jours : ${v(p.value)} sur ${p.days_count} journée(s)` +
        (p.per_day_average != null
          ? `, soit ${v(p.per_day_average)} par journée enregistrée.`
          : '.'),
  );
  if (stats.record) {
    lines.push(
      `  Meilleure saisie : ${
        v(stats.record.value, false)
      } (${stats.record.local_date}).`,
    );
  }
  if (stats.trend) {
    lines.push(
      `  Tendance sur 30 jours (ajustement linéaire, indicatif) : ` +
        `${stats.trend.slope_per_day >= 0 ? '+' : '−'}` +
        `${v(Math.abs(stats.trend.slope_per_day * 7))} par semaine sur ` +
        `${stats.trend.points} journées.`,
    );
  } else {
    lines.push('  Tendance : moins de 5 journées sur 30 jours, non calculée.');
  }
  if (entry.weeks && entry.weeks.length > 0) {
    lines.push(
      '  Par semaine (lundi) : ' +
        entry.weeks.map((w) => `${w.bucket_start} ${v(w.value)}`).join(' ; ') +
        '.',
    );
  }
  if (entry.days && entry.days.length > 0) {
    lines.push(
      '  Dernières journées : ' +
        entry.days.map((d) =>
          `${d.local_date} ${v(d.daily_value, d.sample_count > 1)}` +
          (d.sample_count > 1 ? ` (${d.sample_count} saisies)` : '')
        ).join(' ; ') +
        '.',
    );
  }
  return lines;
}

function overviewLine(
  { metric, item }: { metric: CatalogMetric; item: OverviewMetric },
): string {
  const head = `• ${label(metric)}`;
  if (!item.latest) return `${head} : aucune valeur enregistrée.`;
  const v = (n: number) => formatValue(metric, n, true);
  const recent = item.recent.value === null
    ? 'aucune journée sur les 30 derniers jours'
    : `30 derniers jours ${
      v(item.recent.value)
    } sur ${item.recent.days_count} journée(s)`;
  const previous = item.previous.value === null
    ? 'aucune journée sur les 30 jours précédents'
    : `30 jours précédents ${
      v(item.previous.value)
    } sur ${item.previous.days_count} journée(s)`;
  return `${head} : dernière journée ${item.latest.local_date} = ` +
    `${v(item.latest.value)} ; ${recent} ; ${previous}.`;
}

/** The data part of the prompt, cut at [MAX_CONTEXT_CHARS]. */
export function dataSection(context: CoachContext): string {
  const lines = [
    `Données EVOLUP (aujourd’hui : ${context.today}, fuseau ${context.timezone}) :`,
    'Indicateurs proposés par EVOLUP (l’utilisateur choisit ceux qu’il suit) : ' +
    context.catalog.filter((m) => m.is_active).map((m) => m.name).join(', ') +
    '.',
  ];
  if (context.unavailable) {
    lines.push(
      'Les données EVOLUP de l’utilisateur n’ont pas pu être lues : tu ne ' +
        'connais aucune de ses valeurs. Ne fais aucune supposition.',
    );
  } else if (!context.dataAccess) {
    lines.push(
      'L’utilisateur n’a pas autorisé Polomix à consulter ses données ' +
        'EVOLUP : tu ne connais aucune de ses valeurs. S’il demande une ' +
        'analyse, explique qu’il peut l’autoriser dans Paramètres → ' +
        'Confidentialité.',
    );
  } else {
    if (context.overview) {
      lines.push(
        context.overview.length === 0
          ? 'L’utilisateur ne suit encore aucun indicateur.'
          : 'Indicateurs suivis :',
      );
      for (const entry of context.overview) lines.push(overviewLine(entry));
    }
    for (const entry of context.metrics) lines.push(...metricBlock(entry));
    if (!context.overview && context.metrics.length === 0) {
      lines.push(
        'Aucune donnée n’a été transmise : le message ne porte sur aucun ' +
          'indicateur précis.',
      );
    }
  }
  let text = '';
  for (const line of lines) {
    if (text.length + line.length + 1 > MAX_CONTEXT_CHARS) {
      text += '(données tronquées)\n';
      break;
    }
    text += `${line}\n`;
  }
  return text.trimEnd();
}

export function buildPrompt(message: string, context: CoachContext): string {
  return `${RULES}\n\n${
    dataSection(context)
  }\n\nMessage de l’utilisateur :\n${message}`;
}
