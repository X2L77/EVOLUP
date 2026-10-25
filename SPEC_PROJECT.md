# EVOLUP — Cahier des charges vivant

Ce document rassemble les exigences fournies par le propriétaire du projet et
les décisions validées. Il est construit progressivement.

**Statut global : INCOMPLET.** Seul le « Guide de construction #1 »
(sections 0 et 1) a été reçu. Le second cahier des charges, le « cahier des
charges initial » auquel le guide fait référence et la capture de référence
visuelle n'ont pas été transmis. Toute fonctionnalité seulement nommée ici
n'est **pas** spécifiée et ne doit pas être implémentée avant d'avoir été
définie avec le propriétaire.

Légende :

- **[Validé]** : exigence écrite dans le guide ou confirmée par le propriétaire.
- **[Ouvert]** : décision non prise. Ne pas inventer de réponse.
- **[Constat]** : état vérifié du code ou de Supabase (à la date indiquée).

Règle de périmètre (propriétaire, 2026-10-23) : **ne coder que ce qui est noté
dans le guide de construction.**

---

## 0. Priorités et règles de développement

### 0.1 Objectif — [Validé]

- Application sportive fonctionnelle : Flutter, Supabase, coach IA personnalisé.
- Une vraie application, pas une maquette : boutons, formulaires, navigation,
  données enregistrées, calculs et fonctionnalités doivent réellement fonctionner.
- Le développement suit le parcours réel de l'utilisateur, de la première
  ouverture à l'usage quotidien.
- Le cahier des charges est construit progressivement ; les décisions confirmées
  sont conservées puis intégrées dans une version finale destinée à l'IA de
  développement.

### 0.2 Périmètre V1

[Validé] Priorité absolue : une V1 cohérente, fonctionnelle, testable et
maintenable. Les fonctionnalités suivantes sont **conservées dans la V1** :

| Fonctionnalité | Statut de la spécification |
| --- | --- |
| Inscription, connexion | E-mail spécifié et implémenté (section 1) ; Google/Apple [Ouvert] |
| Gestion du profil | Profil du questionnaire consultable et modifiable (section 2) ; le reste [Ouvert] |
| Questionnaire sportif et personnalisation des objectifs | Spécifié et implémenté (section 2) |
| Choix des préférences visuelles | Reporté en V1.1.0 |
| Programme sportif personnalisé et sa validation | [Ouvert] — nommée seulement |
| Coach IA | Règles générales en 0.6 ; détail [Ouvert] |
| Suivi des séances, enregistrement des performances | [Ouvert] — nommée seulement |
| Fiches d'exercices, records personnels, historiques | [Ouvert] — nommée seulement |
| Progression entre les variantes d'un exercice | [Ouvert] — nommée seulement |
| Score global, statistiques, indicateurs de récupération | [Ouvert] — nommée seulement |
| Quêtes quotidiennes, EXP, niveaux | [Ouvert] — nommée seulement |
| Paramètres, conservation des données utilisateur | [Ouvert] — nommée seulement |

[Validé] Chaque fonctionnalité sera définie précisément avant son
implémentation, puis développée en respectant ses dépendances.

[Validé] **Hors V1** : modèles corporels 3D, véritables fonctionnalités
sociales, dashboard ordinateur avancé.

### 0.3 Technologies et plateformes — [Validé]

- Frontend : Flutter.
- Backend : Supabase (Auth, PostgreSQL, politiques RLS).
- Fonctions serveur : Supabase Edge Functions si nécessaire, notamment pour
  sécuriser les appels au coach IA.
- Plateformes prioritaires : Android, Web, iOS.
- Compatibilité future : architecture permettant d'envisager Windows et macOS.
- Le Web reste responsive et utilisable sur ordinateur (pas de dashboard dédié
  en V1).

### 0.4 Règles générales de développement — [Validé]

- Analyser le code existant avant de le modifier ; ne pas réécrire ce qui
  fonctionne.
- Code modulaire : interface, logique métier, données, calculs et appels réseau
  clairement séparés ; plusieurs fichiers si cela aide la lisibilité.
- Jamais de bouton décoratif ni de donnée fictive à la place d'une fonctionnalité.
- Données à conserver enregistrées durablement, y compris après déconnexion /
  reconnexion.
- États de chargement, erreurs compréhensibles, validations, écrans vides,
  problèmes réseau.
