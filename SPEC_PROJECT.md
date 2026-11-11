# EVOLUP — Cahier des charges vivant (V1 : plateforme de données)

Ce document est la référence fonctionnelle et technique d'EVOLUP. Il remplace
la vision « application sportive » (programme, séances, quêtes, score) : la
nouvelle vision a été transmise par le propriétaire le **2026-11-09** sous le
titre « Reconstruction de la V1 ». Les numéros de sections reprennent ceux de
ce document de reconstruction, auxquels le code renvoie (`SPEC_PROJECT.md §…`).

Légende : **[Validé]** décision du propriétaire · **[Décision technique]**
choix fait pendant l'implémentation, faute de précision, justifié ici ·
**[Constat]** état vérifié (date indiquée) · **[Ouvert]** à trancher par le
propriétaire, à ne pas inventer.

---

## 0. Règles permanentes — [Validé]

- Travailler dans le projet existant ; ne rien détruire (données, tables,
  migrations) sans raison technique démontrée.
- Aucune fonctionnalité V2 dans la V1 ; aucun bouton décoratif ; aucune donnée
  fictive dans les graphiques, tableaux ou réponses.
- Aucune clé secrète dans Flutter, un fichier public ou Git.
- Ne jamais supposer l'état distant de Supabase : le vérifier.
- Aucun déploiement en production (migrations, Edge Functions, secrets) sans
  vérification préalable **et** autorisation explicite du propriétaire.
- Une fonctionnalité n'est « terminée » que testée ; sinon le dire.

## 1. État du projet

Voir le rapport de reconstruction (fin de la session du 2026-11-09) et
§15 pour l'ordre de déploiement. **[Constat] 2026-11-09** : projet Supabase
« EVOLUP [App] » (`zhvhbtqpxorhrxfgeaen`, eu-west-1, PostgreSQL 17.11) ; une
seule migration distante (`20261021000000_create_athlete_profiles`) ;
`coach-chat` version 3 déployée, identique au code de la sauvegarde
`0c5c571`. **[Constat] 2026-11-09 (soir)** : sur accord du propriétaire, les
5 migrations `20261109…` sont appliquées (`db push`) et `coach-chat` v4 est
déployée (version 4) ; `athlete_profiles` inchangée (1 ligne, même
empreinte). Vérifié à distance : objets, droits, refus `anon`, fonctions de
calcul, réponses de la fonction sans session. **Non vérifié** : parcours avec
un compte réel (saisie, statistiques, Polomix).

## 2. Identité — [Validé]

EVOLUP est une plateforme personnelle de données : chaque utilisateur suit et
analyse son évolution dans les domaines qu'il choisit (sport, concentration,
discipline, sommeil, apprentissage, productivité, développement personnel…).
Le sport n'est qu'une catégorie. L'utilisateur choisit ce qu'il suit dans un
**catalogue contrôlé** par EVOLUP ; il ne crée pas d'indicateurs libres.

## 3. Navigation — [Validé]

Cinq sections, dans cet ordre, dans la barre flottante translucide existante :

| Section | Contenu V1 |
| --- | --- |
| **Vue d'ensemble** (accueil) | Résumé réel (indicateurs suivis, journées renseignées, saisies, date de début), favoris puis autres indicateurs avec dernière valeur et comparaison 30 jours / 30 jours précédents quand elle est fondée, raccourcis « Saisir » et « Statistiques », carte Polomix. **Pas de score global.** |
| **Mes données** | Recherche, filtres par catégorie, « Mes indicateurs » (saisie rapide, fiche), « Retirés de ma liste » (historique conservé, réactivation), « Catalogue EVOLUP » (description, unité, agrégation, record, « Suivre »). |
| **Statistiques** | Choix de l'indicateur, période (7 j, 30 j, 90 j, 1 an, Tout), regroupement (Auto, Jour, Semaine, Mois), chiffres clés, graphique, comparaison avec la période précédente, tendance, comparaison avec un second indicateur (graphiques alignés). |
| **Polomix** | Analyste personnel (§10). |
| **Paramètres** | Profil, préférences, confidentialité, connexions (V2), gestion des données, état et test de Polomix, déconnexion. |

