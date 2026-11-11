# Edge Function `coach-chat` — Polomix, l'analyste d'EVOLUP

**Flutter → `coach-chat` → (données de l'utilisateur, en lecture) → Polomix →
`coach-chat` → Flutter.** L'application n'appelle jamais Polomix directement et
ne connaît pas la clé. « v4 » (2026-11-09), **déployée le 2026-11-09** (version
4 de la fonction) ; non encore essayée avec une vraie session.

## Protocole

`POST /functions/v1/coach-chat`, avec la session Supabase de l'utilisateur
(`Authorization: Bearer <access token>`, ajouté par `supabase_flutter`). Corps
limité à 16 Ko.

| Requête                                              | Réponse 200                                                                                                                                          |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{"kind":"chat","message":"…"}` (≤ 2 000 caractères) | `{"kind":"chat","reply":"…"\|null,"model":"chatix-25"\|null,"action":{…}\|null,"context":{"metrics":["tractions"],"data_access":true\|false\|null}}` |
| `{"kind":"status"}`                                  | `{"kind":"status","configured":true,"model":"chatix-25"}` (aucun appel à Polomix)                                                                    |
| `{"kind":"probe"}`                                   | `{"kind":"probe","ok":…,"model":…,"latency_ms":…,"checks":{"secret","reachable","authorized","contract"},"error":code\|null}` (un court appel réel)  |

`action` (seule action existante) :
`{"type":"open_metric_form","metric_slug":"tractions","suggested_value":8}`,
valeur dans l'unité de stockage du catalogue ou `null`.

`context.metrics` : les indicateurs dont les données ont été envoyées à Polomix
(affichés sous la réponse). `data_access` : consentement de l'utilisateur
(`null` si inconnu, par exemple données illisibles).

Erreur : `{ "error": { "code": "<code>", "message": "<texte court>" } }`.

| Code                                | HTTP | Cause                                              |
| ----------------------------------- | ---- | -------------------------------------------------- |
| `unauthorized`                      | 401  | Pas de session valide (connectée, non anonyme)     |
| `invalid_json`, `invalid_request`   | 400  | Corps illisible ou mal formé                       |
| `unsupported_kind`                  | 400  | `kind` inconnu                                     |
| `empty_message`, `message_too_long` | 400  | Message vide ou > 2 000 caractères                 |
| `payload_too_large`                 | 413  | Corps > 16 Ko                                      |
| `origin_not_allowed`                | 403  | Origine Web non autorisée                          |
| `method_not_allowed`                | 405  | Autre méthode que `POST`/`OPTIONS`                 |
| `rate_limited`                      | 429  | Trop d'appels (en-tête `Retry-After`)              |
| `coach_not_configured`              | 503  | Secret `POLOMIX_API_KEY` absent                    |
| `coach_quota_reached`               | 503  | Polomix : 402/429                                  |
| `coach_unavailable`                 | 502  | Polomix : clé refusée, 5xx, réseau                 |
| `coach_rejected`                    | 502  | Polomix : 400/413/422                              |
| `coach_timeout`                     | 504  | Pas de réponse en 30 s                             |
| `coach_bad_response`                | 502  | 2xx non JSON, avec `error`, ou `reply` absent/vide |

## Déroulement d'un message

1. Session vérifiée (`auth.getClaims`), puis limite d'appels.
2. Catalogue lu avec la session de l'utilisateur (`data.ts`).
3. **Saisie ?** (`intent.ts`, déterministe) : un message qui rapporte ou demande
   une saisie (« Je viens de faire 8 tractions. ») et n'est pas une question
   renvoie l'action **sans appeler Polomix**. Indicateur actif unique, valeur
   seulement si elle est certaine (un seul nombre du bon genre, dans les
   bornes). Ambiguïté, indicateur retiré ou inconnu : pas d'action. Le
   formulaire s'ouvre donc même si Polomix est en panne.
4. Sinon : profil lu (fuseau, consentement `coach_data_access`). Avec
   consentement, seules les données des indicateurs nommés par le message (3 au
   plus : 30 derniers jours, record, tendance, 12 semaines, 7 dernières
   journées), ou un résumé de tous les indicateurs suivis pour une question
   générale (`context.ts`, partie données ≤ 3 500 caractères). Sans consentement
   : aucune donnée, et Polomix en est informé. Données illisibles : Polomix en
   est informé, sans rien inventer.
5. Message envoyé à Polomix : consignes (n'utiliser que ces données, ne rien
   inventer, ne rien enregistrer, corrélation ≠ causalité, dire les limites),
   données, puis le message de l'utilisateur. L'API documentée n'a qu'un champ
   `message` (pas de rôle système).
6. `reply` renvoyé tel quel (espaces retirés), après contrôle du statut HTTP et
   du JSON ; aucun filtre sur le texte (décision du propriétaire, v3).

Pourquoi l'action n'est pas demandée au modèle : l'API ne documente aucune
réponse structurée, et la v2 (format `<answer>` imposé) n'était suivie que 2
fois sur 3. La reconnaissance côté fonction est testée (`intent_test.ts`) et ne
dépend pas de Polomix.

## Sécurité

- **Session** : contrôle JWT de la passerelle désactivé (`config.toml`,
  `verify_jwt = false`) ; vérification dans la fonction avec `getClaims` (clés
  ES256). Le préliminaire CORS passe sans session ; un `POST` sans session est
  refusé avant toute lecture.
- **Données** : lues avec **la session de l'utilisateur** (RLS : seulement ses
  lignes), jamais `service_role`. `data.ts` ne contient que des lectures
  (`data_test.ts` le vérifie) et ajoute l'en-tête `x-evolup-actor: polomix`, que
  les fonctions d'écriture de la base refusent. Polomix ne peut donc ni
  enregistrer, ni modifier, ni supprimer.
- **Secret** : `POLOMIX_API_KEY`, lu à chaque appel. Jamais dans Flutter, Git,
  les journaux ni les réponses.
- **CORS** (`cors.ts`, Web seulement ; ce n'est pas une authentification : la
  session reste exigée quelle que soit l'origine) :
  - Android et iOS n'envoient pas d'en-tête `Origin` : pas d'en-têtes CORS,
    requête traitée normalement (session obligatoire).
  - Développement local, sans configuration : `localhost`, `127.x.x.x` et
    `[::1]` sur **tous les ports** (http ou https) ; adresses privées du réseau
    local (10/8, 172.16/12, 192.168/16) **avec un port explicite** (téléphone
    sur le même Wi-Fi). Désactivable avec le secret `COACH_LOCAL_ORIGINS=off`.
  - Production : origines `https://` exactes listées dans le secret
    `COACH_ALLOWED_ORIGINS` (séparées par des virgules ; `*`, chemins et
    `http://` ignorés, et leur nombre est journalisé au démarrage).
  - Toute autre origine (dont `null`) : `403 origin_not_allowed`, avant la
    lecture de la session.
- **Appels excessifs** : 1 à la fois, 5 par minute, 30 par heure et par
  utilisateur, **par instance** (mémoire) : un frein, pas un quota fiable.
- **Journaux** : type de requête, résultat, action oui/non, nombre d'indicateurs
  envoyés, statut HTTP de Polomix, durée. Jamais le message, la réponse, les
  données, l'utilisateur ou le jeton.

## Polomix (documentation consultée le 2026-10-25)

Source : page « ApiDashboard » de https://polomix-ai.netlify.app et appels sans
clé valide.

- Endpoint utilisé : `POST /api/v1/chat`, `Authorization: Bearer pmx_…`, corps
  `{"message","model":"chatix-25"}`, réponse `{"reply","tokens_used","model"}`.
- `POST /api/v1/chat/completions` (format OpenAI) n'est documenté qu'en
  streaming : non utilisé. Rôle `system`, historique : non documentés.
- Quotas affichés : 8 000 jetons/jour et 240 000/mois (offre gratuite).
- Constats 2026-10-25 : `reply` peut commencer par une analyse du modèle (« User
  asks: … ») avant la réponse ; elle est affichée.
- **Non vérifié** : taille maximale d'un message (la v4 envoie consignes +
  données + message, jusqu'à ~6 000 caractères), codes en cas de quota, et
  respect des consignes placées dans le message. Le test de compatibilité des
  Paramètres et un essai réel après déploiement sont nécessaires.

## Tests locaux (sans clé, sans réseau)

Depuis ce dossier :

```powershell
npx -y deno@2.9.6 fmt --check .
npx -y deno@2.9.6 lint .
npx -y deno@2.9.6 check *.ts
npx -y deno@2.9.6 test --no-prompt --allow-read=. *_test.ts
```

Polomix, la session et les données sont remplacés par des faux
(`test_fixtures.ts`).

## Déploiement (accord du propriétaire requis)

Après les migrations `20261109…` (la fonction lit `profiles`, `metric_catalog`,
`user_metrics`, `metric_daily_values` et les fonctions de lecture) :

```powershell
npx supabase functions deploy coach-chat --use-api
```

Puis, dans l'app : Paramètres → Polomix → « Tester la compatibilité », puis une
question et une saisie réelles.