- Interface adaptée aux tailles d'écran ; le clavier ne bloque pas les formulaires.
- Ne jamais inventer de performances sportives, de mesures réelles ou de
  capacités d'intégration non vérifiées.
- Documenter les décisions techniques importantes et les manipulations qui
  demandent l'intervention du propriétaire.
- Tenir `README.md` à jour.
- Tester au fur et à mesure : compiler ne suffit pas pour déclarer une
  fonctionnalité terminée.

### 0.5 Sécurité et données — [Validé]

- Un utilisateur n'accède qu'à ses propres données privées.
- Politiques RLS configurées **et testées** sur les tables concernées.
- Aucune clé API secrète dans le code Flutter, le navigateur, un dépôt Git ou un
  document public.
- Les appels **Polomix** nécessitant une clé privée passent par un environnement
  serveur sécurisé.
- Opérations sensibles validées côté serveur.
- Données personnelles limitées au nécessaire.
- Calculs, scores et récompenses : règles explicites, reproductibles et testables.

### 0.6 Coach IA — [Validé]

- L'intégration de l'IA ne bloque pas le reste de la V1.
- Si l'IA n'est pas connectée ou sa compatibilité non vérifiée : afficher « N/A »
  ou un état d'indisponibilité explicite, jamais un résultat inventé.
- Disponibilité de l'IA et résultat des tests de compatibilité consultables dans
  les Paramètres.
- Les propositions importantes de modification du programme sont présentées à
  l'utilisateur avant application. Une réponse textuelle du coach n'est pas une
  modification enregistrée.

### 0.7 Méthode de conception conjointe — [Validé]

- Le propriétaire prend les décisions fonctionnelles et visuelles.
- L'assistant pose les questions nécessaires dans l'ordre du parcours utilisateur.
- Les questions à choix proposent toujours « Autre / réponse personnalisée ».
- Les réponses validées sont conservées ici ; les points définis ne sont pas
  redemandés sans raison ; les décisions non prises restent marquées [Ouvert].
- La direction artistique est précisée régulièrement, avec références visuelles.
- Aucune proposition non validée n'est traitée comme exigence définitive.
- Le cahier des charges final sera rédigé après la définition du parcours et des
  fonctionnalités.

---

## 1. Premier lancement et écran de connexion

### 1.1 Concept — [Validé]

Premier écran à l'ouverture : connexion / authentification avec l'identité
visuelle d'EVOLUP. Premium, minimaliste, élégant ; interface sombre ; carte
centrale travaillée ; hiérarchie visuelle claire.

[Constat] Aucune capture de référence n'est présente dans le projet ni dans la
conversation. L'écran suit uniquement les descriptions du guide (décision 10).

### 1.2 Arrière-plan — [Validé]

- Bleu nuit extrêmement foncé, proche du noir.
- Deux halos subtils et diffus : un bleu-violet, un cyan ou bleu-vert.
- Une grille de points (dot grid) discrète mais visible.
- Le fond ne doit pas devenir trop coloré ni détourner l'attention de la connexion.
- [Validé] L'écran de connexion garde toujours ce fond, quelle que soit la
  palette choisie par l'utilisateur ; aucun sélecteur de thème sur cet écran
  (décision 7). Depuis le report des thèmes en V1.1.0, cette DA s'applique à
  toute l'application.

### 1.3 Logo — [Validé]

- Flèche stylisée de progression : départ bas → monte vers le haut à droite →
  redescend partiellement → remonte vers le haut à droite (trajectoire finale
  ascendante). Inspirée de 📈 mais symbole propre à EVOLUP, pas l'emoji.
- Remplaçable facilement : un seul fichier, `lib/app/evolup_logo.dart`.
- Position : aligné à gauche, au-dessus du titre « Login » (décision 6).
- Couleur : dégradé bleu-violet → cyan (décision A, qui remplace le « noir »
  envisagé, illisible sur fond presque noir).
- [Ouvert] Proportions et épaisseur définitives (implémentation actuelle :
  44 px, trait arrondi), à valider sur rendu.

### 1.4 Titre — [Validé]

Texte « Login » juste au-dessus de la carte, aligné à gauche, simple et lisible.
Logo + titre ne doivent pas surcharger l'écran.

### 1.5 Carte d'authentification — [Validé]

- Élément principal de l'écran, en verre translucide « liquid glass » discret.
- Ordre : e-mail → mot de passe (icône afficher/masquer, décision 3) →
  « Mot de passe oublié ? » → bouton principal **« Continuer »** (décision 2)
  → lien **« Créer un compte »** toujours visible sous « Continuer »
  (décision B) → séparateur → boutons Google et Apple, **dans** la carte.
