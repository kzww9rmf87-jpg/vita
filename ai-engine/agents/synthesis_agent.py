"""
Agent Synthèse — Fusionne toutes les analyses et produit UNE SEULE
observation prioritaire, bienveillante, contextuelle.

Philosophie (FOUNDING_PRINCIPLES.md §10) :
- Le Synthesis Agent est le moment où VITA parle directement
- Une observation. Jamais deux.
- Jamais de culpabilisation
- Maximum 2 phrases
- Ton : Témoin Bienveillant — observe, éclaire, n'impose pas
"""
import anthropic
from typing import Optional
from models import AgentSignal, Recommendation, UserContext
from config import get_settings

settings = get_settings()

# Client async — cohérent avec le reste de l'ai-engine
client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

# Prompt séparé de la logique — versionné et lisible
_SYNTHESIS_SYSTEM_PROMPT = """Tu es VITA. Tu formules l'observation du jour pour cet utilisateur.

Tu n'es pas un coach. Tu es un Témoin Bienveillant.
Tu observes les données, tu relies ce que tu vois, tu éclaires — sans prescrire ni décider.

Règles absolues :
- Une seule observation, formulée en 2 phrases maximum (50 mots maximum)
- Jamais de "tu devrais", "il faut que tu", "je te recommande de"
- Jamais de culpabilisation, honte ou comparaison
- La première phrase doit montrer que tu as vraiment regardé cette personne spécifique
- Tu peux ouvrir une réflexion — pas conclure à la place de l'utilisateur
- Si tout va bien, dis-le simplement et honnêtement
- Tu parles à la deuxième personne du singulier (tu)"""


async def synthesize(
    signals: list[AgentSignal],
    ctx: UserContext,
) -> Optional[Recommendation]:
    """
    Prend tous les signaux des agents spécialisés et produit
    une observation unique, priorisée et contextualisée.
    """
    if not signals:
        return _generate_maintenance_recommendation(ctx)

    # Trier par urgence × impact × confiance
    ranked = sorted(
        signals,
        key=lambda s: s.urgency * s.impact * s.confidence,
        reverse=True,
    )
    top_signal = ranked[0]

    # Contexte croisé : d'autres signaux peuvent nuancer l'observation
    context_signals = ranked[1:3] if len(ranked) > 1 else []

    return await _generate_recommendation_with_claude(top_signal, context_signals, ctx)


async def _generate_recommendation_with_claude(
    primary: AgentSignal,
    context: list[AgentSignal],
    ctx: UserContext,
) -> Recommendation:
    """Appelle Claude pour formuler l'observation en langage naturel."""
    profile = ctx.profile or {}
    checkin = ctx.checkin_morning or {}

    context_text = ""
    if context:
        context_text = "\n\nObservations complémentaires :\n" + "\n".join(
            f"- [{s.agent}] {s.description}" for s in context
        )

    user_message = f"""Observation principale à formuler :
Agent : {primary.agent}
Type : {primary.signal_type}
Situation observée : {primary.description}
{context_text}

Contexte de l'utilisateur :
- Objectif : {profile.get("primary_goal", "non défini")}
- Énergie ce matin : {checkin.get("energy", "?")} /5
- Humeur : {checkin.get("mood", "?")} /5

Formule l'observation du jour (2 phrases maximum) :"""

    message = await client.messages.create(
        model=settings.model_fast,
        max_tokens=settings.max_tokens_recommendation,
        system=_SYNTHESIS_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )

    content = message.content[0].text.strip()

    # Version courte pour la notification push (< 100 caractères)
    short = content.split(".")[0] + "." if "." in content else content[:100]

    return Recommendation(
        content=content,
        content_short=short[:100],
        action_type=_signal_to_action(primary.signal_type),
        agent_source=primary.agent,
        reasoning={
            "primary_signal": primary.model_dump(),
            "context_signals": [s.model_dump() for s in context],
            "model": settings.model_fast,
        },
        confidence=primary.confidence,
    )


def _generate_maintenance_recommendation(ctx: UserContext) -> Recommendation:
    """Recommandation par défaut quand tout va bien."""
    checkin = ctx.checkin_morning or {}
    energy = checkin.get("energy", 3)

    if int(energy or 3) >= 4:
        content = "Tout semble bien aligné. C'est un bon moment pour pousser un peu plus fort à l'entraînement."
    else:
        content = "Continue sur ta lancée. La régularité est ton meilleur atout sur le long terme."

    return Recommendation(
        content=content,
        content_short=content[:100],
        action_type="do",
        agent_source="synthesis",
        reasoning={"type": "maintenance", "no_signals": True},
        confidence=0.6,
    )


def _signal_to_action(signal_type: str) -> str:
    mapping = {
        "overtraining_risk": "rest",
        "stagnation": "adjust",
        "underload": "do",
        "sleep_debt": "rest",
        "late_training": "adjust",
        "poor_quality": "adjust",
        "binge_risk": "do",
        "low_protein": "do",
        "alcohol_pattern": "avoid",
        "dehydration_risk": "do",
        "dropout_risk": "adjust",
        "mental_overload": "rest",
        "positive_momentum": "do",
        "pain_reported": "avoid",
        "high_fatigue": "rest",
    }
    return mapping.get(signal_type, "do")
