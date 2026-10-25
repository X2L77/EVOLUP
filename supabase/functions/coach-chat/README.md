# Edge Function `coach-chat`

Chat du Coach IA : **Flutter → `coach-chat` → Polomix → `coach-chat` →
Flutter**. L'application n'appelle jamais Polomix directement et ne connaît pas
la clé.

## Protocole (v1)

`POST /functions/v1/coach-chat`, avec la session Supabase de l'utilisateur
(`Authorization: Bearer <access token>`, ajouté par `supabase_flutter`).

Requête : `{ "kind": "chat", "message": "<texte>" }`. Le message est nettoyé
(espaces de début et de fin) et limité à 2 000 caractères ; le corps est limité
à 16 Ko.

Envoi à Polomix (`answer_format.ts`) : une consigne fixe d'EVOLUP (répondre
comme dans un chat, réponse finale entre `<answer>` et `</answer>`, sans analyse
ni commentaire sur les consignes), puis le message de l'utilisateur, inchangé.
Seul le contenu du dernier bloc `<answer>` complet est renvoyé à l'application,
mot pour mot (espaces de début et de fin retirés). Une réponse sans ce bloc est
refusée (`coach_bad_response`) : elle n'est ni affichée brute ni découpée par
devinette.

Réponse :
`{ "kind": "chat", "reply": "<réponse de Polomix (bloc answer)>", "model":
"chatix-25" }`.

Erreur : `{ "error": { "code": "<code>", "message": "<texte court>" } }`.

| Code                                | HTTP | Cause                                                     |
| ----------------------------------- | ---- | --------------------------------------------------------- |
| `unauthorized`                      | 401  | Pas de session valide (utilisateur connecté, non anonyme) |
| `invalid_json`, `invalid_request`   | 400  | Corps illisible ou mal formé                              |
| `unsupported_kind`                  | 400  | `kind` autre que `chat` (tâches futures)                  |
| `empty_message`, `message_too_long` | 400  | Message vide ou > 2 000 caractères                        |
| `payload_too_large`                 | 413  | Corps > 16 Ko                                             |
| `origin_not_allowed`                | 403  | Origine Web non autorisée                                 |
| `method_not_allowed`                | 405  | Autre méthode que `POST`/`OPTIONS`                        |
| `rate_limited`                      | 429  | Trop d'appels (en-tête `Retry-After`)                     |
| `coach_not_configured`              | 503  | Secret `POLOMIX_API_KEY` absent                           |
| `coach_quota_reached`               | 503  | Polomix : 402/429 (offre ou débit)                        |
| `coach_unavailable`                 | 502  | Polomix : clé refusée, 5xx, réseau                        |
| `coach_rejected`                    | 502  | Polomix : 400/413/422                                     |
| `coach_timeout`                     | 504  | Pas de réponse en 30 s                                    |
| `coach_bad_response`                | 502  | Réponse 2xx sans `reply` exploitable ou sans `<answer>`   |

Les réponses d'erreur ne contiennent jamais la clé, le corps renvoyé par
Polomix, ni de détail interne.

## Sécurité

- **Session** : le contrôle JWT de la passerelle est désactivé pour cette
  fonction (`config.toml`) ; l'appelant est vérifié dans la fonction avec
  `auth.getClaims` (clés de signature JWT ES256 du projet, recommandation
  Supabase). Seuls `role = authenticated`, `sub` présent et non anonyme passent.
  La requête préliminaire CORS (`OPTIONS`) passe sans session ; un `POST` sans
  session est refusé.
- **Secret** : `POLOMIX_API_KEY`, lu à chaque appel depuis l'environnement
  serveur. Jamais dans Flutter, Git, les journaux ni les réponses.
- **Aucun accès à la base** et aucune clé `service_role` : la v1 n'envoie aucune
  donnée de profil à Polomix, seulement le message tapé.
- **CORS** : origines Web autorisées = `http://localhost:5000` par défaut, ou la
  liste du secret `COACH_ALLOWED_ORIGINS` (séparée par des virgules, par ex.
  l'adresse du site publié). Les applications mobiles n'envoient pas d'origine.
- **Appels excessifs** : 1 requête à la fois, 5 par minute et 30 par heure par
  utilisateur, **par instance** de la fonction (mémoire). C'est un frein, pas un
  quota fiable : les compteurs repartent à zéro au démarrage d'une instance et
  ne sont pas partagés. Un quota fiable demandera une table (`coach_usage`)
  écrite par la fonction : migration à valider séparément.
- **Journaux** : résultat, statut HTTP de Polomix, durée et, si le bloc
  `<answer>` manque, `detail: "answer_missing"` ; ni message, ni réponse, ni
  utilisateur, ni jeton.

## Polomix (documentation consultée le 2026-10-25)

Source : page « ApiDashboard » de https://polomix-ai.netlify.app (code public du
site) et appels sans clé valide.

- Endpoint simple utilisé : `POST /api/v1/chat`,
  `Authorization: Bearer
  pmx_…`, corps `{"message","model":"chatix-25"}`,
  réponse documentée `{"reply","tokens_used","model"}` (`tokens_used` montré
  comme une chaîne : les deux formes sont acceptées).
- Erreurs constatées : 401 `{"error":{"message","type":"authentication_error"}}`
  sans clé ou avec une clé invalide ; 404 `ROUTE_NOT_FOUND` sur une route
  inconnue.
