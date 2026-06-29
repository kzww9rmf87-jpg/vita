#!/usr/bin/env bash
# VITA — Démarrage développement
# Applique les migrations pending, redémarre tous les services, vérifie la santé.
# Usage : ./dev.sh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

VITA_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS_DIR="$VITA_DIR/.vita/pids"
LOGS_DIR="$VITA_DIR/.vita/logs"
MIGRATIONS_DIR="$VITA_DIR/database/migrations"
ENV_FILE="$VITA_DIR/.env"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
info() { echo -e "  ${DIM}$1${NC}"; }

# ── Prérequis ─────────────────────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || fail ".env introuvable. Lance d'abord : ./bootstrap.sh"
set -a; source "$ENV_FILE"; set +a
mkdir -p "$PIDS_DIR" "$LOGS_DIR"

echo -e "\n${BOLD}VITA — Démarrage développement${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Arrêter les processus existants ────────────────────────────────────────
step "Nettoyage des processus existants"

for pid_file in "$PIDS_DIR"/*.pid; do
  [[ -f "$pid_file" ]] || continue
  PID=$(cat "$pid_file")
  NAME=$(basename "$pid_file" .pid)
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    sleep 0.5
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
    ok "$NAME arrêté (PID $PID)"
  fi
  rm -f "$pid_file"
done

# Libérer les ports au cas où des processus orphelins occupent les ports
for PORT in 3001 3002 3003; do
  PIDS=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$PIDS" ]]; then
    echo "$PIDS" | xargs kill 2>/dev/null || true
    sleep 0.3
    ok "Port $PORT libéré"
  fi
done

# ── 2. Docker ─────────────────────────────────────────────────────────────────
step "Infrastructure (PostgreSQL + Redis)"
docker info &>/dev/null 2>&1 || fail "Docker n'est pas démarré. Ouvre Docker Desktop."

cd "$VITA_DIR/infrastructure/docker"
docker compose up -d postgres redis

info "Attente que PostgreSQL soit prêt..."
TRIES=0
until docker compose exec -T postgres pg_isready -U vita &>/dev/null; do
  TRIES=$((TRIES+1)); [[ $TRIES -gt 20 ]] && fail "PostgreSQL ne répond pas."; sleep 2
done
ok "PostgreSQL"

info "Attente que Redis soit prêt..."
TRIES=0
until docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:-}" ping &>/dev/null 2>&1; do
  TRIES=$((TRIES+1)); [[ $TRIES -gt 10 ]] && fail "Redis ne répond pas."; sleep 2
done
ok "Redis"

# ── 3. Migrations ─────────────────────────────────────────────────────────────
step "Migrations PostgreSQL"

# Récupérer les migrations déjà appliquées
APPLIED=$(docker compose exec -T postgres psql -U vita -d vita -At \
  -c "SELECT filename FROM schema_migrations ORDER BY filename;" 2>/dev/null || echo "")

PENDING=0
APPLIED_COUNT=0

for MIGRATION_FILE in "$MIGRATIONS_DIR"/*.sql; do
  [[ -f "$MIGRATION_FILE" ]] || continue
  FILENAME=$(basename "$MIGRATION_FILE")

  if echo "$APPLIED" | grep -qxF "$FILENAME"; then
    APPLIED_COUNT=$((APPLIED_COUNT+1))
    info "  $FILENAME — déjà appliquée"
  else
    echo -e "  ${YELLOW}→${NC} Application de ${BOLD}$FILENAME${NC}..."
    if docker compose exec -T postgres psql -U vita -d vita \
        -v ON_ERROR_STOP=1 -f - < "$MIGRATION_FILE" > /dev/null 2>&1; then
      # Enregistrer dans schema_migrations si pas déjà fait par la migration elle-même
      docker compose exec -T postgres psql -U vita -d vita -c \
        "INSERT INTO schema_migrations (filename) VALUES ('$FILENAME') ON CONFLICT DO NOTHING;" \
        > /dev/null 2>&1 || true
      ok "$FILENAME appliquée"
      PENDING=$((PENDING+1))
    else
      warn "$FILENAME — échec (vérifier manuellement)"
    fi
  fi
done

if [[ $PENDING -eq 0 ]]; then
  ok "Toutes les migrations sont à jour ($APPLIED_COUNT appliquées)"
else
  ok "$PENDING migration(s) appliquée(s), $APPLIED_COUNT déjà présentes"
fi

# ── 4. Auth Service ───────────────────────────────────────────────────────────
step "Auth Service (port 3001)"
cd "$VITA_DIR/backend/auth-service"
LOG="$LOGS_DIR/auth-service.log"
npm run dev > "$LOG" 2>&1 &
echo $! > "$PIDS_DIR/auth-service.pid"

TRIES=0
until curl -sf http://localhost:3001/health &>/dev/null; do
  TRIES=$((TRIES+1))
  [[ $TRIES -gt 20 ]] && fail "auth-service n'a pas démarré. Logs : $LOG"
  sleep 2
done
ok "Auth Service → http://localhost:3001"

# ── 5. Data Service ───────────────────────────────────────────────────────────
step "Data Service (port 3002)"
cd "$VITA_DIR/backend/data-service"
LOG="$LOGS_DIR/data-service.log"
npm run dev > "$LOG" 2>&1 &
echo $! > "$PIDS_DIR/data-service.pid"

TRIES=0
until curl -sf http://localhost:3002/health &>/dev/null; do
  TRIES=$((TRIES+1))
  [[ $TRIES -gt 20 ]] && fail "data-service n'a pas démarré. Logs : $LOG"
  sleep 2
done
ok "Data Service → http://localhost:3002"

# ── 6. AI Engine (uvicorn --reload) ──────────────────────────────────────────
step "AI Engine (port 3003, hot-reload)"
cd "$VITA_DIR/ai-engine"
[[ -d ".venv" ]] || fail "Environnement Python introuvable. Lance ./bootstrap.sh"
[[ -f ".venv/bin/uvicorn" ]] || fail ".venv/bin/uvicorn introuvable. Lance ./bootstrap.sh"

LOG="$LOGS_DIR/ai-engine.log"
.venv/bin/uvicorn main:app --host 0.0.0.0 --port 3003 --reload > "$LOG" 2>&1 &
echo $! > "$PIDS_DIR/ai-engine.pid"

TRIES=0
until curl -sf http://localhost:3003/health &>/dev/null; do
  TRIES=$((TRIES+1))
  [[ $TRIES -gt 20 ]] && fail "ai-engine n'a pas démarré. Logs : $LOG"
  sleep 2
done
ok "AI Engine → http://localhost:3003 (hot-reload actif)"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  VITA dev est en ligne.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Auth    → ${BOLD}http://localhost:3001${NC}"
echo -e "  API     → ${BOLD}http://localhost:3002${NC}"
echo -e "  IA      → ${BOLD}http://localhost:3003${NC} (hot-reload)"
echo ""
echo -e "  Logs    → ${BOLD}.vita/logs/${NC}"
echo -e "           auth-service : ${DIM}tail -f .vita/logs/auth-service.log${NC}"
echo -e "           data-service : ${DIM}tail -f .vita/logs/data-service.log${NC}"
echo -e "           ai-engine    : ${DIM}tail -f .vita/logs/ai-engine.log${NC}"
echo ""
echo -e "  Lance iOS : ${BOLD}./ios.sh${NC}"
echo -e "  Santé :    ${BOLD}./health.sh${NC}"
echo -e "  Arrêter :  ${BOLD}./stop.sh${NC}"
echo ""
