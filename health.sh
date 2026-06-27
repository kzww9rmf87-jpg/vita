#!/usr/bin/env bash
# VITA — Vérification de l'état de tous les services
# Usage : ./health.sh

VITA_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$VITA_DIR/.env"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

ALL_OK=true

check() {
  local NAME="$1"
  local URL="$2"
  local EXPECTED="$3"

  RESPONSE=$(curl -sf --max-time 3 "$URL" 2>/dev/null || echo "")

  if [[ -z "$RESPONSE" ]]; then
    echo -e "  ${RED}✗${NC} ${BOLD}$NAME${NC} — ne répond pas  ${DIM}($URL)${NC}"
    ALL_OK=false
  elif echo "$RESPONSE" | grep -q "$EXPECTED"; then
    echo -e "  ${GREEN}✓${NC} ${BOLD}$NAME${NC}  ${DIM}($URL)${NC}"
  else
    echo -e "  ${YELLOW}⚠${NC}  ${BOLD}$NAME${NC} — réponse inattendue  ${DIM}($URL)${NC}"
    echo -e "     ${DIM}$RESPONSE${NC}"
    ALL_OK=false
  fi
}

check_docker_service() {
  local NAME="$1"
  local CONTAINER="$2"

  if ! docker info &>/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} ${BOLD}$NAME${NC} — Docker non actif"
    ALL_OK=false
    return
  fi

  STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "absent")
  case "$STATUS" in
    healthy)
      echo -e "  ${GREEN}✓${NC} ${BOLD}$NAME${NC}  ${DIM}(container: $CONTAINER)${NC}"
      ;;
    starting)
      echo -e "  ${YELLOW}⚠${NC}  ${BOLD}$NAME${NC} — démarrage en cours..."
      ALL_OK=false
      ;;
    absent|"")
      echo -e "  ${RED}✗${NC} ${BOLD}$NAME${NC} — container introuvable"
      ALL_OK=false
      ;;
    *)
      echo -e "  ${RED}✗${NC} ${BOLD}$NAME${NC} — état : $STATUS"
      ALL_OK=false
      ;;
  esac
}

echo -e "\n${BOLD}VITA — État des services${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n${CYAN}Infrastructure${NC}"
check_docker_service "PostgreSQL" "vita-postgres"
check_docker_service "Redis" "vita-redis"

echo -e "\n${CYAN}Services${NC}"
check "Auth Service   " "http://localhost:3001/health" "ok"
check "Data Service   " "http://localhost:3002/health" "ok"
check "AI Engine      " "http://localhost:3003/health" "ok"

# ── Vérification de la clé Anthropic ─────────────────────────────────────────
echo -e "\n${CYAN}Configuration${NC}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE" 2>/dev/null; set +a
  if [[ -n "${ANTHROPIC_API_KEY:-}" && "$ANTHROPIC_API_KEY" != "sk-ant-your-key-here" ]]; then
    echo -e "  ${GREEN}✓${NC} ${BOLD}Clé Anthropic${NC} configurée"
  else
    echo -e "  ${RED}✗${NC} ${BOLD}Clé Anthropic${NC} manquante — édite .env"
    ALL_OK=false
  fi
  if [[ -n "${JWT_SECRET:-}" && "${#JWT_SECRET}" -ge 64 ]]; then
    echo -e "  ${GREEN}✓${NC} ${BOLD}JWT_SECRET${NC} (${#JWT_SECRET} caractères)"
  else
    echo -e "  ${YELLOW}⚠${NC}  ${BOLD}JWT_SECRET${NC} trop court (minimum 64 caractères)"
    ALL_OK=false
  fi
else
  echo -e "  ${RED}✗${NC} ${BOLD}.env${NC} introuvable — lance ./bootstrap.sh"
  ALL_OK=false
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if $ALL_OK; then
  echo -e "${GREEN}${BOLD}  ✅  Tous les services sont opérationnels.${NC}"
  echo ""
  echo -e "  VITA est prêt. Lance l'app iOS avec : ${BOLD}./ios.sh${NC}"
else
  echo -e "${RED}${BOLD}  ❌  Certains services ne répondent pas.${NC}"
  echo ""
  echo -e "  Si VITA n'est pas démarré : ${BOLD}./start.sh${NC}"
  echo -e "  Si c'est un premier lancement : ${BOLD}./bootstrap.sh${NC}"
fi
echo ""
