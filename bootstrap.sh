#!/usr/bin/env bash
# VITA — Installation complète de l'environnement de développement
# Usage : ./bootstrap.sh

set -euo pipefail

VITA_DIR="$(cd "$(dirname "$0")" && pwd)"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }
info()  { echo -e "  ${NC}$1"; }

echo -e "\n${BOLD}VITA — Bootstrap${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
step "Homebrew"
if ! command -v brew &>/dev/null; then
  info "Installation de Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Ajouter Homebrew au PATH si Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  ok "Homebrew déjà installé ($(brew --version | head -1))"
fi

# ── 2. Node.js 20 ────────────────────────────────────────────────────────────
step "Node.js 20"
if command -v node &>/dev/null && [[ "$(node --version | cut -d. -f1 | tr -d 'v')" -ge 20 ]]; then
  ok "Node.js $(node --version) déjà installé"
else
  info "Installation de Node.js 20..."
  brew install node@20
  # Lier node@20 s'il y a une version conflictuelle
  brew link --overwrite node@20 2>/dev/null || true
  export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
  ok "Node.js $(node --version) installé"
fi

# ── 3. Python 3.12 ───────────────────────────────────────────────────────────
step "Python 3.12"
PYTHON=""
for candidate in python3.12 python3; do
  if command -v "$candidate" &>/dev/null; then
    VER=$("$candidate" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    MAJOR=$(echo "$VER" | cut -d. -f1)
    MINOR=$(echo "$VER" | cut -d. -f2)
    if [[ "$MAJOR" -ge 3 && "$MINOR" -ge 12 ]]; then
      PYTHON="$candidate"
      break
    fi
  fi
done

if [[ -n "$PYTHON" ]]; then
  ok "Python $("$PYTHON" --version) déjà installé"
else
  info "Installation de Python 3.12..."
  brew install python@3.12
  PYTHON=python3.12
  ok "Python $($PYTHON --version) installé"
fi

# ── 4. Docker Desktop ────────────────────────────────────────────────────────
step "Docker Desktop"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  ok "Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) actif"
else
  if command -v docker &>/dev/null; then
    warn "Docker est installé mais pas démarré."
    info "Lance Docker Desktop depuis Applications, puis relance bootstrap.sh"
    echo ""
    info "Pour installer : brew install --cask docker"
    exit 1
  else
    info "Installation de Docker Desktop..."
    brew install --cask docker
    warn "Docker Desktop a été installé. Lance-le depuis Applications puis relance :"
    info "  ./bootstrap.sh"
    exit 0
  fi
fi

# ── 5. XcodeGen ──────────────────────────────────────────────────────────────
step "XcodeGen"
if command -v xcodegen &>/dev/null; then
  ok "XcodeGen $(xcodegen --version 2>/dev/null || echo '') déjà installé"
else
  info "Installation de XcodeGen..."
  brew install xcodegen
  ok "XcodeGen installé"
fi

# ── 6. Fichier .env ──────────────────────────────────────────────────────────
step "Configuration (.env)"
ENV_FILE="$VITA_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$VITA_DIR/.env.example" "$ENV_FILE"
  info "Fichier .env créé depuis .env.example"
fi

# Générer JWT_SECRET si vide ou non modifié
if grep -qE "^JWT_SECRET=(your_super_secret|changeme|$)" "$ENV_FILE"; then
  NEW_JWT=$(openssl rand -hex 64)
  # sed compatible macOS
  sed -i '' "s|^JWT_SECRET=.*|JWT_SECRET=$NEW_JWT|" "$ENV_FILE"
  ok "JWT_SECRET généré automatiquement"
else
  ok "JWT_SECRET déjà configuré"
fi

# Générer AI_SERVICE_TOKEN si vide ou non modifié
if grep -qE "^AI_SERVICE_TOKEN=(your_inter_service|changeme|$)" "$ENV_FILE"; then
  NEW_TOKEN=$(openssl rand -hex 32)
  sed -i '' "s|^AI_SERVICE_TOKEN=.*|AI_SERVICE_TOKEN=$NEW_TOKEN|" "$ENV_FILE"
  ok "AI_SERVICE_TOKEN généré automatiquement"
else
  ok "AI_SERVICE_TOKEN déjà configuré"
fi

# Générer des mots de passe DB/Redis cohérents si non modifiés
if grep -qE "^POSTGRES_PASSWORD=changeme" "$ENV_FILE"; then
  NEW_PG_PASS="vita_$(openssl rand -hex 8)"
  sed -i '' "s|^POSTGRES_PASSWORD=changeme|POSTGRES_PASSWORD=$NEW_PG_PASS|" "$ENV_FILE"
  # Mettre à jour DATABASE_URL en conséquence
  sed -i '' "s|postgresql://vita:changeme@|postgresql://vita:$NEW_PG_PASS@|" "$ENV_FILE"
  ok "Mot de passe PostgreSQL généré"
fi

if grep -qE "^REDIS_PASSWORD=changeme" "$ENV_FILE"; then
  NEW_REDIS_PASS="redis_$(openssl rand -hex 8)"
  sed -i '' "s|^REDIS_PASSWORD=changeme|REDIS_PASSWORD=$NEW_REDIS_PASS|" "$ENV_FILE"
  sed -i '' "s|redis://:changeme@|redis://:$NEW_REDIS_PASS@|" "$ENV_FILE"
  ok "Mot de passe Redis généré"
fi

# Vérifier ANTHROPIC_API_KEY
ANTHROPIC_KEY=$(grep "^ANTHROPIC_API_KEY=" "$ENV_FILE" | cut -d= -f2-)
if [[ -z "$ANTHROPIC_KEY" || "$ANTHROPIC_KEY" == "sk-ant-your-key-here" ]]; then
  echo ""
  echo -e "  ${YELLOW}${BOLD}Action requise — Clé Anthropic${NC}"
  info "VITA a besoin d'une clé API Anthropic pour générer les recommandations."
  info "Obtiens ta clé sur : https://console.anthropic.com/settings/keys"
  echo ""
  printf "  Entre ta clé Anthropic (sk-ant-...) : "
  read -r ANTHROPIC_INPUT
  if [[ -n "$ANTHROPIC_INPUT" ]]; then
    sed -i '' "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$ANTHROPIC_INPUT|" "$ENV_FILE"
    ok "Clé Anthropic enregistrée"
  else
    warn "Clé non renseignée — les recommandations IA ne fonctionneront pas"
    warn "Édite .env et ajoute : ANTHROPIC_API_KEY=sk-ant-..."
  fi
else
  ok "Clé Anthropic configurée"
fi

# ── 7. Dépendances Node.js ───────────────────────────────────────────────────
step "Dépendances Node.js"
cd "$VITA_DIR"
npm install --silent
ok "Dépendances racine installées"

cd "$VITA_DIR/backend/auth-service"
npm install --silent
ok "auth-service"

cd "$VITA_DIR/backend/data-service"
npm install --silent
ok "data-service"

# ── 8. Environnement Python ──────────────────────────────────────────────────
step "Environnement Python (ai-engine)"
cd "$VITA_DIR/ai-engine"

if [[ ! -d ".venv" ]]; then
  $PYTHON -m venv .venv
  info "Environnement virtuel créé"
fi

source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
deactivate
ok "Dépendances Python installées"

# ── 9. Infrastructure Docker (PostgreSQL + Redis) ────────────────────────────
step "Infrastructure Docker"
cd "$VITA_DIR/infrastructure/docker"

# Charger les variables d'env pour docker compose
set -a; source "$ENV_FILE"; set +a

docker compose up -d postgres redis

info "Attente que PostgreSQL et Redis soient prêts..."
TRIES=0
while ! docker compose exec -T postgres pg_isready -U vita &>/dev/null; do
  TRIES=$((TRIES+1))
  if [[ $TRIES -gt 20 ]]; then
    fail "PostgreSQL n'a pas démarré dans les temps."
    exit 1
  fi
  sleep 2
done
ok "PostgreSQL prêt"

TRIES=0
while ! docker compose exec -T redis redis-cli -a "$REDIS_PASSWORD" ping &>/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  if [[ $TRIES -gt 10 ]]; then
    fail "Redis n'a pas démarré dans les temps."
    exit 1
  fi
  sleep 2
done
ok "Redis prêt"

# ── 10. Migrations base de données ───────────────────────────────────────────
step "Migrations base de données"
cd "$VITA_DIR"
npm run db:migrate
ok "Migrations appliquées"

# ── Résumé ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Bootstrap terminé avec succès.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Lance VITA avec :  ${BOLD}./start.sh${NC}"
echo -e "  Lance iOS avec :   ${BOLD}./ios.sh${NC}"
echo ""
