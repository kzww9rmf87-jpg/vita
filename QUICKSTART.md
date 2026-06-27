# VITA — Guide de lancement local

Ce guide permet de lancer VITA intégralement sur Mac et de tester le parcours complet (check-in → recommandation IA) dans le simulateur iOS.

---

## Prérequis système

| Outil | Version | Installation |
|---|---|---|
| Homebrew | — | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Node.js | 20+ | `brew install node@20 && echo 'export PATH="/opt/homebrew/opt/node@20/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc` |
| Python | 3.12+ | `brew install python@3.12` |
| Docker Desktop | — | Télécharger sur docker.com puis lancer l'app |
| XcodeGen | — | `brew install xcodegen` |
| Xcode | 15.4+ | App Store |

Vérification après installation :
```bash
node --version        # v20.x.x
python3.12 --version  # Python 3.12.x
docker --version      # Docker version 27.x
xcodegen --version    # XcodeGen version 2.x
```

---

## Étape 1 — Variables d'environnement

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita"
cp .env.example .env
```

Générer les secrets puis les coller dans `.env` :

```bash
openssl rand -hex 64   # → JWT_SECRET
openssl rand -hex 32   # → AI_SERVICE_TOKEN
```

Valeurs à renseigner dans `.env` :
```
JWT_SECRET=<résultat openssl rand -hex 64>
AI_SERVICE_TOKEN=<résultat openssl rand -hex 32>
ANTHROPIC_API_KEY=sk-ant-...
POSTGRES_PASSWORD=vita_dev_2025
REDIS_PASSWORD=redis_dev_2025
DATABASE_URL=postgresql://vita:vita_dev_2025@localhost:5432/vita
REDIS_URL=redis://:redis_dev_2025@localhost:6379
AI_ENGINE_URL=http://localhost:3003
ALLOWED_ORIGINS=http://localhost:3000
```

La clé `ANTHROPIC_API_KEY` s'obtient sur console.anthropic.com → API Keys.

---

## Étape 2 — Infrastructure (PostgreSQL + Redis)

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/infrastructure/docker"
docker compose up -d postgres redis
```

Attendre que les services soient sains (~10 secondes) :
```bash
docker compose ps
# postgres   healthy
# redis      healthy
```

---

## Étape 3 — Base de données

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita"
npm install
npm run db:migrate
```

Résultat attendu :
```
✓ Migration 001_init.sql exécutée
✓ Migration 002_remove_gamification.sql exécutée
Toutes les migrations ont été appliquées.
```

---

## Étape 4 — Auth Service (port 3001)

Ouvrir un terminal dédié :

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/backend/auth-service"
npm install && npm run dev
```

Vérification :
```bash
curl http://localhost:3001/health
# {"status":"ok","service":"auth-service"}
```

---

## Étape 5 — Data Service (port 3002)

Ouvrir un terminal dédié :

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/backend/data-service"
npm install && npm run dev
```

Vérification :
```bash
curl http://localhost:3002/health
# {"status":"ok","service":"data-service"}
```

---

## Étape 6 — AI Engine (port 3003)

Ouvrir un terminal dédié :

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/ai-engine"
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

Vérification :
```bash
curl http://localhost:3003/health
# {"status":"ok","service":"ai-engine"}
```

---

## Étape 7 — Application iOS

### 7a — Générer le projet Xcode

```bash
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/mobile/ios"
xcodegen generate
```

Résultat : `Vita.xcodeproj` est créé dans le dossier.

### 7b — Ouvrir dans Xcode

```bash
open "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/mobile/ios/Vita.xcodeproj"
```

### 7c — Configurer la signature

Dans Xcode :
1. Sélectionner le projet **Vita** dans le panneau de gauche
2. Onglet **Signing & Capabilities** → choisir ton Apple ID dans *Team*
3. Si conflit de Bundle ID : changer `com.vita.app` en `com.vita.app.dev`

### 7d — Lancer dans le simulateur

- Sélectionner un simulateur **iPhone** (iOS 17+) dans la barre de sélection
- `Cmd + R` pour compiler et lancer

**Note :** La première compilation prend 1-2 minutes (build complet). Les suivantes sont incrémentales.

---

## Étape 8 — Tester le parcours complet

### Créer un compte

1. L'app affiche l'écran d'authentification
2. Appuyer sur **Se connecter avec Apple**
3. Dans le simulateur : Features → Apple Pay and Passbook → Set up Face ID, puis utiliser ton Apple ID de développeur

> Alternative rapide : utiliser l'authentification email/mot de passe si elle est exposée par l'auth-service.

### Effectuer un check-in

1. Depuis l'accueil, appuyer sur la carte **Check-in du matin**
2. Question 1 : noter la qualité du sommeil (lunes)
3. Question 2 : noter l'énergie
4. Question 3 : indiquer une douleur éventuelle
5. Appuyer sur **Voir ma recommandation**

### Ce que tu dois observer

| Moment | Écran | Durée |
|---|---|---|
| Immédiatement | Écran de raisonnement (point animé) | — |
| ~0-2s | "Je relis nos échanges…" | — |
| ~2-5s | "J'analyse votre sommeil…" | — |
| ~5-7s | "Je compare avec vos habitudes…" | — |
| ~7-10s | Recommandation générée par Claude apparaît | — |
| Retour accueil | Carte recommandation visible sur HomeView | — |

---

## Architecture des ports

```
iOS App (simulateur)
    ↓ HTTP/SSE
├── :3001  auth-service   (JWT, inscription, connexion)
├── :3002  data-service   (check-ins, SSE, dashboard)  ← API_BASE_URL
└── :3003  ai-engine      (Claude, LangGraph)           ← interne uniquement
         ↓
    :5432  PostgreSQL (Docker)
    :6379  Redis (Docker)
```

En développement, `API_BASE_URL` dans `project.yml` pointe sur `:3002` (data-service).
L'auth utilise `:3001` — configurer les deux URLs si nécessaire dans `APIClient.swift`.

---

## Dépannage

**"Cannot connect to localhost"**
Vérifier que les services sont démarrés. Le simulateur iOS accède à `localhost` de la machine hôte directement.

**"AI Engine Timeout" ou pas de recommandation**
Vérifier que `ANTHROPIC_API_KEY` est renseignée et valide. Vérifier que l'ai-engine est démarré sur le port 3003.

**SSE se déconnecte immédiatement**
Le JWT token est peut-être expiré. Se déconnecter et reconnecter dans l'app.

**"xcodegen: command not found"**
`brew install xcodegen` puis fermer et rouvrir le terminal.

**Migrations échouent ("connection refused")**
Docker n'est pas lancé, ou PostgreSQL n'est pas encore `healthy`. Vérifier avec `docker compose ps`.

**Erreur de compilation Swift : "Cannot find type 'X'"**
Après `xcodegen generate`, Xcode doit être relancé pour indexer les nouveaux fichiers.

---

## Arrêter l'environnement

```bash
# Ctrl+C dans chaque terminal Node/Python
# Puis arrêter Docker :
cd "/Users/arnaultduhil/Desktop/Mairie Monclar/vita/infrastructure/docker"
docker compose down
```