Fiche d'un indicateur (depuis Mes données, la Vue d'ensemble ou Statistiques) :
nom, catégorie, statut, description, « Saisir une valeur », statistiques de la
période, liste des journées (correction, suppression), favori, retrait de la
liste, effacement de l'historique, suppression de l'indicateur.

Le bouton retour système ramène à la Vue d'ensemble. Pas de section Social.

## 4. Catalogue d'indicateurs

### 4.1–4.3 Principe et définition — [Validé]

Le catalogue (`metric_categories`, `metric_catalog`) appartient à EVOLUP.
Chaque indicateur a : identifiant permanent (entier explicite), `slug` unique,
nom, catégorie, description, type (`integer`, `decimal`, `duration`,
`score`), unité de stockage, précision de stockage, libellé d'unité, facteur
et décimales d'affichage, méthode d'agrégation, sens du record (ou aucun),
bornes, total quotidien maximal (sommes), configuration de formulaire
(`form_config`, ex. champs d'une durée), mots-clés, statut actif, ordre.

Unités de stockage : `repetition`, `page`, `task` (entiers), `meter`
(distances), `second` (durées, entiers), `point` (notes). L'app convertit à la
saisie et à l'affichage (`affiché = stocké / display_factor`), le serveur
vérifie dans l'unité de stockage.

### 4.4 Évolution — [Validé]

Ajouts par migration uniquement. Un indicateur suivi ne peut être ni supprimé
(clé étrangère), ni changer d'identifiant, de `slug`, d'unité, de précision ou
d'agrégation (déclencheur) : on le désactive (`is_active = false`) et on crée
une nouvelle définition.

### 4.5 Catalogue initial — [Décision technique]

Migration `20261109100200_seed_metric_catalog.sql`. Méthodes d'agrégation :
moyenne pour les mesures répétées de même nature (référence du propriétaire),
somme pour ce qui s'additionne sur une journée, minimum pour un meilleur temps.

| id | slug | Catégorie | Type · unité | Agrégation | Record |
| --- | --- | --- | --- | --- | --- |
| 1 | `tractions` | Sport | entier · rép. (0–500) | moyenne | meilleure série |
| 2 | `pompes` | Sport | entier · rép. (0–1000) | moyenne | meilleure série |
| 3 | `course_distance` | Sport | décimal · m, affiché en km (2 déc.) | somme (≤ 500 km/j) | plus longue course |
| 4 | `course_5km` | Sport | durée min/s (10 min–3 h) | minimum | meilleur temps (plus bas) |
| 5 | `concentration_duree` | Concentration | durée h/min (1 min–16 h) | somme (≤ 24 h/j) | — |
| 6 | `concentration_qualite` | Concentration | note 1–10 | moyenne | — |
| 7 | `discipline_quotidienne` | Discipline | note 1–10 | moyenne | — |
| 8 | `sommeil_duree` | Sommeil | durée h/min (1 min–24 h) | somme (nuit + sieste, ≤ 24 h/j) | — |
| 9 | `sommeil_qualite` | Sommeil | note 1–10 | moyenne | — |
| 10 | `lecture_duree` | Apprentissage | durée h/min | somme (≤ 24 h/j) | — |
| 11 | `pages_lues` | Apprentissage | entier · pages (1–2000) | somme | — |
| 12 | `etude_duree` | Apprentissage | durée h/min | somme (≤ 24 h/j) | — |
| 13 | `taches_accomplies` | Productivité | entier · tâches (1–500) | somme | — |
| 14 | `productivite_ressentie` | Productivité | note 1–10 | moyenne | — |
| 15 | `meditation_duree` | Développement personnel | durée h/min (1 min–12 h) | somme (≤ 24 h/j) | — |
| 16 | `humeur` | Développement personnel | note 1–10 | moyenne | — |

Un record n'est calculé que pour les performances (« meilleure saisie »).
**[Ouvert]** Liste, bornes et méthodes à confirmer par le propriétaire.

## 5. Saisie

### 5.1 Sources — [Validé]

Saisie manuelle uniquement, depuis Mes données, la fiche, la Vue d'ensemble
(« Saisir ») ou Polomix. Aucune collecte automatique en V1.

### 5.2–5.3 Parcours Polomix et contrat d'action

**[Constat] 2026-11-09** : l'API publique de Polomix ne renvoie qu'un texte
(`reply`), sans rôle système ni réponse structurée documentés ; un format
imposé au modèle (balises `<answer>`, v2) n'était suivi que 2 fois sur 3 et le
propriétaire l'a rejeté. **[Décision technique]** La demande de saisie est donc
reconnue de façon déterministe par l'Edge Function (`intent.ts`), à partir des
mots-clés du catalogue. Le texte de Polomix n'est jamais analysé ni filtré.

Contrat renvoyé à Flutter :

```json
{ "kind": "chat", "reply": null, "model": null,
  "action": { "type": "open_metric_form", "metric_slug": "tractions",
              "suggested_value": 8 },
  "context": { "metrics": [], "data_access": null } }
```

Règles appliquées et testées :

- Action seulement pour un message qui rapporte ou demande une saisie
  (« j'ai… », « je viens de… », « note… »), jamais pour une question (point
  d'interrogation ou mot interrogatif).
- `metric_slug` : un seul indicateur **actif** du catalogue ; ambiguïté
  (deux indicateurs possibles) → aucune action.
- `suggested_value` (unité de stockage) : seulement s'il y a exactement un
  nombre du bon genre (durée, distance avec unité, note, nombre) dans les
  bornes et la précision ; sinon `null` (formulaire vide).
- Un message de saisie sans question n'est pas envoyé à Polomix : la carte
  « Saisie préparée » est affichée comme venant d'EVOLUP, pas de Polomix. Le
  formulaire s'ouvre donc même si Polomix est indisponible.
- Flutter revérifie : action inconnue ignorée, `slug` mal formé rejeté,
  indicateur inactif ou inconnu → carte « indisponible », aucun formulaire ;
  indicateur non suivi ou retiré → proposition de l'ajouter / réactiver avant
  le formulaire ; valeur hors bornes → non préremplie.
- Le formulaire s'ouvre seul (petite transition) si la section Polomix est
  visible ; sinon la carte garde un bouton « Ouvrir le formulaire ».

### 5.4 Formulaire — [Validé]

Nom très visible en haut à gauche, catégorie, champ adapté (entier ; décimal
dans l'unité affichée ; heures/minutes/secondes ; notes autorisées), unité,
bornes, date de mesure (aujourd'hui sur l'horloge de l'appareil, modifiable
vers le passé, jamais le futur), explication de l'agrégation, « Valider ».
Chargement, confirmation (valeur du jour et nombre de saisies), message de
doublon, erreurs compréhensibles (une erreur réseau n'est jamais un succès),
protection contre les doubles envois, « Nouvelle saisie ». Le champ reste au-
dessus du clavier ; le clavier s'ouvre après la transition.

### 5.5 Validation obligatoire — [Validé]

Seul « Valider » écrit. Polomix ne crée, ne modifie ni ne supprime aucune
donnée (§10.3). Une valeur proposée reste modifiable et n'est pas enregistrée
avant validation.

## 6. Agrégation quotidienne et stockage

### 6.1–6.2 Une ligne par jour, calcul incrémental — [Validé]

Chaque saisie validée est fusionnée immédiatement dans l'unique ligne
(indicateur suivi, jour local) de `metric_daily_aggregates` : somme, nombre,
minimum, maximum, dernière valeur. Aucune saisie individuelle n'est conservée.
Exemple : 8 puis 10 → somme 18, 2 saisies, moyenne 9.

**[Décision technique]** Concurrence : la ligne est créée par
`INSERT … ON CONFLICT DO NOTHING`, sinon verrouillée par `SELECT … FOR UPDATE`
avant lecture et mise à jour (fonction `record_metric_entry`, une transaction).
Testé : 30 saisies simultanées sur 30 connexions, aucune perdue.

### 6.3 Méthode par indicateur — [Validé]

`average`, `sum`, `max`, `min`, `last`, définie dans le catalogue (§4.5).

### 6.4 Doublons et idempotence

- **[Validé]** Doublon = même utilisateur, même indicateur, même jour local,
  même valeur normalisée : il ne change ni la somme ni le nombre, et l'app
  l'annonce. Conséquence à connaître : deux vraies séries identiques le même
  jour (8 puis 8) ne comptent qu'une fois. **[Ouvert]** Le propriétaire
  confirmera si cette règle doit rester stricte.
- **[Décision technique]** Empreinte : un hachage de 64 bits (SHA-256 tronqué)
  par valeur distincte du jour, calculé en base sur la valeur arrondie à la
  précision de stockage sans zéros finaux (8 = 8,0 = 8,00), salé par
  l'indicateur suivi et le jour. Ce n'est pas la valeur elle-même, mais pour
  des valeurs peu nombreuses (0 à 500 répétitions) l'ensemble des valeurs
  distinctes d'un jour pourrait être retrouvé par essai : les empreintes sont
  donc protégées comme les données (RLS, et colonne non lisible par les
  clients).
- **[Décision technique]** Idempotence : chaque envoi porte une clé UUID
  générée par l'app, régénérée dès que la valeur ou la date change et
  conservée lors d'une nouvelle tentative. Une clé déjà fusionnée (200
  dernières par jour) renvoie `already_recorded` sans rien changer.
- Limite : 200 saisies par indicateur et par jour.

### 6.5 Correction — [Validé]

Les saisies fusionnées ne peuvent pas être modifiées une à une. Deux actions
explicites : « Corriger la valeur de la journée » remplace la journée par une
seule valeur (1 saisie, empreinte recalculée), « Supprimer cette journée ».
L'app le dit clairement.

### 6.6 Fuseaux horaires

- **[Validé]** Profil : fuseau IANA modifiable (`profiles.timezone`).
- **[Décision technique]** La date de mesure est un jour calendaire choisi
  dans le formulaire (horloge de l'appareil) ; chaque agrégat garde le fuseau
  IANA de l'appareil lors de la première saisie du jour (`timezone_name`). Le
  serveur refuse un jour postérieur à « aujourd'hui » dans ce fuseau et un
  fuseau inconnu de PostgreSQL. Le fuseau du profil sert à « aujourd'hui »
  dans la Vue d'ensemble et Polomix. Aucune conversion UTC ne touche la date
  (testé, y compris un jour de changement d'heure et UTC+14).
- Le fuseau du profil est initialisé avec celui de l'appareil à la première
  connexion (UTC s'il est illisible).

### 6.7 Regroupements — [Validé]

PostgreSQL regroupe par jour, semaine ISO (lundi) ou mois. Moyenne d'une
période = somme des sommes / somme des nombres (pondérée). Somme = total de
la période (et moyenne par journée enregistrée en plus). `auto` : jours
jusqu'à 120 jours, semaines jusqu'à deux ans, mois au-delà (≤ ~120 points).
Les agrégats quotidiens ne sont jamais supprimés pour gagner de la place. Pas
de TimescaleDB.

## 7. Modèle Supabase V1

### 7.1 `profiles` — [Validé]

`user_id` (PK → `auth.users`, cascade), `display_name` (1–60, facultatif),
`timezone` (IANA vérifié par déclencheur), `theme_palette` (`gold`,
`black_white`, `blue`, `violet` ; défaut `blue`), `theme_mode` (`dark`,
`light` ; défaut `dark`), `coach_data_access` (défaut `false`), `created_at`,
`updated_at`. Créé par l'app à la première connexion.

`athlete_profiles` (ancien questionnaire sportif) est **conservée intacte**
(1 ligne au 2026-11-09) mais n'est plus lue.

### 7.2 `metric_categories` · 7.3 `metric_catalog`

Voir §4. Lecture par tout utilisateur connecté (y compris les indicateurs
retirés, pour afficher leur historique) ; aucune écriture par l'API.

### 7.4 `user_metrics`

`id`, `user_id`, `metric_catalog_id`, `is_active`, `is_favorite`,
`sort_order`, `added_at`, `updated_at` ; unique (`user_id`,
`metric_catalog_id`) ; `user_id` et `metric_catalog_id` non modifiables.
Désactiver conserve l'historique ; supprimer efface l'historique (action
explicite, confirmée).

### 7.5 `metric_daily_aggregates`

`id`, `user_id`, `user_metric_id`, `local_date` (≥ 1900-01-01),
`timezone_name`, `sample_count` (1–200), `value_sum`, `value_min`,
`value_max`, `value_last`, `entry_fingerprints` (bigint[]), `request_keys`
(uuid[], ≤ 200), `created_at`, `updated_at`. Unique (`user_metric_id`,
`local_date`). Clé étrangère composite (`user_metric_id`, `user_id`) →
`user_metrics (id, user_id)` : impossible d'attacher un agrégat à l'indicateur
d'un autre compte. Contrôle de cohérence (min ≤ dernière ≤ max, somme entre
min×n et max×n, une empreinte par saisie). Vue `metric_daily_values`
(`security_invoker`) : les colonnes utiles plus `daily_value`, sans empreintes.

### 7.6 Conversations Polomix — [Constat]

Aucune table de conversation n'existait ; la conversation reste temporaire
(non enregistrée). Aucune table d'analyses persistantes n'est créée.

## 8. Fonctions PostgreSQL

### 8.1 Écritures (`SECURITY DEFINER`, `search_path` vide)

- `record_metric_entry(p_user_metric_id, p_value, p_unit, p_local_date,
  p_timezone, p_idempotency_key)` → `{status, aggregate}` ; `status` =
  `recorded`, `duplicate` ou `already_recorded`.
- `correct_metric_day(p_user_metric_id, p_local_date, p_value, p_unit)` →
  `{status: "corrected", aggregate}`.

**[Décision technique]** Pourquoi `SECURITY DEFINER` : les clients n'ont aucun
droit INSERT/UPDATE sur les agrégats ; sinon ils pourraient écrire des
compteurs ou empreintes falsifiés et contourner validation et doublons. Les
fonctions vérifient `auth.uid()`, l'appartenance de l'indicateur, son statut,
l'unité, la valeur, les bornes, la date et le fuseau ; noms entièrement
qualifiés ; EXECUTE réservé à `authenticated`. Elles refusent toute requête
portant l'en-tête `x-evolup-actor: polomix` (défense en profondeur).

### 8.2 Lectures (`SECURITY INVOKER`, RLS appliquée)

`get_overview()`, `get_metric_history(id, from, to, bucket)`,
`get_metric_statistics(id, from, to)` (valeur de la période, moyenne par
journée pour les sommes, record, dernière journée, tendance par moindres
carrés à partir de 5 journées), `compare_metric_periods(id, a…, b…)`
(comparable à partir de 3 journées de chaque côté), `list_timezones()`.
Index : unique (`user_metric_id`, `local_date`), (`user_id`, `local_date`).

### 8.3 Codes d'erreur (message des exceptions)

SQLSTATE `42501` : `not_authenticated`, `coach_cannot_write`. SQLSTATE
`22023` : `missing_parameter`, `metric_not_tracked`, `metric_not_active`,
`metric_retired`, `unit_mismatch`, `value_invalid`, `value_precision`,
`value_out_of_range`, `invalid_timezone`, `date_too_old`, `date_in_future`,
`daily_entry_limit`, `daily_sum_exceeded`, `day_not_found`, `invalid_period`,
`invalid_bucket`, `too_many_points`. SQLSTATE `55000` (migrations) :
`metric_identity_is_permanent`, `metric_storage_is_permanent_once_tracked`.
L'app les traduit dans `lib/data/data_error.dart`.

## 9. Sécurité et RLS — [Validé]

RLS sur toutes les tables de `public`. Données privées (`profiles`,
`user_metrics`, `metric_daily_aggregates`) : politiques distinctes par
opération, `auth.uid() = user_id`. Agrégats : SELECT et DELETE seulement ;
INSERT/UPDATE ni droit ni politique (fonctions §8.1). Colonnes d'empreintes et
de clés non lisibles. Catalogue : SELECT pour `authenticated`, aucune
écriture. `anon` : aucun accès ; `service_role` : aucun droit (comme
`athlete_profiles`). Schéma `private` (non exposé par l'API) pour les fonctions
internes. Testé à deux identités, en anonyme et en `service_role` (§17.5).

## 10. Polomix

### 10.1 Architecture

Flutter → Edge Function `coach-chat` (session vérifiée par `getClaims`) →
lecture des données **avec la session de l'utilisateur** (RLS) → Polomix
(`POST /api/v1/chat`, modèle `chatix-25`, secret `POLOMIX_API_KEY`) → texte
renvoyé tel quel. Requêtes `status` (secret présent ?) et `probe` (test réel
de compatibilité) pour les Paramètres.

### 10.2 Contexte transmis

- **[Décision technique]** Consentement : `profiles.coach_data_access`, désactivé
  par défaut (données envoyées à un service tiers) ; bannière dans Polomix et
  interrupteur dans Paramètres → Confidentialité.
- Avec consentement : seulement les indicateurs que le message nomme
  (mots-clés, noms, catégories ; 3 au plus) : 30 derniers jours, record,
  tendance, 12 semaines, 7 dernières journées ; pour une question générale
  (bilan, évolution…), un résumé de chaque indicateur suivi. Rien d'autre,
  ni nom ni e-mail. Partie données limitée à 3 500 caractères.
- Consignes placées avant le message (l'API n'a pas de rôle système) :
  n'utiliser que ces données, ne rien inventer, ne pas prétendre enregistrer,
  corrélation ≠ causalité, signaler les limites.
- L'app affiche « Données consultées : … » sous la réponse.

### 10.3 Droits — [Validé]

Polomix consulte et analyse ; il ne peut ni enregistrer, ni modifier, ni
supprimer, ni toucher au catalogue. Garanti par : aucun code d'écriture dans
la fonction (test statique `data_test.ts`), session de l'utilisateur (jamais
`service_role`), refus en base de l'en-tête `x-evolup-actor: polomix`.

### 10.4 Indisponibilité — [Validé]

Chat en erreur explicite, jamais de fausse réponse ; formulaires,
statistiques et données restent utilisables ; état réel et test de
compatibilité dans Paramètres → Polomix.

## 11. Graphiques et analyses — [Validé]

Graphique générique (`CustomPainter`) construit depuis la définition :
barres pour les sommes, ligne et points sinon, unités de l'indicateur, valeur
exacte au toucher ou au survol, résumé pour les lecteurs d'écran. Aucun
lissage ni interpolation. Pas de record sans sens du record ; pas de tendance
avant 5 journées ; pas de comparaison avant 3 journées par période ; un seul
point → « pas encore d'évolution ». Comparaison de deux indicateurs : deux
graphiques sur les mêmes jours, avec l'avertissement « ne prouvent pas que
l'un cause l'autre ».

## 12. Design — [Validé]

Identité premium sombre conservée (fond, halos, grille de points, cartes en
verre). Palettes Gold, Black & White, Blue, Violet ; mode sombre par défaut,
mode clair disponible ; système central `EvolupColors` (ThemeExtension),
aucune couleur figée dans les pages. **[Décision technique]** Palette par défaut
Blue (= l'identité nuit actuelle). Les écrans de connexion gardent toujours
l'identité nuit (décision 7 du journal). Logo dans un seul fichier
(`lib/app/evolup_logo.dart`). Animations discrètes, coupées si l'appareil le
demande. Contraste vérifié par test pour chaque palette et mode. Priorités :
Android, Web, iOS.

## 13. Retiré de la V1 — [Validé]

Programme sportif, planification, déroulement de séance, catalogue
d'exercices, quêtes, EXP, niveaux, score sur 100, variantes d'exercices. Le
questionnaire sportif initial (ancien §2) et l'ancien accueil sont retirés du
code (récupérables dans Git, commit `0c5c571`) ; la table `athlete_profiles`
et sa migration restent.

## 14. Reporté en V2 — [Validé]

Montres, Health Connect, synchronisation, services tiers, API de collecte,
import de fichiers, social. Paramètres → Connexions l'annonce sans rien
simuler.

## 15. Migrations et déploiement

Migrations versionnées dans `supabase/migrations/` ; testées sur PostgreSQL
17.11 local (`supabase/tests/db`, sans Docker) ; vérifiées par
`npx supabase db push --linked --dry-run`. Ordre de mise en production, **sur
accord du propriétaire** : (1) migrations, (2) redéploiement de `coach-chat`,
(3) application. Étapes (1) et (2) faites le 2026-11-09 ; (3) à faire. Jamais de `reset` distant ni de `config push`. Détail dans
le README.

## 16. Organisation du code — [Validé]

`lib/data` (modèles, conversions, dépôts Supabase), `lib/app` (démarrage,
session, navigation, widgets partagés, thèmes, formats), `lib/features/*`
(pages et leurs contrôleurs), `lib/coach` (client Polomix). Voir `CLAUDE.md`.

## 17. Tests

- Base (`supabase/tests/db`, 46 tests) : agrégation, doublons, idempotence,
  concurrence, dates et fuseaux, regroupements pondérés, statistiques,
  comparaisons, RLS à deux identités, anonyme, catalogue, durcissement.
- Edge Function (Deno, 43 tests) : contrat, sessions, contexte pertinent,
  consentement, intention de saisie, actions invalides, panne Polomix, état,
  test de compatibilité, absence d'écriture.
- Flutter (126 tests) : navigation, catalogue, formulaire, Polomix,
  statistiques, paramètres, thèmes, connexion.

## 18. Connexion et compte — [Validé] (guide de construction #1)

Écran de connexion inchangé : fond nuit, halos, grille de points, logo en
dégradé au-dessus de « Login », carte en verre ; « Continuer » ne fait que se
connecter, « Créer un compte » est une action séparée suivie d'un code
e-mail (8 caractères minimum), messages neutres ne révélant pas l'existence
d'un compte, récupération par lien (PKCE), Google et Apple actifs seulement
s'ils sont configurés dans Supabase. Détails historiques : version précédente
de ce document dans Git (`0c5c571`).

## 19. Journal des décisions

| Date | Décision | Source |
| --- | --- | --- |
| 2026-10-23 → 10-25 | Écran de connexion, OAuth préparé, questionnaire, barre flottante, Polomix v1 → v3 (voir l'historique Git de ce document). | Propriétaire |
| 2026-11-09 | Nouvelle vision : plateforme personnelle de données ; 5 sections ; catalogue contrôlé ; agrégation quotidienne ; Polomix analyste ; retrait programme/séances/quêtes/EXP/score ; V2 : connexions, import, social. | Propriétaire |
| 2026-11-09 | Palettes Gold, Black & White, Blue, Violet et mode clair réintroduits (sombre par défaut). | Propriétaire |
| 2026-11-09 | Saisie reconnue par l'Edge Function (pas de format imposé au modèle) ; texte de Polomix inchangé. | Décision technique |
| 2026-11-09 | Accès de Polomix aux données sur consentement, désactivé par défaut. | Décision technique |
| 2026-11-09 | Écritures par deux fonctions `SECURITY DEFINER` ; empreintes de 64 bits ; clé d'idempotence client. | Décision technique |
| 2026-11-09 | Palette par défaut Blue ; connexion toujours en identité nuit. | Décision technique |
| 2026-11-09 | Migrations `20261109…` appliquées et `coach-chat` v4 déployée. | Propriétaire |
| 2026-11-09 | Polomix sans dépendance au port 5000 : origines locales (loopback tous ports, réseau privé avec port) + origines `https://` de `COACH_ALLOWED_ORIGINS` ; pas de joker ; session toujours exigée (fonction version 5). | Propriétaire |

## 20. Questions ouvertes — [Ouvert]

1. Doublon strict (§6.4) : deux séries identiques le même jour ne comptent
   qu'une fois. À confirmer ou assouplir.
2. Catalogue initial (§4.5) : liste, bornes, méthodes, records.
3. Consentement Polomix désactivé par défaut : à confirmer.
4. Suppression du compte depuis l'app (nécessite une Edge Function avec la
   clé `service_role`) : non faite.
5. Que faire de `athlete_profiles` (conserver, exporter, supprimer) ?
6. Logo définitif ; identifiant d'application (`com.example.my_training`).
7. Replit est-il encore utilisé ? (plancher Flutter 3.32 / Dart 3.8 conservé.)
