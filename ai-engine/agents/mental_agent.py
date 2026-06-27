"""
Agent Mental — Analyse la motivation, les habitudes, la régularité
et détecte le risque de décrochage.
"""
from typing import Optional
from models import AgentSignal, UserContext


def analyze(ctx: UserContext) -> Optional[AgentSignal]:
    checkin = ctx.checkin_morning
    patterns = ctx.patterns or []

    signals: list[AgentSignal] = []

    dropout = _detect_dropout_risk(ctx)
    if dropout:
        signals.append(dropout)

    mental_load = _detect_mental_overload(checkin)
    if mental_load:
        signals.append(mental_load)

    momentum = _detect_positive_momentum(ctx)
    if momentum:
        signals.append(momentum)

    if not signals:
        return None

    return max(signals, key=lambda s: s.urgency * s.confidence)


def _detect_dropout_risk(ctx: UserContext) -> Optional[AgentSignal]:
    """
    Risque de décrochage si motivation < 2/5 sur 3 jours consécutifs.
    """
    # Dans le vrai système, on requête les checkins des 3 derniers jours
    checkin = ctx.checkin_morning or {}
    motivation = checkin.get("motivation")

    if motivation is None or int(motivation) > 2:
        return None

    return AgentSignal(
        agent="mental",
        signal_type="dropout_risk",
        description=f"Motivation très basse ({motivation}/5). "
                    "Réduire l'intensité aujourd'hui peut t'aider à rester dans la durée.",
        confidence=0.8,
        urgency=0.75,
        impact=0.8,
        data={"motivation": motivation},
    )


def _detect_mental_overload(checkin: Optional[dict]) -> Optional[AgentSignal]:
    """Stress ≥ 4 ET énergie ≤ 2 → surcharge mentale."""
    if not checkin:
        return None

    stress = checkin.get("stress")
    energy = checkin.get("energy")

    if stress is None or energy is None:
        return None

    if int(stress) < 4 or int(energy) > 2:
        return None

    return AgentSignal(
        agent="mental",
        signal_type="mental_overload",
        description=f"Stress élevé ({stress}/5) et énergie basse ({energy}/5). "
                    "Charge mentale importante : priorise la récupération.",
        confidence=0.85,
        urgency=0.7,
        impact=0.75,
        data={"stress": stress, "energy": energy},
    )


def _detect_positive_momentum(ctx: UserContext) -> Optional[AgentSignal]:
    """
    Signal de célébration si énergie ≥ 4 ET motivation ≥ 4
    ET au moins une séance cette semaine.
    """
    checkin = ctx.checkin_morning or {}
    sessions = ctx.activity_week or []

    energy = checkin.get("energy")
    motivation = checkin.get("motivation")

    if not energy or not motivation:
        return None
    if int(energy) < 4 or int(motivation) < 4:
        return None
    if not sessions:
        return None

    return AgentSignal(
        agent="mental",
        signal_type="positive_momentum",
        description="Bonne énergie et motivation aujourd'hui. "
                    "Moment idéal pour une séance exigeante.",
        confidence=0.8,
        urgency=0.2,
        impact=0.5,
        data={"energy": energy, "motivation": motivation},
    )