- Texte courant et bouton principal sobres et lisibles, sans effets lumineux.
- Animations discrètes et fluides, désactivées quand l'appareil demande de
  réduire les animations (décision C) : apparition de l'écran, transition vers
  l'étape code, états des boutons et chargements.

### 1.6 Authentification par e-mail — [Validé]

Contrainte réelle de Supabase Auth : il ne distingue pas « mot de passe
incorrect » et « compte inexistant » (même code `invalid_credentials`). Une
seule action ne peut donc pas décider entre connexion et création de façon
fiable. Le parcours retenu sépare deux actions explicites sur le même écran.

**Connexion — « Continuer »** : tente uniquement une connexion.

| Résultat Supabase | Interface | Inscription |
| --- | --- | --- |
| Succès | Session ouverte, l'application continue | Non |
| `invalid_credentials` | « Adresse e-mail ou mot de passe incorrect. » (même message que le compte existe ou non) | **Jamais** |
| `email_not_confirmed` | Message + bouton « Recevoir un code » (envoi seulement si l'utilisateur appuie) | Jamais |
| Réseau, délai dépassé | Message réseau | Jamais |
| Trop de tentatives | Message d'attente | Jamais |
| Autre | Message générique, jamais de faux succès | Jamais |

**Création — « Créer un compte »** (action volontaire) : mot de passe de
8 caractères minimum (décision 4) → `signUp` → étape code avec un message
neutre identique que l'adresse soit nouvelle ou déjà inscrite (décision 1).

**Étape code** : saisie du code reçu par e-mail, « Valider » (vérification
par Supabase via `verifyOTP`, qui ouvre la session seulement si le code est
valide), « Renvoyer le code » après 60 s, « Modifier l'adresse ».

**Récupération** : mécanisme existant conservé (décision 5) — lien envoyé par
e-mail, puis écran « Nouveau mot de passe ». Le client Flutter utilise le mode
PKCE : le lien doit être ouvert sur le même appareil et le même navigateur que
la demande.

**Google et Apple** (décision 8) : boutons toujours visibles. Un bouton ne
lance une connexion OAuth réelle que si le fournisseur est **activé dans
Supabase** (réglages publics lus par l'application) et si la plateforme reçoit
le retour (Web, Android, iOS). Sinon il affiche « Non configuré »,
« Indisponible » (réglages illisibles) ou « Non disponible ici », et un appui
explique pourquoi sans rien lancer. Annulation ou refus dans la fenêtre du
fournisseur : message sur l'écran de connexion, jamais de faux succès.
[Ouvert] Test réel de chaque fournisseur, plateforme par plateforme, après
configuration par le propriétaire.

### 1.7 Contraintes — [Validé]

- Conçu d'abord pour téléphone ; s'adapte aux autres tailles.
- Champs accessibles quand le clavier apparaît.
- Les actions de validation déclenchent réellement l'authentification.
- Erreurs compréhensibles ; ne jamais laisser croire qu'une connexion a réussi.
- Relié à Supabase Auth avec une configuration réellement vérifiée.
- Aucune donnée de connexion ni clé secrète exposée dans le frontend.

### 1.8 Décisions encore ouvertes — [Ouvert]

- Proportions et épaisseur définitives du logo.
- Couleur et style définitifs du bouton principal (implémentation actuelle :
  fond clair uni, texte sombre, sans effet lumineux) — à valider sur rendu.
- Fonctionnement de Google et Apple (première connexion, création de compte).

### 1.9 Supabase — [Validé]

- Configurer Supabase **en même temps** que le code.
- Le formulaire de connexion doit être utilisable dès la première version.
- Sans accès à Supabase : demander l'accès au propriétaire.

---

## 2. Questionnaire initial — [Validé] 2026-10-23

### 2.1 Parcours

1. Création de compte (ou connexion) → l'application vérifie la session.
2. Elle charge le profil de l'utilisateur (`public.athlete_profiles`). Une
   session seule ne signifie **pas** un profil complété.
3. Pas de profil → questionnaire. Profil existant → accueil (pas de nouveau
   questionnaire à la connexion suivante).
4. Réponses conservées pendant le parcours (retour arrière sans perte) et sur
   l'appareil, pour reprendre après fermeture de l'application.
5. Enregistrement dans Supabase **uniquement à la validation finale**, pour
   l'utilisateur de la session ; confirmation « Profil enregistré », puis
   bouton « Accéder à EVOLUP » vers l'accueil.
6. Le profil peut être modifié depuis l'accueil (« Modifier mon profil »).

### 2.2 Interface

- Une question par écran, avec explication courte si utile ; « Étape x sur n »
  (n s'adapte : 9 ou 10 selon l'étape matériel) et barre de progression animée.
- Bouton « Continuer » fixé en bas, au-dessus du clavier ; il refuse une
  réponse obligatoire invalide (message sous la question). Dernière étape :
  « Créer mon profil » (ou « Enregistrer » en modification).
- Retour à l'étape précédente sans perte de réponses.
- Animations discrètes : fondu + léger déplacement horizontal entre les
  questions, léger enfoncement du bouton, progression animée, chargement pendant
  l'enregistrement ; désactivées si l'appareil demande moins d'animations.
- Même DA que l'écran de connexion (fond, halos, dot grid, carte en verre).

### 2.3 Questions (dans l'ordre)

| # | Question | Règle |
| --- | --- | --- |
| 1 | Âge | Obligatoire, 15 à 120 ans |
| 2 | Taille | Obligatoire, 80 à 250 cm (une décimale) |
| 3 | Poids | Obligatoire, 25 à 350 kg (une décimale) |
| 4 | Séances par semaine | Obligatoire, **curseur vertical** de 2 à 7 |
| 5 | Jours d'entraînement | **Petits cercles** (Lu … Di) ; exactement autant de jours que de séances (donc au moins 2). Jours choisis = séances et quêtes ; autres jours = repos (aucune séance fictive créée) |
| 6 | Niveau | Obligatoire : Débutant, Intermédiaire, Avancé |
| 7 | Objectif principal | Obligatoire, un seul choix parmi les 6 objectifs ; précision facultative (200 caractères max) |
| 8 | Lieux d'entraînement | Obligatoire, un ou plusieurs : À domicile, Salle de sport, Street workout |
| 9 | Matériel à domicile | **Seulement si « À domicile »** ; au moins un choix, « Aucun matériel » exclut les autres ; effacé si « À domicile » est retiré |
| 10 | Durée d'une séance | Obligatoire : 30, 45, 60, 75 ou 90 minutes |

**Non demandé** : sports pratiqués, objectifs secondaires, contraintes ou
limitations physiques (pas de données de santé en V1), montre ou source de
données, couleurs et thèmes (reportés en V1.1.0).

### 2.4 Données

Table `public.athlete_profiles`, une ligne par utilisateur créée à la fin du
questionnaire. Les règles ci-dessus sont appliquées à la fois par
l'application (`lib/data/profile_rules.dart`) et par la base (contraintes de la
migration) ; un test vérifie qu'elles restent identiques. RLS : chaque
utilisateur connecté lit, crée et modifie uniquement sa propre ligne ; aucun
accès anonyme ; pas de suppression depuis l'application.

---

## 3. Questions ouvertes (à poser au propriétaire)

1. Transmettre le second cahier des charges et le « cahier des charges
   initial » s'ils existent.
2. « Polomix » : de quel service s'agit-il (fournisseur du coach IA ? autre) ?
3. Table distante `public.Profiles` : créée volontairement ? Peut-elle être
   supprimée ?
4. Comptes Apple Developer et Google Cloud, accès à un Mac, identifiant
   d'application définitif (remplaçant `com.example.my_training`).
5. Replit est-il encore utilisé ? (il fixe le plancher Flutter 3.32 / Dart 3.8)

---

## 4. État constaté du projet — [Constat] 2026-10-23

### Implémenté et vérifié localement (tests automatisés, sans Supabase)

- Écran de connexion conforme à la section 1 et parcours connexion / création
  / code / récupération.
- Google et Apple : lancement OAuth réel (`signInWithOAuth`), retour par la
  page Web ou le lien `evolup://auth-callback`, erreurs et annulations
  affichées sur l'écran de connexion. Chaque bouton n'est actif que si le
  fournisseur est activé dans Supabase (réglages publics lus au démarrage) et
  si la plateforme reçoit le retour OAuth (Web, Android, iOS).
- Questionnaire de la section 2, enregistrement final, confirmation, accueil
  et modification du profil ; brouillon local ; erreurs d'enregistrement.
- DA EVOLUP sur toute l'application ; sélecteur de palettes supprimé
  (V1.1.0).
- 55 tests automatisés réussis ; `flutter analyze` sans problème.

### Vérifié contre le projet Supabase réel (lecture seule, aucun compte créé)

- Connexion avec une adresse inexistante : `invalid_credentials`, message
  correct (test du 2026-10-23).
- Table de profil (2026-10-24, après migration) : sans session, l'API répond
  HTTP 401 (`42501`) ; requêtes simulées (transactions annulées, aucun
  compte) : un utilisateur connecté ne lit et n'écrit que sa propre ligne ;
  `anon` et `service_role` n'ont aucun accès ; contraintes actives (jour en
  double, âge 14, matériel sans domicile refusés).
