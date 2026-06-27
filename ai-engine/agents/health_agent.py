"""
Agent Santé — Analyse les douleurs, la fatigue, les blessures et le stress
physiologique global.
"""
from typing import Optional
from models import AgentSignal, UserContext


def analyze(ctx: UserContext) -> Optional[AgentSignal]:
    checkin = ctx.checkin_morning or {}
    signals: list[AgentSignal] = []

    pain = _detect_pain(checkin)
    if pain:
        signals.append(pain)

    fatigue = _detect_fatigue(checkin, ctx.sleep)
    if fatigue:
        signals.append(fatigue)

    if not signals:
        return None

    return max(signals, key=lambda s: s.urgency * s.confidence)


def _detect_pain(checkin: dict) -> Optional[AgentSignal]:
    pain_areas = checkin.get("pain_areas") or []
    pain_intensity = checkin.get("pain_intensity") or 0

    if not pain_areas or int(pain_intensity) < 4:
        return None

    return AgentSignal(
        agent="health",
        signal_type="pain_reported",
        description=f"Douleur signalée ({pain_intensity}/10) : {', '.join(pain_areas)}. "
                    "Évite de solliciter ces zones aujourd'hui.",
        confidence=0.95,
        urgency=0.8 if int(pain_intensity) >= 7 else 0.6,
        impact=0.85,
        data={"pain_areas": pain_areas, "pain_intensity": pain_intensity},
    )


def _detect_fatigue(checkin: dict, sleep: Optional[dict]) -> Optional[AgentSignal]:
    energy = checkin.get("energy")
    sleep_quality = (sleep or {}).get("quality_score")
    hrv = (sleep or {}).get("hrv_ms")

    if energy is None:
        return None

    fatigue_score = 0.0

    if int(energy) <= 2:
        fatigue_score += 0.4

    if sleep_quality and float(sleep_quality) < 3:
        fatigue_score += 0.3

    if hrv is not None and float(hrv) < 40:
        fatigue_score += 0.3

    if fatigue_score < 0.4:
        return None

    return AgentSignal(
        agent="health",
        signal_type="high_fatigue",
        description=f"Fatigue physiologique élevée (énergie : {energy}/5"
                    + (f", HRV : {hrv:.0f}ms" if hrv else "")
                    + "). Le corps demande du repos.",
        confidence=min(0.9, 0.5 + fatigue_score),
        urgency=0.65,
        impact=0.7,
        data={"energy": energy, "sleep_quality": sleep_quality, "hrv_ms": hrv},
    )
