-- Initial EVOLUP catalog (SPEC_PROJECT.md §4.5). Later versions add metrics
-- with new migrations following this pattern: explicit, never reused ids;
-- a metric that has data is retired (is_active = false), never deleted.
--
-- Aggregation of several entries on the same local day:
--   average  repeated measures of the same nature (owner's reference method):
--            tractions, pompes, self-rated scores;
--   sum      quantities that add up over a day: distance run, time spent
--            focusing, sleeping (night + naps), reading, studying,
--            meditating, pages read, tasks done;
--   min      best performance when lower is better: 5 km time.
-- Records exist only for performances: tractions, pompes (best set), distance
-- (longest run), 5 km time (fastest). Scores and durations have none.

insert into public.metric_categories (id, slug, name, description, sort_order)
values
  (1, 'sport', 'Sport', 'Performances physiques et entraînement.', 10),
  (2, 'concentration', 'Concentration',
    'Temps et qualité de travail concentré.', 20),
  (3, 'discipline', 'Discipline', 'Régularité et respect de vos engagements.', 30),
  (4, 'sommeil', 'Sommeil', 'Durée et qualité du sommeil.', 40),
  (5, 'apprentissage', 'Apprentissage', 'Lecture, étude et progression.', 50),
  (6, 'productivite', 'Productivité', 'Travail accompli et efficacité ressentie.', 60),
  (7, 'developpement_personnel', 'Développement personnel',
    'Bien-être, méditation et état d’esprit.', 70);

insert into public.metric_catalog (
  id, slug, category_id, name, description,
  value_kind, storage_unit, storage_scale, unit_label, display_factor,
  display_decimals, aggregation, record_direction,
  min_value, max_value, daily_sum_max, form_config, keywords, sort_order
)
values
  (1, 'tractions', 1, 'Tractions',
    'Nombre de répétitions d’une série de tractions.',
    'integer', 'repetition', 0, 'rép.', 1, 0, 'average', 'higher',
    0, 500, null, '{}', array['traction', 'tractions', 'pull-up', 'pull-ups',
    'pullup', 'pullups', 'chin-up', 'chin-ups'], 10),
  (2, 'pompes', 1, 'Pompes',
    'Nombre de répétitions d’une série de pompes.',
    'integer', 'repetition', 0, 'rép.', 1, 0, 'average', 'higher',
    0, 1000, null, '{}', array['pompe', 'pompes', 'push-up', 'push-ups',
    'pushup', 'pushups'], 20),
  (3, 'course_distance', 1, 'Course — distance',
    'Distance parcourue en courant. Plusieurs courses d’une même journée '
    'sont additionnées.',
    'decimal', 'meter', 0, 'km', 1000, 2, 'sum', 'higher',
    10, 300000, 500000, '{}', array['course', 'courses', 'couru', 'courir',
    'running', 'footing', 'jogging', 'distance'], 30),
  (4, 'course_5km', 1, 'Course — temps sur 5 km',
    'Temps réalisé sur 5 km. Le meilleur temps de la journée est retenu.',
    'duration', 'second', 0, 'temps', 1, 0, 'min', 'lower',
    600, 10800, null, '{"duration_fields": ["minutes", "seconds"]}',
    array['5 km', '5km', '5 kilometres', 'cinq kilometres'], 40),
  (5, 'concentration_duree', 2, 'Temps de concentration',
    'Temps de travail concentré. Les sessions d’une même journée sont '
    'additionnées.',
    'duration', 'second', 0, 'durée', 1, 0, 'sum', null,
    60, 57600, 86400, '{"duration_fields": ["hours", "minutes"]}',
    array['concentration', 'concentre', 'concentree', 'focus', 'deep work'],
    10),
  (6, 'concentration_qualite', 2, 'Qualité de concentration',
    'Note de 1 à 10 de votre capacité à rester concentré.',
    'score', 'point', 0, '/10', 1, 0, 'average', null,
    1, 10, null, '{}', array['qualite de concentration',
    'qualite de ma concentration'], 20),
  (7, 'discipline_quotidienne', 3, 'Discipline quotidienne',
    'Note de 1 à 10 du respect de vos engagements de la journée.',
    'score', 'point', 0, '/10', 1, 0, 'average', null,
    1, 10, null, '{}', array['discipline', 'regularite'], 10),
  (8, 'sommeil_duree', 4, 'Durée de sommeil',
    'Temps de sommeil. Une nuit et une sieste du même jour sont '
    'additionnées.',
    'duration', 'second', 0, 'durée', 1, 0, 'sum', null,
    60, 86400, 86400, '{"duration_fields": ["hours", "minutes"]}',
    array['sommeil', 'dormi', 'dormir', 'dors', 'sieste', 'nuit'], 10),
  (9, 'sommeil_qualite', 4, 'Qualité du sommeil',
    'Note de 1 à 10 de la qualité de votre sommeil.',
    'score', 'point', 0, '/10', 1, 0, 'average', null,
    1, 10, null, '{}', array['qualite du sommeil', 'qualite de sommeil',
    'qualite de mon sommeil'], 20),
  (10, 'lecture_duree', 5, 'Temps de lecture',
    'Temps passé à lire. Les sessions d’une même journée sont additionnées.',
    'duration', 'second', 0, 'durée', 1, 0, 'sum', null,
    60, 86400, 86400, '{"duration_fields": ["hours", "minutes"]}',
    array['lecture', 'lire', 'lu'], 10),
  (11, 'pages_lues', 5, 'Pages lues',
    'Nombre de pages lues dans la journée.',
    'integer', 'page', 0, 'pages', 1, 0, 'sum', null,
    1, 2000, 10000, '{}', array['page', 'pages'], 20),
  (12, 'etude_duree', 5, 'Temps d’étude',
    'Temps consacré à étudier ou à réviser. Les sessions d’une même journée '
    'sont additionnées.',
    'duration', 'second', 0, 'durée', 1, 0, 'sum', null,
    60, 86400, 86400, '{"duration_fields": ["hours", "minutes"]}',
    array['etude', 'etudie', 'etudier', 'revision', 'revisions', 'revise',
    'reviser'], 30),
  (13, 'taches_accomplies', 6, 'Tâches accomplies',
    'Nombre de tâches terminées dans la journée.',
    'integer', 'task', 0, 'tâches', 1, 0, 'sum', null,
    1, 500, 2000, '{}', array['tache', 'taches', 'to-do', 'todo'], 10),
  (14, 'productivite_ressentie', 6, 'Productivité ressentie',
    'Note de 1 à 10 de votre productivité de la journée.',
    'score', 'point', 0, '/10', 1, 0, 'average', null,
    1, 10, null, '{}', array['productivite', 'productif', 'productive'], 20),
  (15, 'meditation_duree', 7, 'Méditation',
    'Temps de méditation. Les séances d’une même journée sont additionnées.',
    'duration', 'second', 0, 'durée', 1, 0, 'sum', null,
    60, 43200, 86400, '{"duration_fields": ["hours", "minutes"]}',
    array['meditation', 'medite', 'mediter'], 10),
  (16, 'humeur', 7, 'Humeur',
    'Note de 1 à 10 de votre humeur générale de la journée.',
    'score', 'point', 0, '/10', 1, 0, 'average', null,
    1, 10, null, '{}', array['humeur', 'moral'], 20);