- Réglages publics : e-mail activé, confirmation obligatoire, Google et Apple
  désactivés.

### Non testé

- Inscription réelle avec code (adresse de test et réglage du modèle
  d'e-mail nécessaires), lien de récupération, OAuth réel (fournisseurs non
  configurés), Android (aucun appareil ni émulateur), iOS (pas de dossier
  `ios/`, pas de Mac).

### Supabase

- Projet « EVOLUP [App] », ref `zhvhbtqpxorhrxfgeaen`, région eu-west-1.
- Non vérifiables avec les accès disponibles (le connecteur ne gère pas la
  configuration Auth, aucune CLI ni jeton) : modèle d'e-mail, longueur
  minimale du mot de passe, URL de redirection, SMTP. Réglages à faire par le
  propriétaire dans le tableau de bord (voir README).
- Schéma `public` : `public.athlete_profiles` (migration `20261021000000`
  **appliquée le 2026-10-24** avec le CLI Supabase) et `public.Profiles`
  (non versionnée, 0 ligne, RLS sans politique, inutilisée par l'app,
  inchangée).
- `public.rls_auto_enable()` : fonction du déclencheur d'événements
  `ensure_rls` (active RLS sur toute nouvelle table de `public`). Exécutable
  par `anon`/`authenticated` (alerte Supabase), risque faible. Correction
  recommandée, non appliquée : `revoke execute ... from public, anon,
  authenticated`.

