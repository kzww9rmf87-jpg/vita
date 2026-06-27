# VITA — ENGINEERING GUIDE
## Guide technique officiel du projet

*Ce document définit comment nous construisons VITA. Il a la même autorité que FOUNDING_PRINCIPLES.md dans le domaine technique. Tout développeur, humain ou IA, doit le consulter avant d'écrire du code.*

*Dernière mise à jour : Juin 2026 — Version 1.0*

---

## TABLE DES MATIÈRES

1. [Philosophie d'ingénierie](#1-philosophie-dingénierie)
2. [Architecture du système](#2-architecture-du-système)
3. [Organisation des dossiers](#3-organisation-des-dossiers)
4. [Standards TypeScript / Node.js](#4-standards-typescript--nodejs)
5. [Standards Python / AI Engine](#5-standards-python--ai-engine)
6. [Standards Swift / iOS](#6-standards-swift--ios)
7. [Standards SQL / Base de données](#7-standards-sql--base-de-données)
8. [Sécurité](#8-sécurité)
9. [Tests](#9-tests)
10. [Documentation](#10-documentation)
11. [Revue de code](#11-revue-de-code)
12. [Git et versioning](#12-git-et-versioning)
13. [Variables d'environnement](#13-variables-denvironnement)
14. [Performance](#14-performance)
15. [Règles pour Claude Code](#15-règles-pour-claude-code)

---

## 1. PHILOSOPHIE D'INGÉNIERIE

### Le code est une déclaration de valeurs

Le code de VITA doit être cohérent avec `FOUNDING_PRINCIPLES.md`. Un développeur qui lit notre code doit comprendre ce que nous croyons — pas seulement ce que nous faisons.

**Conséquences concrètes :**
- Pas de gamification dans le code, même commentée ou désactivée
- Les noms de variables et fonctions doivent refléter notre vocabulaire produit (`witness`, `memory`, `check_in`) — pas un vocabulaire générique wellness (`score`, `streak`, `achievement`)
- Une table de base de données qui ne devrait pas exister selon nos principes n'existe pas dans le code

### Construire pour durer, pas pour impressionner

VITA doit fonctionner dans dix ans. Cela impose des choix différents de ceux d'une startup qui optimise pour la vitesse.

- **Préférer le lisible au malin.** Une solution élégante mais difficile à comprendre n'est pas une bonne solution pour VITA.
- **Préférer l'explicite à l'implicite.** La magie de framework cache des comportements. On préfère le code qu'on peut lire de haut en bas.
- **Zéro dette technique volontaire.** On ne code pas `// TODO: fix later`. Si quelque chose doit être fait, on le fait maintenant ou on ouvre un ticket concret avec une date.

### Simplicité d'abord

Avant d'abstraire, demander : est-ce que cette abstraction a été nécessaire **trois fois** ? Si non, la duplication modeste est préférable à l'abstraction prématurée.

Règle : une PR qui ajoute une abstraction doit expliquer en description pourquoi elle était nécessaire.

---

## 2. ARCHITECTURE DU SYSTÈME

### Vue d'ensemble

```
┌─────────────────────────────────────────────┐
│                  Mobile iOS                  │
│              (SwiftUI / Swift)               │
└──────────────┬──────────────────────────────┘
               │ HTTPS / REST
               ▼
┌─────────────────────────────────────────────┐
│                    Nginx                     │
│              (Reverse Proxy)                 │
└──────┬────────────────────┬─────────────────┘
       │                    │
       ▼                    ▼
┌─────────────┐    ┌─────────────────┐
│ auth-service│    │  data-service   │
│  (Port 3001)│    │  (Port 3002)    │
│  TypeScript │    │  TypeScript     │
└─────────────┘    └────────┬────────┘
                            │ HTTP interne
                            ▼
                   ┌─────────────────┐
                   │   ai-engine     │
                   │  (Port 3003)    │
                   │  Python/FastAPI │
                   └────────┬────────┘
                            │
              ┌─────────────┴──────────────┐
              ▼                            ▼
     ┌─────────────────┐        ┌──────────────────┐
     │   PostgreSQL 16  │        │    Redis 7        │
     │   + TimescaleDB  │        │    (Cache)        │
     └─────────────────┘        └──────────────────┘
```

### Responsabilités par service

| Service | Responsabilité unique | Ce qu'il NE fait PAS |
|---------|----------------------|----------------------|
| `auth-service` | Authentification, tokens, sessions | Données de santé, IA |
| `data-service` | CRUD données santé, agrégation, proxy IA | Auth, logique IA |
| `ai-engine` | Analyse IA, mémoire, orchestration Claude | Auth, persistance directe des données santé |

### Règle de communication inter-services

- Le mobile ne parle **jamais** directement à l'ai-engine
- Le data-service est le seul point d'entrée pour le mobile
- L'ai-engine ne fait pas confiance aux requêtes sans `X-Service-Token`
- Aucun service ne partage de code directement avec un autre (pas de package partagé en monorepo pour l'instant)

### Ports

| Service | Port dev | Port prod |
|---------|----------|-----------|
| auth-service | 3001 | 3001 |
| data-service | 3002 | 3002 |
| ai-engine | 3003 | 3003 (non exposé publiquement) |
| PostgreSQL | 5432 | 5432 (interne uniquement) |
| Redis | 6379 | 6379 (interne uniquement) |
| Nginx | 80 / 443 | 80 / 443 |

**Règle :** En production, seul Nginx est exposé publiquement. PostgreSQL, Redis, et l'ai-engine ne sont **jamais** accessibles depuis l'extérieur.

---

## 3. ORGANISATION DES DOSSIERS

### Structure racine

```
vita/
├── FOUNDING_PRINCIPLES.md   ← Vision produit (ne pas modifier sans consensus)
├── ENGINEERING.md           ← Ce document (ne pas modifier sans PR dédiée)
├── QUICKSTART.md            ← Guide de démarrage développeur
├── package.json             ← Monorepo root (Turborepo)
├── turbo.json
├── .env.example             ← Template — JAMAIS de vraies valeurs ici
├── .gitignore
│
├── backend/
│   ├── auth-service/
│   │   ├── src/
│   │   │   ├── index.ts         ← Entrée : serveur Fastify, plugins, hooks
│   │   │   ├── db.ts            ← Pool PostgreSQL + helpers query
│   │   │   ├── tokens.ts        ← Génération/révocation JWT + refresh
│   │   │   └── routes/
│   │   │       └── auth.ts      ← Routes /auth/* (register, login, refresh, logout)
│   │   ├── tests/
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── Dockerfile
│   │
│   └── data-service/
│       ├── src/
│       │   ├── index.ts         ← Entrée : serveur, hook JWT global
│       │   ├── db.ts            ← Pool PostgreSQL
│       │   ├── ai-client.ts     ← Client HTTP vers ai-engine (NOUVEAU)
│       │   └── routes/
│       │       ├── checkin.ts
│       │       ├── dashboard.ts
│       │       ├── profile.ts
│       │       ├── sleep.ts
│       │       ├── activity.ts
│       │       ├── nutrition.ts
│       │       ├── chat.ts      ← Route /chat (proxy vers ai-engine)
│       │       └── reports.ts
│       ├── tests/
│       ├── package.json
│       ├── tsconfig.json
│       └── Dockerfile
│
├── ai-engine/
│   ├── agents/
│   │   ├── __init__.py
│   │   ├── sport_agent.py
│   │   ├── sleep_agent.py
│   │   ├── nutrition_agent.py
│   │   ├── mental_agent.py
│   │   ├── health_agent.py
│   │   └── synthesis_agent.py
│   ├── memory/
│   │   ├── __init__.py
│   │   ├── vita_memory.py      ← Chargement mémoire complète (NOUVEAU)
│   │   ├── pattern_detector.py
│   │   └── weekly_report.py
│   ├── tests/
│   │   ├── __init__.py
│   │   ├── test_sport_agent.py
│   │   ├── test_sleep_agent.py
│   │   └── test_nutrition_agent.py
│   ├── config.py
│   ├── models.py
│   ├── orchestrator.py
│   ├── chat.py
│   ├── main.py
│   ├── db.py                   ← Pool asyncpg partagé (NOUVEAU)
│   ├── requirements.txt
│   └── Dockerfile
│
├── mobile/
│   └── ios/
│       └── Vita/
│           ├── Vita.xcodeproj/
│           ├── Core/
│           │   ├── Network/
│           │   │   └── APIClient.swift
│           │   ├── HealthKit/
│           │   │   └── HealthKitManager.swift
│           │   └── Storage/
│           │       └── KeychainHelper.swift
│           ├── DesignSystem/
│           │   └── VitaTheme.swift
│           ├── Features/
│           │   ├── Auth/
│           │   ├── Onboarding/
│           │   ├── CheckIn/
│           │   ├── Dashboard/
│           │   ├── Chat/
│           │   └── History/     ← "Mon histoire" (NOUVEAU)
│           └── VitaApp.swift
│
├── database/
│   ├── migrations/
│   │   └── 001_init.sql
│   └── migrate.js              ← Runner de migrations (NOUVEAU)
│
└── infrastructure/
    └── docker/
        ├── docker-compose.yml
        └── nginx.conf
```

### Règles d'organisation

**Un fichier = une responsabilité.** Si un fichier fait deux choses, le diviser.

**Nommage des fichiers :**
- TypeScript : `camelCase.ts` pour les modules, `PascalCase.ts` pour les classes seules
- Python : `snake_case.py` toujours
- Swift : `PascalCase.swift` toujours (conventions Apple)
- SQL : `001_description_courte.sql` (numéro séquentiel, description en snake_case)

**Les tests vivent à côté du code :** `src/routes/auth.ts` → `tests/routes/auth.test.ts`

---

## 4. STANDARDS TYPESCRIPT / NODE.JS

### Configuration TypeScript

Chaque service backend doit avoir un `tsconfig.json` à sa racine. Configuration minimale obligatoire :

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "esModuleInterop": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

**`strict: true` est non-négociable.** Pas de `any` implicite, pas de `null` ignoré.

### Règles de code TypeScript

**Types :**
```typescript
// ✅ Bon — types explicites sur les fonctions publiques
async function getUserById(id: string): Promise<User | null> { ... }

// ❌ Mauvais — retour inféré sur une fonction publique complexe
async function getUserById(id: string) { ... }

// ✅ Bon — utiliser unknown plutôt que any
function parseData(raw: unknown): ParsedData { ... }

// ❌ Jamais
function parseData(raw: any): any { ... }
```

**Imports :**
```typescript
// ✅ Extensions .js obligatoires pour les imports locaux (NodeNext)
import { query } from './db.js'
import { authRoutes } from './routes/auth.js'

// ❌ Sans extension — échouera avec NodeNext
import { query } from './db'
```

**Gestion d'erreurs :**
```typescript
// ✅ Bon — erreurs typées et exhaustives
try {
  const user = await getUser(id)
} catch (err) {
  if (err instanceof PostgresError) {
    app.log.error({ err, userId: id }, 'DB error in getUser')
    return reply.status(500).send({ error: 'INTERNAL_ERROR' })
  }
  throw err // Re-throw les erreurs inattendues
}

// ❌ Mauvais — catch silencieux
try {
  const user = await getUser(id)
} catch {
  // silently fail
}
```

**Validation des inputs :**
- Tout body de requête doit être validé avec **Zod** avant d'être utilisé
- La validation se fait en première ligne du handler
- Les erreurs de validation retournent toujours un 400 avec `{ error: 'VALIDATION_ERROR', details: ... }`

```typescript
// ✅ Pattern obligatoire pour tous les handlers
app.post('/example', async (req, reply) => {
  const result = ExampleSchema.safeParse(req.body)
  if (!result.success) {
    return reply.status(400).send({
      error: 'VALIDATION_ERROR',
      details: result.error.flatten(),
    })
  }
  const body = result.data
  // ... suite
})
```

**Requêtes SQL :**
- **Zéro SQL dynamique par concaténation de chaînes.** Toujours des paramètres `$1, $2`.
- Les requêtes complexes (>10 lignes) vont dans des fonctions nommées dans `db.ts`

```typescript
// ✅ Bon
await query('SELECT id FROM users WHERE email = $1', [email])

// ❌ Injection SQL potentielle
await query(`SELECT id FROM users WHERE email = '${email}'`)
```

### Conventions de nommage TypeScript

| Élément | Convention | Exemple |
|---------|-----------|---------|
| Variables, fonctions | camelCase | `getUserById`, `accessToken` |
| Classes, interfaces, types | PascalCase | `UserProfile`, `TokenResponse` |
| Constantes globales | SCREAMING_SNAKE | `MAX_REFRESH_TOKENS` |
| Fichiers | camelCase | `authRoutes.ts`, `db.ts` |
| Routes Fastify | snake_case dans l'URL | `/checkin/morning`, `/dashboard/week` |
| Colonnes DB (dans les types TS) | camelCase | `createdAt`, `userId` |

---

## 5. STANDARDS PYTHON / AI ENGINE

### Environnement

- Python **3.12+** obligatoire
- Un virtualenv par développeur (`python -m venv .venv`)
- `requirements.txt` pour les dépendances de production
- `requirements-dev.txt` pour les dépendances de développement (pytest, etc.)

### Configuration linter

Le projet utilise **ruff** pour le linting et le formatage. Configuration dans `pyproject.toml` (à créer) :

```toml
[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "S", "B", "A"]
ignore = ["S101"]  # assert autorisé dans les tests

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S", "B"]
```

### Règles de code Python

**Types obligatoires sur toutes les fonctions publiques :**
```python
# ✅ Bon
async def load_user_memory(user_id: str, limit: int = 20) -> list[MemoryEntry]:
    ...

# ❌ Mauvais
def load_user_memory(user_id, limit=20):
    ...
```

**Pydantic pour tous les modèles de données :**
```python
# ✅ Bon — modèle validé
class CheckInData(BaseModel):
    energy: int = Field(ge=1, le=5)
    mood: int = Field(ge=1, le=5)
    notes: str | None = None

# ❌ Mauvais — dict non typé
def process_checkin(data: dict) -> dict:
    energy = data["energy"]  # Pas de validation
```

**Async/await : règle absolue :**
```python
# ✅ Bon — tout I/O est async dans FastAPI
async def handle_chat_message(user_id: str, message: str) -> ChatResponse:
    rows = await db.fetch("SELECT ...", user_id)  # asyncpg

# ❌ Bloque le worker FastAPI — interdit
def handle_chat_message(user_id: str, message: str) -> ChatResponse:
    conn = psycopg2.connect(...)  # Synchrone bloquant
    cur = conn.cursor()
```

**Gestion des connexions DB — pool partagé :**
```python
# ✅ Pool asyncpg global dans db.py
# Utilisé ainsi dans tous les modules :
from db import get_pool

async def some_function():
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT ...")

# ❌ Jamais de connexion par appel
def some_function():
    conn = psycopg2.connect(settings.database_url)  # Une connexion par appel
```

**Prompts Claude — règles de rédaction :**

Les prompts sont du code. Ils doivent être versionnés, testés et documentés.

```python
# ✅ Bon — prompt dans une constante nommée, séparé de la logique
WITNESS_SYSTEM_PROMPT = """
Tu es VITA, un Témoin Bienveillant.
[...]
"""

async def generate_response(context: UserContext) -> str:
    response = await client.messages.create(
        model=settings.model_fast,
        system=WITNESS_SYSTEM_PROMPT,
        messages=[...],
    )
    return response.content[0].text

# ❌ Prompt inline dans la logique
async def generate_response(context: UserContext) -> str:
    response = await client.messages.create(
        system="Tu es un assistant santé...",  # Prompt enterré dans la logique
        ...
    )
```

### Conventions de nommage Python

| Élément | Convention | Exemple |
|---------|-----------|---------|
| Variables, fonctions | snake_case | `user_id`, `load_context` |
| Classes | PascalCase | `UserContext`, `AgentSignal` |
| Constantes de module | SCREAMING_SNAKE | `MAX_HISTORY_MESSAGES` |
| Fichiers | snake_case | `vita_memory.py`, `pattern_detector.py` |
| Tables DB (dans les requêtes) | snake_case | `user_profiles`, `daily_checkins` |

---

## 6. STANDARDS SWIFT / IOS

### Architecture : MVVM stricte

Chaque feature suit la structure :
```
Features/
└── NomDeLaFeature/
    ├── NomDeLaFeatureView.swift      ← UI pure, zéro logique métier
    ├── NomDeLaFeatureViewModel.swift ← @MainActor, @Published, appels API
    └── NomDeLaFeatureModels.swift    ← Structs Codable si nombreux
```

**La View ne contient jamais de logique.** Elle observe le ViewModel et lui délègue toute action.

```swift
// ✅ Bon — View déléguée
struct CheckInView: View {
    @StateObject private var vm = CheckInViewModel()

    var body: some View {
        Button("Valider") {
            Task { await vm.submit() }  // Logique dans le VM
        }
    }
}

// ❌ Mauvais — logique dans la View
struct CheckInView: View {
    var body: some View {
        Button("Valider") {
            Task {
                let body = CheckInBody(energy: 3, mood: 3)
                let _: CheckInResponse = try await APIClient.shared.post("/checkin/morning", body: body)
                // Logique métier dans la View
            }
        }
    }
}
```

**Tous les ViewModels sont `@MainActor` :**
```swift
@MainActor
final class CheckInViewModel: ObservableObject {
    @Published var currentStep = 1
    @Published var isSubmitting = false

    func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        // ...
    }
}
```

### Design System — règles d'usage

**Toutes les couleurs** viennent de `VitaColor`. Aucune couleur littérale (`Color.blue`, `Color(hex:...)`) dans les Views.

**Toutes les polices** viennent de `VitaFont`.

**Tous les espacements** viennent de `VitaSpacing`.

**Tous les rayons de bordure** viennent de `VitaRadius`.

```swift
// ✅ Bon
Text("Bonjour")
    .font(VitaFont.title(22))
    .foregroundColor(VitaColor.textPrimary)
    .padding(VitaSpacing.lg)

// ❌ Mauvais — valeurs harcordées
Text("Bonjour")
    .font(.system(size: 22, weight: .semibold))
    .foregroundColor(.black)
    .padding(16)
```

### Règles de sécurité iOS

- Les tokens ne sont **jamais** stockés dans `UserDefaults`. Toujours dans le Keychain via `KeychainHelper`.
- L'`accessToken` n'est jamais loggé (ni par `print`, ni par `Logger`).
- Les données de santé de l'utilisateur ne transitent jamais dans les logs.

### Conventions de nommage Swift

| Élément | Convention | Exemple |
|---------|-----------|---------|
| Types (struct, class, enum, protocol) | PascalCase | `CheckInViewModel`, `APIError` |
| Variables, fonctions | camelCase | `isSubmitting`, `submitCheckIn()` |
| Constantes de module | camelCase (Swift idiomatique) | `maxRetries`, `defaultTimeout` |
| Fichiers | PascalCase | `CheckInViewModel.swift` |
| Endpoints API (dans les appels) | snake_case dans la string | `"/checkin/morning"` |

---

## 7. STANDARDS SQL / BASE DE DONNÉES

### Règles de migration

- Chaque changement de schéma = un nouveau fichier `NNN_description.sql`
- Le numéro est séquentiel et n'est jamais réutilisé
- **Une migration ne peut jamais être modifiée après avoir été commitée**
- Si une migration contient une erreur, on crée une migration de correction

```sql
-- ✅ Bon — migration atomique et réversible
-- 002_add_onboarding_responses.sql

BEGIN;

CREATE TABLE onboarding_responses (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question   TEXT NOT NULL CHECK (question IN (
               'why_here', 'life_now', 'change_stuck',
               'dependents', 'future_self', 'private_weight'
             )),
  response   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_onboarding_user ON onboarding_responses(user_id);

COMMIT;
```

### Nommage SQL

| Élément | Convention | Exemple |
|---------|-----------|---------|
| Tables | snake_case, pluriel | `user_profiles`, `daily_checkins` |
| Colonnes | snake_case | `user_id`, `created_at`, `pain_areas` |
| Index | `idx_table_colonnes` | `idx_sleep_user_date` |
| Fonctions PG | snake_case | `update_updated_at()` |
| Contraintes CHECK | Inline sur la colonne | `CHECK (energy BETWEEN 1 AND 5)` |
| Clés étrangères | `REFERENCES table(id)` sans alias | `REFERENCES users(id)` |

### Règles SQL

**Toutes les tables ont :**
- `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()` (sauf junction tables)
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` (si applicable)

**Les requêtes dans le code :**
- Paramètres positionnels (`$1`, `$2`) — toujours
- Pas de `SELECT *` — lister explicitement les colonnes
- Les requêtes de plus de 5 lignes sont dans des fonctions nommées

```typescript
// ✅ Bon — colonnes explicites
const user = await queryOne<User>(
  'SELECT id, email, created_at FROM users WHERE id = $1',
  [userId]
)

// ❌ Mauvais — SELECT *
const user = await queryOne('SELECT * FROM users WHERE id = $1', [userId])
```

### Hypertables TimescaleDB

Les tables suivantes sont des hypertables (données temporelles) :
- `sleep_entries` (partitionné par `date`)
- `activity_sessions` (partitionné par `date`)
- `daily_checkins` (partitionné par `date`)
- `nutrition_daily` (partitionné par `date`)
- `ai_recommendations` (partitionné par `date`)
- `messages` (partitionné par `created_at`)

**Règle :** Toute requête sur ces tables qui porte sur une plage de dates **doit** inclure un filtre sur la colonne de partitionnement pour bénéficier du pruning.

```sql
-- ✅ Bon — filtre sur la colonne de partition
SELECT * FROM daily_checkins
WHERE user_id = $1 AND date >= CURRENT_DATE - 7;

-- ❌ Mauvais — scan complet de l'hypertable
SELECT * FROM daily_checkins WHERE user_id = $1;
```

---

## 8. SÉCURITÉ

### Règles non-négociables

Ces règles s'appliquent à tout le code, par tout développeur, dans toutes les circonstances.

**1. Zéro secret dans le code.**
Aucune clé API, mot de passe, secret JWT ou token ne doit apparaître dans le code source — ni dans un commentaire, ni dans un test, ni dans une configuration commitée. Toujours des variables d'environnement.

**2. Zéro SQL par concaténation.**
Toujours des paramètres positionnels. Sans exception.

**3. Validation à la frontière.**
Tout input externe (body HTTP, query params, headers) est validé avant d'être utilisé. Les données internes (entre services) font confiance au type système, pas à une validation redondante.

**4. CORS restrictif.**
`origin: true` est interdit. Toujours une liste explicite via `ALLOWED_ORIGINS`.

**5. Principe du moindre privilège.**
Chaque service n'a accès qu'à ce dont il a besoin. L'ai-engine n'a pas de route exposée publiquement. La DB de production n'est pas accessible depuis l'extérieur.

### Authentification et tokens

**JWT (Access Token)**
- Durée de vie : 15 minutes
- Algorithme : HS256 avec `JWT_SECRET` (min 64 caractères aléatoires)
- Payload minimal : `{ sub: userId, type: 'access' }`
- Ne jamais inclure de données sensibles dans le payload JWT

**Refresh Token**
- Généré avec `crypto.randomBytes(64)`
- Stocké en base sous forme de hash SHA-256 uniquement
- Durée de vie : 30 jours
- Rotation obligatoire à chaque usage (révocation de l'ancien, émission d'un nouveau)
- Révocation de tous les tokens de l'utilisateur sur suppression de compte

**Token inter-services**
- `X-Service-Token` : secret dédié (`AI_SERVICE_TOKEN`), distinct du `JWT_SECRET`
- Le token est un secret partagé statique (pas un JWT)
- Toute requête à l'ai-engine sans ce header exact retourne 401

### Rate limiting

**Routes concernées et limites :**

| Route | Limite | Fenêtre |
|-------|--------|---------|
| `POST /auth/login` | 10 requêtes | 15 minutes par IP |
| `POST /auth/register` | 5 requêtes | 1 heure par IP |
| `POST /auth/refresh` | 20 requêtes | 15 minutes par IP |
| `POST /chat` | 30 requêtes | 1 heure par userId |
| `POST /recommend` | 10 requêtes | 1 heure par userId |

Le rate limiting est implémenté avec Redis (compteurs avec TTL).

### Données de santé — règles spéciales

Les données de santé sont des données sensibles au sens du RGPD. Règles supplémentaires :

- Les logs applicatifs **ne contiennent jamais** de données de santé (énergie, humeur, douleur, etc.)
- Les logs peuvent contenir : `userId`, timestamps, codes d'erreur, durées de traitement
- Les backups de production sont chiffrés au repos
- L'export RGPD (`GET /profile/export`) est loggué avec userId et timestamp pour audit

### Headers de sécurité HTTP

Nginx doit inclure ces headers sur toutes les réponses :

```nginx
add_header X-Content-Type-Options "nosniff";
add_header X-Frame-Options "DENY";
add_header Referrer-Policy "no-referrer";
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()";
```

---

## 9. TESTS

### Philosophie des tests

Les tests de VITA vérifient deux choses distinctes :

1. **La correction fonctionnelle** : le code fait ce qu'il est censé faire
2. **Les moments magiques** : les expériences clés du produit se produisent au bon moment

Un test qui vérifie que `POST /checkin/morning` retourne 201 est un test fonctionnel.

Un test qui vérifie que "la réponse de VITA au Jour 7 contient une référence à un élément des Jours 1-6" est un test de moment magique. Ces tests sont aussi importants.

### Niveaux de tests

**Tests unitaires** — chaque agent IA, chaque fonction de calcul
- Rapides (< 100ms par test)
- Pas de réseau, pas de DB
- Doivent passer en CI à chaque PR

**Tests d'intégration** — routes HTTP avec DB de test
- Base de données de test isolée (Docker en CI)
- Testent le flux complet d'une requête
- Doivent passer en CI avant merge

**Tests de bout-en-bout** — scénarios utilisateur complets
- Exécutés manuellement avant chaque release
- Scénarios documentés dans `tests/e2e/scenarios.md`

### Couverture minimale requise

| Composant | Couverture minimale |
|-----------|-------------------|
| Agents IA (`sport_agent`, `sleep_agent`, etc.) | 80% |
| Routes auth-service | 90% |
| Routes data-service (CRUD) | 70% |
| Logique de mémoire (`vita_memory.py`) | 85% |
| Synthesis agent | 80% |

### Écriture des tests

**Tests Python (pytest) :**
```python
# ✅ Bon — test nommé explicitement, une seule assertion par test
class TestOvertrainingDetection:

    def test_detects_overtraining_with_high_load_and_poor_sleep(self):
        sessions = [make_session(rpe=9, duration=90)] * 6
        sleep = {"quality_score": 2, "duration_minutes": 300}
        
        signal = _detect_overtraining(sessions, sleep)
        
        assert signal is not None
        assert signal.signal_type == "overtraining_risk"

    def test_no_overtraining_below_threshold(self):
        sessions = [make_session(rpe=6, duration=60)] * 3
        sleep = {"quality_score": 4}
        
        signal = _detect_overtraining(sessions, sleep)
        
        assert signal is None
```

**Tests TypeScript (vitest) :**
```typescript
// ✅ Bon — test d'intégration de route
describe('POST /checkin/morning', () => {
  it('returns 201 with valid body', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/checkin/morning',
      headers: { authorization: `Bearer ${testToken}` },
      body: { energy: 4, mood: 3, stress: 2 },
    })

    expect(response.statusCode).toBe(201)
    expect(response.json()).toMatchObject({ date: expect.any(String) })
  })

  it('returns 409 if morning checkin already exists today', async () => {
    await createTestCheckin(testUserId) // Fixture

    const response = await app.inject({
      method: 'POST',
      url: '/checkin/morning',
      headers: { authorization: `Bearer ${testToken}` },
      body: { energy: 3, mood: 3, stress: 3 },
    })

    expect(response.statusCode).toBe(409)
  })
})
```

### Tests des moments magiques

Ces tests sont dans `tests/magic-moments/` et vérifient les expériences clés du produit.

```python
# tests/magic-moments/test_day7_memory.py

async def test_vita_response_references_previous_checkin():
    """
    Au Jour 7, la réponse de VITA au check-in doit contenir
    une référence à quelque chose dit les jours précédents.
    
    C'est le Moment Magique 1 — "Cette IA me connaît vraiment."
    """
    user_id = await create_test_user()
    
    # Simuler 6 jours de check-ins avec un contexte cohérent
    for day in range(6):
        await create_checkin(user_id, notes="Réunion stressante demain")
    
    # Jour 7 : générer la réponse
    response = await generate_checkin_response(user_id)
    
    # La réponse doit montrer qu'elle a vu les jours précédents
    # (elle ne doit pas être un message générique)
    assert "réunion" in response.content.lower() or \
           "stressante" in response.content.lower() or \
           "semaine" in response.content.lower()
    
    assert response.content != GENERIC_MAINTENANCE_RESPONSE
```

---

## 10. DOCUMENTATION

### Ce qui doit être documenté

**Toujours documenter :**
- Les décisions d'architecture non évidentes (avec pourquoi, pas juste quoi)
- Les algorithmes complexes (ATL/CTL, corrélation de Pearson)
- Les contrats d'API (inputs, outputs, codes d'erreur)
- Les variables d'environnement (dans `.env.example`)
- Les scénarios de test end-to-end

**Ne jamais documenter :**
- Ce que le code dit déjà clairement
- Les évidences ("cette fonction retourne un utilisateur")
- L'historique des décisions (c'est le rôle de git)

### Commentaires dans le code

Un commentaire explique **pourquoi**, jamais **quoi**.

```typescript
// ✅ Bon — explique une contrainte non évidente
// bcrypt avec rounds=12 : délibérément lent pour résister au brute-force.
// Ne pas réduire même si les perfs semblent impactées.
const hash = await bcrypt.hash(password, 12)

// ❌ Mauvais — dit ce que le code dit déjà
// Hacher le mot de passe
const hash = await bcrypt.hash(password, 12)
```

```python
# ✅ Bon — explique le choix algorithmique
# τ=7 pour ATL (charge aiguë) suit la littérature PMC/TSS de Coggan & Allen.
# Un τ plus court réagit plus vite aux pics de charge.
atl = _compute_training_load(sessions, tau=7)

# ❌ Mauvais
# Calculer la charge aiguë
atl = _compute_training_load(sessions, tau=7)
```

### Documentation des routes API

Chaque route doit avoir un commentaire court au format suivant :

```typescript
// POST /checkin/morning
// Body: MorningCheckinSchema
// Returns: { id: string, date: string }
// Errors: 409 si check-in déjà fait aujourd'hui, 400 si validation échoue
// Auth: JWT requis
app.post('/morning', async (req, reply) => { ... })
```

### `.env.example` comme documentation

Toute nouvelle variable d'environnement doit être :
1. Ajoutée dans `.env.example` avec une valeur d'exemple ou une description
2. Documentée dans le service qui l'utilise
3. Listée dans `QUICKSTART.md` si elle est requise pour démarrer

---

## 11. REVUE DE CODE

### Qui peut merger

- Toute PR requiert au moins **une revue approuvée**
- Les PRs qui touchent à la sécurité (auth, tokens, CORS, données de santé) requièrent **deux revues**
- Les PRs qui modifient `FOUNDING_PRINCIPLES.md` ou `ENGINEERING.md` requièrent une **discussion d'équipe explicite** avant ouverture

### Ce que le reviewer vérifie

**Checklist obligatoire pour chaque PR :**

- [ ] Le code compile sans erreurs ou warnings
- [ ] Les tests passent
- [ ] La PR ne viole aucun principe de `FOUNDING_PRINCIPLES.md`
- [ ] La PR ne viole aucune règle de `ENGINEERING.md`
- [ ] Pas de secrets dans le code
- [ ] Pas de SQL par concaténation
- [ ] Les inputs externes sont validés
- [ ] Les erreurs sont gérées (pas de catch silencieux)
- [ ] Les nouvelles variables d'environnement sont dans `.env.example`
- [ ] Si la PR ajoute une fonctionnalité : un test couvre le cas nominal et un cas d'erreur

### Ce que le reviewer NE fait PAS

- Suggérer des fonctionnalités non demandées
- Commenter le style si le linter passe (le linter a raison, pas l'opinion du reviewer)
- Bloquer une PR pour des raisons de préférence personnelle non documentée dans ce guide

### Format des commentaires de review

**Bloquant :** `[BLOCKER] Cette route expose les données de santé sans authentification.`

**Suggestion :** `[SUGGESTION] Ce pattern pourrait être extrait en fonction. Pas bloquant pour cette PR.`

**Question :** `[QUESTION] Pourquoi `bcrypt.compare` plutôt que `timingSafeEqual` ici ?`

---

## 12. GIT ET VERSIONING

### Branches

```
main          ← Production. Toujours deployable.
develop       ← Intégration. Passent les tests. Base des PRs.
sprint/N      ← Branche de sprint (optionnel si équipe petite)
feat/nom-court ← Feature branch. Nommée par la feature, pas par le ticket.
fix/nom-court  ← Bug fix.
chore/nom-court ← Infrastructure, dépendances, configuration.
```

**Règle :** On ne committe jamais directement sur `main`. Toujours via PR depuis `develop`.

### Commits

Format obligatoire : **Conventional Commits**

```
type(scope): description courte en impératif

Corps optionnel : explication du pourquoi si non évident.

Ticket: VITA-123 (si applicable)
```

**Types autorisés :**

| Type | Usage |
|------|-------|
| `feat` | Nouvelle fonctionnalité |
| `fix` | Correction de bug |
| `refactor` | Refactoring sans changement de comportement |
| `test` | Ajout ou modification de tests uniquement |
| `chore` | Configuration, dépendances, infra |
| `docs` | Documentation uniquement |
| `perf` | Amélioration de performance |
| `security` | Correction de sécurité |

**Exemples :**
```
feat(checkin): add morning check-in route with idempotency check

fix(auth): replace app.authenticate with correct JWT hook

security(data-service): restrict CORS from origin:true to ALLOWED_ORIGINS

chore(db): add migrate.js runner for SQL migrations

docs(engineering): add SQL naming conventions section
```

**Règles :**
- Un commit = une seule chose. Pas de "fix bug and add feature and refactor".
- La description est en anglais, impératif présent ("add", pas "added" ni "adding").
- Pas de commits "WIP", "fix", "test" dans `main` ou `develop`.

### Tags de version

Format : `vMAJEUR.MINEUR.PATCH`

- **PATCH** : bug fix, correction de sécurité, documentation
- **MINEUR** : nouvelle fonctionnalité, compatible avec l'existant
- **MAJEUR** : changement breaking d'API, changement de schéma incompatible

---

## 13. VARIABLES D'ENVIRONNEMENT

### Règles

- **Jamais** de valeur par défaut pour les secrets dans le code
- **Toujours** une erreur claire au démarrage si une variable obligatoire est absente
- **Toujours** dans `.env.example` avec documentation

### Variables obligatoires par service

**auth-service :**
```bash
DATABASE_URL        # postgresql://user:pass@host:5432/vita
JWT_SECRET          # Minimum 64 caractères, généré avec openssl rand -hex 64
PORT                # 3001
ALLOWED_ORIGINS     # http://localhost:3000 (comma-separated)
```

**data-service :**
```bash
DATABASE_URL        # même DB que auth-service
JWT_SECRET          # même secret que auth-service (vérifie les tokens)
REDIS_URL           # redis://:password@host:6379
PORT                # 3002
AI_ENGINE_URL       # http://ai-engine:3003
AI_SERVICE_TOKEN    # Secret dédié inter-services (distinct de JWT_SECRET)
ALLOWED_ORIGINS     # même que auth-service
```

**ai-engine :**
```bash
DATABASE_URL        # même DB
REDIS_URL           # même Redis
ANTHROPIC_API_KEY   # sk-ant-...
JWT_SECRET          # Pour vérifier les tokens utilisateurs si nécessaire
AI_SERVICE_TOKEN    # même valeur que dans data-service
PORT                # 3003
```

### Validation au démarrage

Chaque service doit valider ses variables d'environnement **au démarrage**, pas au premier usage.

```typescript
// auth-service/src/index.ts — validation au démarrage
const required = ['DATABASE_URL', 'JWT_SECRET', 'ALLOWED_ORIGINS']
for (const key of required) {
  if (!process.env[key]) {
    console.error(`[FATAL] Missing required environment variable: ${key}`)
    process.exit(1)
  }
}
```

```python
# ai-engine/config.py — pydantic-settings lève une erreur si manquant
class Settings(BaseSettings):
    database_url: str           # Obligatoire — erreur si absent
    anthropic_api_key: str      # Obligatoire
    ai_service_token: str       # Obligatoire
    redis_url: str = "redis://localhost:6379"  # Optionnel avec défaut
```

---

## 14. PERFORMANCE

### Règles générales

**Pas d'optimisation prématurée.** On mesure avant d'optimiser. Si une requête prend 200ms, on comprend pourquoi avant de la modifier.

**Les requêtes DB ont des limites.** Toute requête qui peut retourner un grand nombre de lignes doit avoir un `LIMIT`. Défaut recommandé : 100.

**Le cache Redis est utilisé pour :**
- Le contexte utilisateur dans l'orchestrateur (TTL 10 minutes)
- Les compteurs de rate limiting
- Rien d'autre sans décision explicite

### Cibles de performance

| Endpoint | P95 cible |
|----------|-----------|
| `POST /auth/login` | < 300ms |
| `POST /checkin/morning` | < 200ms |
| `GET /dashboard/week` | < 500ms |
| `POST /chat` (avec Claude) | < 5s |
| `POST /recommend` (avec Claude) | < 8s |

### Connexions DB

- auth-service : pool de 10 connexions max
- data-service : pool de 20 connexions max
- ai-engine : pool asyncpg de 10 connexions max

Ces valeurs sont configurées dans chaque `db.ts` / `db.py`. **Ne pas augmenter** sans comprendre l'impact sur PostgreSQL.

---

## 15. RÈGLES POUR CLAUDE CODE

*Cette section définit comment Claude Code (l'IA de développement) doit opérer dans ce dépôt.*

### Avant d'écrire la moindre ligne de code

1. **Lire `FOUNDING_PRINCIPLES.md`** pour vérifier la cohérence philosophique de la demande
2. **Lire ce document** pour appliquer les standards corrects
3. **Lire les fichiers existants concernés** avant de les modifier
4. **Identifier les dépendances** : quels autres fichiers seront affectés par ce changement ?

### Ce que Claude Code fait toujours

- Crée des `tsconfig.json` corrects pour chaque service TypeScript
- Valide les inputs avec Zod en première ligne des handlers
- Utilise des paramètres positionnels SQL (`$1`, `$2`)
- Ajoute des types explicites sur toutes les fonctions
- Vérifie que les imports ont l'extension `.js` en TypeScript (NodeNext)
- Teste les changements manuellement avant de les proposer comme terminés
- Documente le **pourquoi** dans les commentaires, pas le **quoi**
- Suit les conventions de nommage de ce document

### Ce que Claude Code ne fait jamais

- N'ajoute pas de fonctionnalité non demandée dans une PR
- Ne crée pas de gamification (streaks, badges, scores globaux, XP)
- N'utilise pas `origin: true` dans les configurations CORS
- Ne stocke pas de données de santé dans les logs
- N'écrit pas de secrets en dur dans le code
- Ne fait pas de `SELECT *`
- N'ignore pas silencieusement les erreurs (`catch {}` vide)
- Ne contourne pas les règles de ce document sans l'expliquer explicitement

### Quand Claude Code rencontre un conflit

Si une demande contredit `FOUNDING_PRINCIPLES.md` ou ce document, Claude Code :
1. L'identifie explicitement ("Cette demande contredit le principe X de FOUNDING_PRINCIPLES.md")
2. Explique pourquoi c'est problématique
3. Propose une alternative conforme
4. N'implémente pas la version non conforme sans accord explicite

### Format des réponses techniques

Quand Claude Code propose un changement de code, il présente :
1. **Ce qu'il va faire** (une phrase)
2. **Pourquoi** (si non évident)
3. **Les fichiers affectés**
4. **Le code**
5. **Comment vérifier que ça fonctionne**

---

## ANNEXE — CHECKLIST DE PR

À coller dans la description de chaque Pull Request :

```markdown
## Checklist

### Code
- [ ] Le code compile sans erreurs ni warnings
- [ ] Les tests passent localement
- [ ] Pas de `console.log` / `print` de debug laissés

### Sécurité
- [ ] Pas de secrets dans le code
- [ ] Pas de SQL par concaténation de chaînes
- [ ] Les inputs externes sont validés (Zod/Pydantic)
- [ ] Pas de `origin: true` dans CORS
- [ ] Pas de données de santé dans les logs

### Standards
- [ ] Types explicites sur les fonctions publiques
- [ ] Gestion d'erreurs (pas de catch silencieux)
- [ ] Imports avec extension `.js` (TypeScript)
- [ ] Pas de `SELECT *`
- [ ] Design System utilisé (pas de couleurs/fonts hardcodées) [iOS uniquement]

### Philosophie produit
- [ ] Pas de gamification (streaks, badges, scores globaux)
- [ ] Cohérent avec FOUNDING_PRINCIPLES.md

### Documentation
- [ ] Nouvelles variables d'env dans `.env.example`
- [ ] API documentée (format inputs/outputs/erreurs) si nouvelle route
- [ ] Commentaires expliquent le "pourquoi" si nécessaire
```

---

*Ce document est la référence technique de VITA. Il évolue par PR dédiée, avec description des changements et raisons. Il ne peut pas être modifié dans le cadre d'une PR de fonctionnalité.*
