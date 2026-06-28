"""
Agent Synthèse — Fusionne toutes les analyses et produit UNE observation
prioritaire + 3 actions concrètes pour la journée.

Philosophie (FOUNDING_PRINCIPLES.md §10) :
- Le Synthesis Agent est le moment où VITA parle directement
- Une observation. Jamais deux.
- Trois actions : concrètes, réalistes, non culpabilisantes
- Ton : Témoin Bienveillant — observe, éclaire, n'impose pas
"""
import json as json_module
import logging
import anthropic
from typing import Optional
from models import AgentSignal, Recommendation, UserContext
from config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

_SYNTHESIS_SYSTEM_PROMPT = """Tu es VITA, un Témoin Bienveillant. Tu formules l'observation du jour et 3 actions concrètes.

Réponds UNIQUEMENT en JSON valide, sans markdown, sans texte avant ou après :
{
  "observation": "1 à 2 phrases max. Montre que tu as vraiment regardé cette personne spécifique.",
  "actions": [
    "action concrète 1 (< 10 mots)",
    "action concrète 2 (< 10 mots)",
    "action concrète 3 (< 10 mots)"
  ]
}

Règles pour l'observation :
- 50 mots maximum
- Jamais "tu devrais", "il faut", "je te recommande"
- Pas de culpabilisation, honte ou comparaison
- La première phrase prouve que tu as regardé cette personne, pas une autre
- Deuxième personne du singulier (tu)

Règles pour les 3 actions :
- Réalisables aujourd'hui, concrètes, courtes
- Adaptées à l'état du jour (énergie, signaux)
- Pas de guillemets dans les actions
- Exemples valides : "Marcher 20 minutes", "Coucher avant 22h30", "Protéines au dîner"
"""


async def synthesize(
    signals: list[AgentSignal],
    ctx: UserContext,
) -> Optional[Recommendation]:
    if not signals:
        return _generate_maintenance_recommendation(ctx)

    ranked = sorted(
        signals,
        key=lambda s: s.urgency * s.impact * s.confidence,
        reverse=True,
    )
    top_signal = ranked[0]
    context_signals = ranked[1:3] if len(ranked) > 1 else []

    return await _generate_recommendation_with_claude(top_signal, context_signals, ctx)