---

## 5. Risques et dépendances identifiés

- Inscription de bout en bout non encore validée : dépend des réglages du
  tableau de bord (modèle d'e-mail avec `{{ .Token }}`), de la migration et
  d'une adresse de test.
- Service d'e-mail intégré de Supabase : limite horaire faible, envoi « au
  mieux » ; un SMTP personnalisé (fournisseur + domaine + DNS) est nécessaire
  avant d'ouvrir l'application à d'autres utilisateurs.
- iOS / Sign in with Apple : nécessite un Mac et un compte Apple Developer ;
  développement actuel sous Windows. Google : projet Google Cloud et
  identifiants OAuth.
- Effet « liquid glass » (`BackdropFilter`) : à vérifier sur un Android
  d'entrée de gamme (aucun appareil Android disponible sur le poste).
- La base ne vérifie pas l'absence de doublons dans les listes (jours, lieux,
  matériel) ; l'application n'en envoie jamais.
- Coach IA / Polomix : fournisseur non identifié ; ne doit pas bloquer la V1.
- Chaîne de dépendances probable (à confirmer quand les fonctionnalités seront
  spécifiées) : Auth → Profil / questionnaire → Programme (catalogue
  d'exercices et variantes) → Séances / performances → Records, historiques,
  statistiques → Score, EXP, quêtes, niveaux. Les jours d'entraînement du
  profil serviront aux quêtes et aux séances.

---

## 6. Journal des décisions

| Date | Décision | Source |
| --- | --- | --- |
| 2026-10-23 | Guide de construction #1 (sections 0 et 1) reçu et enregistré. | Propriétaire |
| 2026-10-23 | Le guide n'est pas forcément complet ; les éléments manquants restent ouverts. | Propriétaire |
| 2026-10-23 | Ne coder que ce qui est noté dans le guide de construction. | Propriétaire |
| 2026-10-23 | 1 — Identifiants incorrects : message clair, récupération proposée, sans révéler l'existence d'un compte. | Propriétaire |
| 2026-10-23 | 2 — Bouton principal « Continuer ». | Propriétaire |
| 2026-10-23 | 3 — Icône afficher/masquer le mot de passe. | Propriétaire |
| 2026-10-23 | 4 — Mot de passe : 8 caractères minimum à l'inscription. | Propriétaire |
| 2026-10-23 | 5 — Récupération : mécanisme existant par lien e-mail conservé. | Propriétaire |
| 2026-10-23 | 6 / A — Logo aligné à gauche au-dessus de « Login », dégradé bleu-violet → cyan. | Propriétaire |
| 2026-10-23 | 7 — Écran de connexion toujours bleu nuit avec dot grid ; pas de sélecteur de thème. | Propriétaire |
| 2026-10-23 | 8 — Google et Apple visibles mais indiqués indisponibles tant qu'ils ne sont pas configurés ; aucune simulation. | Propriétaire |
| 2026-10-23 | 9 — Migration `athlete_profiles` : SQL présenté, application seulement après accord explicite. | Propriétaire |
| 2026-10-23 | 10 — Pas de référence visuelle : suivre les descriptions du guide. | Propriétaire |
| 2026-10-23 | B — Lien « Créer un compte » toujours visible sous « Continuer ». | Propriétaire |
| 2026-10-23 | C — Animations discrètes, respectant la réduction des animations. | Propriétaire |
| 2026-10-23 | Un échec de connexion ne déclenche jamais d'inscription ; vérification de l'inscription par un vrai code Supabase. | Propriétaire |
| 2026-10-23 | Autorisation : configuration Auth e-mail dans Supabase uniquement ; schéma, données, fonctions, RLS, utilisateurs de test, Google/Apple et identifiant Android exigent un accord explicite. | Propriétaire |
| 2026-10-23 | Questionnaire : âge, taille, poids obligatoires ; pas de sports pratiqués ni d'objectifs secondaires ; matériel seulement à domicile ; au moins 2 jours. | Propriétaire |
| 2026-10-23 | Séances par semaine sur un curseur vertical (2 à 7), puis exactement autant de jours dans des petits cercles. | Propriétaire |
| 2026-10-23 | Contraintes / limitations physiques non demandées en V1. | Propriétaire |
| 2026-10-23 | Âge minimum : 15 ans. | Propriétaire |
| 2026-10-23 | Couleurs et thèmes reportés en V1.1.0 : DA EVOLUP sur toute l'application, sélecteur de palettes retiré, aucune colonne de thème. | Propriétaire |
| 2026-10-23 | Préparer OAuth Google et Apple (code et Supabase) dans la limite des accès disponibles ; l'e-mail doit fonctionner indépendamment. | Propriétaire |
| 2026-10-23 | Schéma : autorisation de créer/modifier tables, colonnes, relations, index et RLS, avec plan et accord avant chaque migration ; aucune suppression sans accord. | Propriétaire |
| 2026-10-24 | Migration `athlete_profiles` (contrainte anti-doublon des jours, aucun droit pour `service_role`) appliquée avec `npx supabase db push --linked`. | Propriétaire |
| 2026-10-25 | Intégration Polomix et fonctionnalités du coach IA mises en attente. | Propriétaire |
| 2026-10-25 | Barre de navigation flottante et translucide (verre de la carte de connexion), en bas : Coach IA (bulle avec « … ») · Home (maison, au centre) · Statistiques (trois barres, celle du milieu la plus haute). Coach IA et Statistiques : pages « Bientôt disponible », sans faux chat, appel d'API ni donnée. | Propriétaire |
| 2026-10-25 | Coach IA v1 : vrai chat dans l'onglet Coach IA, réponses de Polomix uniquement, via la fonction serveur Supabase `coach-chat` (clé `POLOMIX_API_KEY` côté serveur seulement) ; conversation temporaire non enregistrée ; aucune donnée personnelle ou sportive envoyée ; pas d'historique ni de table. Architecture prévue pour de futures tâches structurées validées par le serveur (contrat dans `supabase/functions/coach-chat/README.md`). | Propriétaire |
| 2026-10-25 | `coach-chat` déployée (version 1, `npx supabase functions deploy coach-chat --use-api`) avec le secret `POLOMIX_API_KEY` ; appels sans session refusés (401, vérifié) ; deux vrais échanges réussis depuis le S22. Constat : la réponse de Polomix peut contenir l'analyse du modèle avant la réponse. | Propriétaire |
| 2026-10-25 | `coach-chat` version 2 déployée : réponse finale demandée dans un bloc `<answer>`, seul ce bloc est affiché, sinon erreur propre. Observé sur le S22 : 2 réponses propres sur 3 questions ; la 3ᵉ refusée deux fois (`answer_missing`). Format non fiable : solution à décider **[Ouvert]**. | Propriétaire |
