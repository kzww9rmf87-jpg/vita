"""
Détection de signaux de sécurité dans les entrées de journal.

Ce module est volontairement conservateur : il préfère les faux positifs
aux faux négatifs. Mieux vaut déclencher une ressource inutile que manquer
une détresse réelle.

Niveaux de sévérité :
  critical  — idéation active, plan, urgence immédiate
  high      — idéation passive récurrente, désespoir profond
  medium    — signaux d'alarme sans idéation claire
  low       — vocabulaire de désespoir sans signaux clairs

Catégories :
  ideation_active   — pensées suicidaires avec intention ou plan
  ideation_passive  — "je voudrais ne plus être là", sans plan apparent
  self_harm         — automutilation, comportements autodestructeurs
  hopelessness      — sentiment durable de sans-issue
  crisis            — urgence non spécifiée, demande d'aide explicite
"""
import re
import logging
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)

# ── Ressource nationale ──────────────────────────────────────────────────────

CRISIS_RESOURCE = (
    "Si tu traverses une période difficile, le **3114** "
    "(numéro national de prévention du suicide, disponible 24h/24) "
    "peut t'accompagner avec bienveillance."
)

# ── Règles de détection ──────────────────────────────────────────────────────
#
# Structure : (pattern_regex, category, severity, weight)
# Les règles sont évaluées dans l'ordre ; le score final détermine le niveau.

_RULES: list[tuple[str, str, str, int]] = [
    # Critical — idéation active avec plan ou acte
    (r"\bje vais (me suicider|me tuer|en finir)\b", "ideation_active", "critical", 10),
    (r"\bj'ai (un plan|décidé de)\b.{0,30}(mourir|me tuer|fin de vie)", "ideation_active", "critical", 10),
    (r"\blettre d'adieu\b", "ideation_active", "critical", 10),
    (r"\bprise de médicaments?\b.{0,20}(en grande quantité|overdose|tous)", "ideation_active", "critical", 8),

    # High — idéation passive explicite
    (r"\bje (veux|voudrais|aimerais) (mourir|ne plus exister|ne plus être là)\b", "ideation_passive", "high", 7),
    (r"\bje (pense|songe) (à la mort|au suicide|à mourir)\b", "ideation_passive", "high", 7),
    (r"\bplus personne ne me manquerait\b", "ideation_passive", "high", 6),
    (r"\bla vie ne vaut (plus rien|pas la peine)\b", "hopelessness", "high", 5),
    (r"\bje me (blesse|bless|coupe|brûle) (volontairement|moi-même|pour)\b", "self_harm", "high", 7),

    # Medium — signaux d'alarme sans idéation claire
    (r"\bje n'(en peux|en veux) plus\b", "hopelessness", "medium", 3),
    (r"\btout (s'arrêter|stopper|lâcher)\b", "hopelessness", "medium", 3),
    (r"\bje suis (épuisé|à bout|vidé).{0,30}(plus envie|sans espoir|fini)", "hopelessness", "medium", 3),
    (r"\bj'ai besoin d'aide\b", "crisis", "medium", 4),
    (r"\bau secours\b", "crisis", "medium", 5),
    (r"\bplus aucun espoir\b", "hopelessness", "medium", 4),

    # Low — vocabulaire dépressif sans signaux clairs
    (r"\bà quoi ça sert\b", "hopelessness", "low", 1),
    (r"\bje (ne sers|ne vaux) (à rien|rien)\b", "hopelessness", "low", 2),
    (r"\btout est (inutile|vain|nul)\b", "hopelessness", "low", 1),
]

_SEVERITY_THRESHOLDS = {
    "critical": 8,
    "high": 5,
    "medium": 3,
    "low": 1,
}


@dataclass
class SafetyResult:
    has_flag: bool = False
    severity: str = "none"           # none | low | medium | high | critical
    category: str = ""
    excerpt: str = ""                # ≤ 200 chars
    needs_immediate_resource: bool = False
    resource_message: Optional[str] = None
    matched_rules: list[str] = field(default_factory=list)


def detect_safety_signals(text: str) -> SafetyResult:
    """
    Analyse un texte et retourne un SafetyResult.
    Ne lève jamais d'exception — toujours retourne un résultat.
    """
    try:
        return _analyze(text)
    except Exception as exc:
        logger.error("[SAFETY] Unexpected error during analysis: %s", exc)
        return SafetyResult()


def _analyze(text: str) -> SafetyResult:
    if not text or len(text.strip()) < 5:
        return SafetyResult()

    normalized = text.lower()
    score = 0
    top_category = ""
    top_severity = "none"
    matched_rules: list[str] = []
    first_match_pos = len(text)
    excerpt_start = 0

    for pattern, category, severity, weight in _RULES:
        match = re.search(pattern, normalized)
        if match:
            score += weight
            matched_rules.append(f"{severity}:{category}")

            # Garde la règle avec le plus haut poids comme catégorie principale
            if weight >= score - weight:  # cette règle contribue majoritairement
                top_category = category
                top_severity = severity

            if match.start() < first_match_pos:
                first_match_pos = match.start()
                excerpt_start = max(0, match.start() - 20)

    if score == 0:
        return SafetyResult()

    # Détermine le niveau final selon le score cumulé
    final_severity = "low"
    for sev in ("critical", "high", "medium", "low"):
        if score >= _SEVERITY_THRESHOLDS[sev]:
            final_severity = sev
            break

    # Si une règle critical a matché, force le niveau
    for rule in matched_rules:
        if rule.startswith("critical:"):
            final_severity = "critical"
            top_severity = "critical"
            break
    for rule in matched_rules:
        if rule.startswith("high:") and final_severity not in ("critical",):
            final_severity = "high"
            break

    # Extrait ≤ 200 chars autour du premier signal
    excerpt_end = min(len(text), excerpt_start + 200)
    excerpt = text[excerpt_start:excerpt_end].strip()

    needs_immediate = final_severity in ("critical", "high")

    return SafetyResult(
        has_flag=True,
        severity=final_severity,
        category=top_category or (matched_rules[0].split(":")[1] if matched_rules else ""),
        excerpt=excerpt,
        needs_immediate_resource=needs_immediate,
        resource_message=CRISIS_RESOURCE if needs_immediate else None,
        matched_rules=matched_rules,
    )


def build_crisis_prefix(result: SafetyResult) -> str:
    """
    Préfixe à injecter en tête de la réponse VITA quand un signal critique est détecté.
    Court, chaleureux, non-alarmiste dans la forme — mais oriente vers l'aide humaine.
    """
    if result.severity == "critical":
        return (
            "Ce que tu partages me touche profondément, et je veux être honnête avec toi : "
            "ce que tu décris dépasse ce que je peux accompagner seule. "
            f"{CRISIS_RESOURCE} "
            "Tu mérites une présence humaine, pas seulement des mots sur un écran.\n\n"
        )
    if result.severity == "high":
        return (
            "Je t'entends. Ce que tu traverses est lourd, et je ne veux pas minimiser ça. "
            f"{CRISIS_RESOURCE}\n\n"
        )
    return ""