async def _generate_recommendation_with_claude(
    primary: AgentSignal,
    context: list[AgentSignal],
    ctx: UserContext,
) -> Recommendation:
    profile = ctx.profile or {}
    checkin = ctx.checkin_morning or {}

    context_text = ""
    if context:
        context_text = "\n\nObservations complémentaires :\n" + "\n".join(
            f"- [{s.agent}] {s.description}" for s in context
        )

    user_message = f"""Observation principale :
Agent : {primary.agent}
Signal : {primary.signal_type}
Situation : {primary.description}
{context_text}

Contexte de l'utilisateur :
- Objectif : {profile.get("primary_goal", "non défini")}
- Énergie ce matin : {checkin.get("energy", "?")} /5
- Humeur : {checkin.get("mood", "?")} /5
- Stress : {checkin.get("stress", "?")} /5

Génère l'observation et les 3 actions en JSON :"""

    try:
        message = await client.messages.create(
            model=settings.model_fast,
            max_tokens=settings.max_tokens_recommendation,
            system=_SYNTHESIS_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = message.content[0].text.strip()
        observation, actions = _parse_claude_response(raw)
    except Exception as exc:
        logger.warning("[synthesis] Claude unavailable (%s) — using rule-based fallback", exc)
        observation = _fallback_observation(primary, ctx)
        actions = _fallback_actions(primary.signal_type, ctx)

    short = observation.split(".")[0] + "." if "." in observation else observation[:100]

    return Recommendation(
        content=observation,
        content_short=short[:100],
        action_type=_signal_to_action(primary.signal_type),
        agent_source=primary.agent,
        reasoning={
            "primary_signal": primary.model_dump(),
            "context_signals": [s.model_dump() for s in context],
            "model": settings.model_fast,
        },
        confidence=primary.confidence,
        actions=actions,
    )


def _parse_claude_response(raw: str) -> tuple[str, list[str]]:
    """Parse la réponse JSON de Claude. Retourne (observation, actions)."""
    text = raw
    # Enlève les blocs markdown si Claude les a ajoutés malgré la consigne
    if "```json" in text:
        text = text.split("```json")[1].split("```")[0].strip()
    elif "```" in text:
        text = text.split("```")[1].split("```")[0].strip()

    try:
        parsed = json_module.loads(text)
        observation = str(parsed.get("observation", "")).strip()
        actions_raw = parsed.get("actions", [])
        actions = [str(a).strip() for a in actions_raw if str(a).strip()][:3]
        if observation and len(actions) == 3:
            return observation, actions
    except (json_module.JSONDecodeError, KeyError, TypeError):
        pass

    # Dernier recours : le texte brut comme observation, sans actions
    raise ValueError(f"Could not parse Claude response: {raw[:200]}")


def _fallback_observation(primary: AgentSignal, ctx: UserContext) -> str:
    """Observation textuelle quand Claude est indisponible."""
    checkin = ctx.checkin_morning or {}
    energy = int(checkin.get("energy", 3) or 3)

    if energy <= 2:
        return "Énergie basse ce matin. Les données des derniers jours racontent la même histoire."
    if primary.signal_type in ("overtraining_risk", "high_fatigue"):
        return "Ton corps a encaissé beaucoup ces derniers jours. La récupération fait partie de la progression."
    if primary.signal_type in ("sleep_debt", "poor_quality"):
        return "Le sommeil de cette semaine n'a pas été suffisant. C'est là que commence la fatigue."
    if primary.signal_type in ("low_protein",):
        return "Les protéines sont en dessous de ce dont ton objectif a besoin. Ça se règle facilement."
    return "Continue sur ta lancée. La régularité est ton meilleur atout."


def _fallback_actions(signal_type: str, ctx: UserContext) -> list[str]:
    """3 actions rule-based quand Claude est indisponible."""
    checkin = ctx.checkin_morning or {}
    energy = int(checkin.get("energy", 3) or 3)
    sleep = ctx.sleep or {}
    duration_min = sleep.get("duration_minutes", 0) or 0

    lookup: dict[str, list[str]] = {
        "overtraining_risk": [
            "Repos actif : marche légère, pas de salle",
            "Dormir au moins 8h cette nuit",
            "Hydratation : 2L d'eau minimum",
        ],
        "sleep_debt": [
            "Coucher avant 22h30 ce soir",
            "Pas d'écran 30 min avant de dormir",
            "Séance légère si tu t'entraînes aujourd'hui",
        ],
        "late_training": [
            "Décaler l'entraînement avant 19h si possible",
            "Routine de coucher à heure fixe",
            "Lumière tamisée 1h avant de dormir",
        ],
        "poor_quality": [
            "Coucher 30 min plus tôt que d'habitude",
            "Pas de caféine après 14h",
            "10 min de respiration profonde avant de dormir",
        ],
        "low_protein": [
            "Source de protéines à chaque repas",
            "Collation protéinée dans l'après-midi",
            "Viser 120g de protéines aujourd'hui",
        ],
        "alcohol_pattern": [
            "Journée sans alcool",
            "2L d'eau dans la journée",
            "Repas équilibré le soir",
        ],
        "dehydration_risk": [
            "1 grand verre d'eau dès maintenant",
            "2L d'eau minimum aujourd'hui",
            "Eau avant chaque repas",
        ],
        "mental_overload": [
            "5 min de respiration profonde ce matin",
            "Marche de 15 min sans téléphone",
            "Couper les notifications 1h ce soir",
        ],
        "dropout_risk": [
            "Séance courte plutôt qu'aucune séance",
            "20 min suffisent aujourd'hui",
            "Note ce que tu ressens après",
        ],
        "stagnation": [
            "Varier l'exercice principal aujourd'hui",
            "Augmenter le poids de 2.5kg sur un mouvement",
            "Logger la séance pour avoir une base",
        ],
        "pain_reported": [
            "Pas de charge sur la zone douloureuse",
            "Étirements doux ce soir",
            "Consulter si la douleur persiste 3 jours",
        ],
        "high_fatigue": [
            "Pas d'entraînement intense aujourd'hui",
            "Marche de 20 min à l'extérieur",
            "Coucher 30 min plus tôt que d'habitude",
        ],
        "positive_momentum": [
            "Maintenir le rythme actuel",
            "Ajouter une légère progression ce soir",
            "Logger pour garder la trace",
        ],
    }

    actions = lookup.get(signal_type)
    if actions:
        return actions[:3]

    # Défaut adapté à l'énergie du jour
    if energy <= 2:
        return [
            "Séance légère ou repos actif",
            "Coucher avant 22h30 ce soir",
            "Repas complet avec protéines",
        ]
    return [
        "Maintenir le rythme d'entraînement",
        "Boire 2L d'eau dans la journée",
        "Coucher à heure régulière",
    ]


def _generate_maintenance_recommendation(ctx: UserContext) -> Recommendation:
    """Recommandation par défaut quand aucun signal n'est détecté."""
    checkin = ctx.checkin_morning or {}
    energy = int(checkin.get("energy", 3) or 3)
    sleep = ctx.sleep or {}
    duration_min = sleep.get("duration_minutes", 0) or 0

    if energy >= 4:
        content = "Tout semble bien aligné. C'est un bon moment pour pousser un peu plus fort."
        actions = [
            "Augmenter légèrement l'intensité de la séance",
            "Viser 8h de sommeil cette nuit",
            "Protéines à chaque repas",
        ]
    elif duration_min > 0 and duration_min < 390:
        content = "Continue sur ta lancée. Le sommeil mérite un peu plus d'attention."
        actions = [
            "Coucher 30 min plus tôt ce soir",
            "Maintenir le rythme d'entraînement",
            "Hydratation : 2L d'eau dans la journée",
        ]
    else:
        content = "Continue sur ta lancée. La régularité est ton meilleur atout sur le long terme."
        actions = [
            "Maintenir le rythme d'entraînement actuel",
            "Boire 2L d'eau dans la journée",
            "Coucher à heure régulière ce soir",
        ]

    return Recommendation(
        content=content,
        content_short=content[:100],
        action_type="do",
        agent_source="synthesis",
        reasoning={"type": "maintenance", "no_signals": True},
        confidence=0.6,
        actions=actions,
    )


def _signal_to_action(signal_type: str) -> str:
    mapping = {
        "overtraining_risk":  "rest",
        "stagnation":         "adjust",
        "underload":          "do",
        "sleep_debt":         "rest",
        "late_training":      "adjust",
        "poor_quality":       "adjust",
        "binge_risk":         "do",
        "low_protein":        "do",
        "alcohol_pattern":    "avoid",
        "dehydration_risk":   "do",
        "dropout_risk":       "adjust",
        "mental_overload":    "rest",
        "positive_momentum":  "do",
        "pain_reported":      "avoid",
        "high_fatigue":       "rest",
    }
    return mapping.get(signal_type, "do")
