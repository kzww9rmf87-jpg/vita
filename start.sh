#!/usr/bin/env bash
# VITA — Démarrage de tous les services
# Usage : ./start.sh

set -euo pipefail

# Assure que Homebrew et les outils système sont accessibles dans un shell non-interactif
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

VITA_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS_DIR="$VITA_DIR/.vita/pids"
LOGS_DIR="$VITA_DIR/.vita/logs"
ENV_FILE="$VITA_DIR/.env"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# ── Prérequis ─────────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env introuvable. Lance d'abord : ./bootstrap.sh"
fi

# Charger les variables d'environnement
set -a; source "$ENV_FILE"; set +a

mkdir -p "$PIDS_DIR" "$LOGS_DIR"

echo -e "\n${BOLD}VITA — Démarrage${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Vérifier que des services ne tournent pas déjà ───────────────────────────
for pid_file in "$PIDS_DIR"/*.pid; do
  [[ -f "$pid_file" ]] || continue
  PID=$(cat "$pid_file")
  NAME=$(basename "$pid_file" .pid)
  if kill -0 "$PID" 2>/dev/null; then
    warn "$NAME tourne déjà (PID $PID). Lance ./stop.sh d'abord."
    exit 0
  else
    rm -f "$pid_file"
  fi
done

# ── 1. Docker ─────────────────────────────────────────────────────────────────
step "Infrastructure (PostgreSQL + Redis)"
if ! docker info &>/dev/null 2>&1; then
  fail "Docker n'est pas démarré. Ouvre Docker Desktop puis relance ./start.sh"
fi

cd "$VITA_DIR/infrastructure/docker"
docker compose up -d postgres redis

info() { echo -e "  ${NC}$1"; }

info "Attente que PostgreSQL soit prêt..."
TRIES=0
until docker compose exec -T postgres pg_isready -U vita &>/dev/null; do
  TRIES=$((TRIES+1))
  [[ $TRIES -gt 20 ]] && fail "PostgreSQL ne répond pas."
  sleep 2
done
ok "PostgreSQL"

info "Attente que Redis soit prêt..."
TRIES=0
until docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:-}" ping &>/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  [[ $TRIES -gt 10 ]] && fail "Redis ne répond pas."
  sleep 2
done
ok "Redis"

# ── 2. Auth Service ───────────────────────────────────────────────────────────
step "Auth Service (port 3001)"
cd "$VITA_DIR/backend/auth-service"

LOG="$LOGS_DIR/auth-service.log"
npm run dev > "$LOG" 2>&1 &
echo $! > "$PIDS_DIR/auth-service.pid"

# Attendre que le service écoute
TRIES=0
until curl -sf http://localhost:3001/health &>/dev/null; do
  TRIES=$((TRIES+1))
  if [[ $TRIES -gt 15 ]]; then
    fail "auth-service n'a pas démarré. Logs : $LOG"
  fi
  sleep 2
done
ok "Auth Service → http://localhost:3001"

# ── 3. Data Service ───────────────────────────────────────────────────────────
step "Data Service (port 3002)"
cd "$VITA_DIR/backend/data-service"

LOG="$LOGS_DIR/data-service.log"
npm run dev > "$LOG" 2>&1 &
echo $! > "$PIDS_DIR/data-service.pid"

TRIES=0
until curl -sf http://localhost:3002/health &>/dev/null; do
  TRIES=$((TRIES+1))
  if [[ $TRIES -gt 15 ]]; then
    fail "data-service n'a pas démarré. Logs : $LOG"
  fi
  sleep 2
done
ok "Data Service → http://localhost:3002"

# ── 4. AI Engine ──────────────────────────────────────────────────────────────
step "AI Engine (port 3003)"
cd "$VITA_DIR/ai-engine"

if [[ ! -d ".venv" ]]; then
  fail "Environnement Python introuvable. Lance d'abord : ./bootstrap.sh"
fi

LOG="$LOGS_DIR/ai-engine.log"
.venv/bin/python main.py > "$LOG" 2>&1 &
echo $! > "$PIDS_DIR/ai-engine.pid"

TRIES=0
until curl -sf http://localhost:3003/health &>/dev/null; do
  TRIES=$((TRIES+1))
  if [[ $TRIES -gt 20 ]]; then
    fail "ai-engine n'a pas démarré. Logs : $LOG"
  fi
  sleep 2
done
ok "AI Engine → http://localhost:3003"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  VITA est en ligne.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Auth    → ${BOLD}http://localhost:3001${NC}"
echo -e "  API     → ${BOLD}http://localhost:3002${NC}"
echo -e "  IA      → ${BOLD}http://localhost:3003${NC} (interne)"
echo ""
echo -e "  Lance iOS :   ${BOLD}./ios.sh${NC}"
echo -e "  Vérifier :    ${BOLD}./health.sh${NC}"
echo -e "  Arrêter :     ${BOLD}./stop.sh${NC}"
echo -e "  Logs :        ${BOLD}.vita/logs/${NC}"
echo ""