- `POST /api/v1/chat/completions` (format OpenAI) n'est documenté qu'avec
  `"stream": true` (SSE terminé par `[DONE]`) : **non utilisé**. Rôle `system`,
  réponse sans streaming, historique : non documentés.
- Quotas affichés par le site : jetons par jour et par mois selon l'offre (8 000
  / jour et 240 000 / mois pour l'offre gratuite), 3 clés par compte.
- **Non vérifié** : forme brute complète d'une réponse réussie (jamais
  journalisée), codes renvoyés en cas de quota, taille maximale d'un message.

Constats du 2026-10-25 (fonction déployée, deux vrais échanges réussis en 4 s et
9 s) :

- À la question « Qui est ton créateur ? », le texte affiché (le champ `reply`,
  seulement nettoyé de ses espaces par la fonction et l'application) commençait
  par « User asks: … », « Context: The system prompt provides specific
  instructions… » et une analyse du respect de ces consignes, puis donnait la
  réponse. EVOLUP n'envoie aucune consigne système : celle dont parle le modèle
  est appliquée par Polomix, invisible et non configurable depuis l'endpoint
  simple.
- Le chat web de Polomix (code public, `Chat.tsx`) reçoit lui aussi un seul
  texte et le découpe dans le navigateur en « raisonnement » et « Réponse finale
  » en repérant des titres (« Raisonnement », « Analyse », « Réponse finale », «
  Final answer »…). Il envoie sa propre consigne `system` à un endpoint interne
  (`/api/chat/stream`), non documenté pour l'API publique.
- Ce que ces éléments ne permettent pas d'établir : s'il s'agit d'un
  raisonnement interne du modèle ou d'une mise en forme choisie par lui, et si
  l'API publique accepte un rôle `system`.

Conséquence : chaque message est envoyé seul, sans historique, précédé de la
consigne de format ci-dessus ; le coach ne garde pas le fil de la conversation.
Si le modèle ne respecte pas le bloc `<answer>`, l'utilisateur voit « La réponse
du coach est inutilisable. » avec « Réessayer » (taux mesurable dans les
journaux : `detail: "answer_missing"`).

Version 2 (bloc `<answer>`), déployée le 2026-10-25, observée sur le S22 : «
Bonjour » et « Qui est ton créateur » ont reçu une réponse propre, sans analyse
; « Explique moi la théorie des cordes » a échoué deux fois (`answer_missing`,
environ 4 s) : **le modèle ne respecte pas le format de façon fiable**. La
documentation de Polomix ne décrit aucun moyen de séparer l'analyse de la
réponse (ni champ dédié, ni consigne système, ni réglage du modèle).

## Tests locaux (sans clé)

Avec Deno (par exemple `npx -y deno@2.9.6`), depuis ce dossier :

```powershell
npx -y deno@2.9.6 fmt --check .
npx -y deno@2.9.6 lint .
npx -y deno@2.9.6 check *.ts
npx -y deno@2.9.6 test --no-prompt answer_format_test.ts handler_test.ts polomix_test.ts
```

Les tests remplacent Polomix et la vérification de session par des faux : aucun
appel réseau, aucune clé.

## Contrat futur : tâches structurées (non implémenté)

Objectif : permettre à EVOLUP de demander à l'IA une tâche précise pour un
utilisateur (ex. un calcul de score) sans jamais lui donner un accès libre aux
données.

1. **Demande** de l'application :
   `{ "kind": "task", "task": "<id>",
   "input": { … } }`. Aujourd'hui refusée
   (`unsupported_kind`).
2. **Registre serveur** (dans cette fonction, versionné et testé) : pour chaque
   `task`, la liste fermée des champs autorisés (ex. `athlete_profiles.level`,
   `athlete_profiles.weekly_sessions`), le schéma du résultat attendu et sa
   version. Une tâche absente du registre est refusée.
3. **Besoins de données** : si l'IA est consultée pour savoir quelles données
   sont utiles, elle répond `{ "required_fields": [ … ] }`. Le serveur ne garde
   que l'intersection avec la liste autorisée de la tâche ; tout autre champ est
   ignoré et journalisé (nom seulement). L'IA ne formule jamais de requête, de
   table ou de filtre.
4. **Lecture** : le serveur lit ces champs avec le client Supabase **de
   l'utilisateur** (RLS appliqué, jamais `service_role`) et n'envoie que le
   strict nécessaire, sans identifiant ni e-mail.
5. **Résultat** : l'IA doit répondre en JSON ; le serveur le valide contre le
   schéma de la tâche (types, bornes, champs connus) et refuse le reste
   (`coach_bad_response`). Réponse à l'application :
   `{ "kind": "task",
   "task": "<id>", "version": 1, "status": "proposal", "result": { … } }`,
   validée une seconde fois par Flutter.
6. **Effets** : un résultat n'écrit rien par lui-même. Toute modification
   (programme, objectifs…) est une proposition présentée à l'utilisateur, puis
   appliquée par du code déterministe après son accord (SPEC_PROJECT.md §0.6).

Avant d'implémenter une tâche : définir ses règles métier et sa formule
(reproductibles et testables), le consentement à l'envoi de données, la
persistance éventuelle (migration), et les tests de validation.
