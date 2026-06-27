#!/usr/bin/env bash
# VITA — Génération du projet Xcode et ouverture dans Xcode
# Usage : ./ios.sh

set -euo pipefail

VITA_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$VITA_DIR/mobile/ios"
PROJECT="$IOS_DIR/Vita.xcodeproj"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
info() { echo -e "  ${NC}$1"; }

echo -e "\n${BOLD}VITA — iOS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Vérifier Xcode ────────────────────────────────────────────────────────────
step "Vérification de Xcode"
if ! command -v xcodebuild &>/dev/null; then
  fail "Xcode n'est pas installé. Installe-le depuis l'App Store."
fi
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1)
ok "$XCODE_VER"

# ── Vérifier XcodeGen ─────────────────────────────────────────────────────────
step "Vérification de XcodeGen"
if ! command -v xcodegen &>/dev/null; then
  info "XcodeGen non trouvé. Installation..."
  brew install xcodegen
fi
ok "XcodeGen disponible"

# ── Générer le projet Xcode ───────────────────────────────────────────────────
step "Génération du projet Xcode"
cd "$IOS_DIR"
xcodegen generate --spec project.yml --project .
ok "Vita.xcodeproj généré"

# ── Ouvrir dans Xcode ─────────────────────────────────────────────────────────
step "Ouverture dans Xcode"
if [[ ! -d "$PROJECT" ]]; then
  fail "Vita.xcodeproj introuvable après génération."
fi
open "$PROJECT"
ok "Xcode ouvert"

echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Projet iOS ouvert dans Xcode.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Dans Xcode :"
echo -e "  1. Sélectionne un simulateur ${BOLD}iPhone${NC} (iOS 17+)"
echo -e "  2. Onglet Signing & Capabilities → choisis ton ${BOLD}Apple ID${NC}"
echo -e "  3. Lance avec ${BOLD}Cmd + R${NC}"
echo ""
info "Si VITA n'est pas démarré : ./start.sh"
echo ""
