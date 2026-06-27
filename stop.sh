#!/usr/bin/env bash
# VITA — Arrêt de tous les services
# Usage : ./stop.sh

VITA_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDS_DIR="$VITA_DIR/.vita/pids"
ENV_FILE="$VITA_DIR/.env"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

echo -e "\n${BOLD}VITA — Arrêt${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Services Node / Python ────────────────────────────────────────────────────
step "Services applicatifs"

for SERVICE in auth-service data-service ai-engine; do
  PID_FILE="$PIDS_DIR/$SERVICE.pid"
  if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      # Arrêt propre (SIGTERM) puis forçage si nécessaire
      kill "$PID" 2>/dev/null || true
      sleep 1
      if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
      fi
      ok "$SERVICE arrêté"
    else
      warn "$SERVICE n'était pas actif"
    fi
    rm -f "$PID_FILE"
  else
    warn "$SERVICE — pas de PID (démarré hors de start.sh ?)"
  fi
done

# Nettoyage défensif : tuer les processus sur les ports connus au cas où
for PORT in 3001 3002 3003; do
  PID=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$PID" ]]; then
    kill "$PID" 2>/dev/null || true
    ok "Port $PORT libéré"
  fi
done

# ── Docker ────────────────────────────────────────────────────────────────────
step "Infrastructure Docker"
if docker info &>/dev/null 2>&1; then
  cd "$VITA_DIR/infrastructure/docker"
  if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
  fi
  docker compose stop postgres redis
  ok "PostgreSQL et Redis arrêtés (données conservées)"
else
  warn "Docker n'est pas actif — rien à arrêter"
fi

echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  VITA est arrêté.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Pour redémarrer : ${BOLD}./start.sh${NC}"
echo ""
