"""
Agent Sommeil — Analyse la récupération, détecte les dérives circadiennes
et calcule la dette de sommeil cumulée.
"""
from typing import Optional
from models import AgentSignal, UserContext


def analyze(ctx: UserContext) -> Optional[AgentSignal]:
    sleep = ctx.sleep
    if not sleep:
        return None

    signals: list[AgentSignal] = []

    debt = _detect_sleep_debt(sleep, ctx.profile)
    if debt:
        signals.append(debt)

    circadian = _detect_circadian_drift(ctx.activity_week)
    if circadian:
        signals.append(circadian)

    quality = _detect_poor_quality(sleep)
    if quality:
        signals.append(quality)

    if not signals:
        return None

    return max(signals, key=lambda s: s.urgency * s.confidence)


def _detect_sleep_debt(sleep: dict, profile: Optional[dict]) -> Optional[AgentSignal]:
    """
    Dette de sommeil = max(0, besoin_individuel - durée_réelle).
    Besoin individuel : baseline calculée sur les 30 premiers jours,
    fallback à 7h30.
    """
    duration_min = sleep.get("duration_minutes")
    if not duration_min:
        return None

    baseline_min = (profile or {}).get("baseline_sleep_hours", 7.5) * 60
    debt_min = baseline_min - float(duration_min)

    if debt_min < 30:
        return None

    debt_h = debt_min / 60
    urgency = min(0.95, debt_h / 3)

    return AgentSignal(
        agent="sleep",
        signal_type="sleep_debt",
        description=f"Tu as dormi {duration_min/60:.1f}h cette nuit (besoin : {baseline_min/60:.1f}h). "
                    f"Dette de {debt_h:.1f}h accumulée.",
        confidence=0.9,
        urgency=urgency,
        impact=0.8,
        data={"duration_min": duration_min, "baseline_min": baseline_min, "debt_min": debt_min},
    )


def _detect_circadian_drift(sessions: Optional[list[dict]]) -> Optional[AgentSignal]:
    """
    Détecte si des séances d'entraînement ont eu lieu après 20h,
    ce qui corrèle avec une latence d'endormissement accrue.
    """
    if not sessions:
        return None

    late_sessions = [
        s for s in sessions
        if s.get("started_at") and _hour_of(s["started_at"]) >= 20
    ]

    if len(late_sessions) < 2:
        return None

    return AgentSignal(
        agent="sleep",
        signal_type="late_training",
        description=f"{len(late_sessions)} séance(s) effectuée(s) après 20h cette semaine. "
                    "Cela peut retarder l'endormissement de 30 à 60 minutes.",
        confidence=0.75,
        urgency=0.5,
        impact=0.65,
        data={"late_sessions": len(late_sessions)},
    )


def _detect_poor_quality(sleep: dict) -> Optional[AgentSignal]:
    quality = sleep.get("quality_score")
    awakenings = sleep.get("awakenings", 0)

    if not quality or float(quality) >= 3:
        return None

    return AgentSignal(
        agent="sleep",
        signal_type="poor_quality",
        description=f"Qualité de sommeil basse ({quality}/5) avec {awakenings} réveil(s). "
                    "Ton corps n'a pas bien récupéré.",
        confidence=0.85,
        urgency=0.6,
        impact=0.7,
        data={"quality_score": quality, "awakenings": awakenings},
    )


def _hour_of(dt_str: str) -> int:
    from datetime import datetime
    try:
        return datetime.fromisoformat(dt_str.replace("Z", "+00:00")).hour
    except Exception:
        return 0
