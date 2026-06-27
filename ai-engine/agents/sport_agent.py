"""
Agent Sport — Analyse la progression, détecte stagnations et surcharge,
construit et ajuste les programmes d'entraînement.

Algorithme principal : ratio ATL/CTL (Acute Training Load / Chronic Training Load)
pour évaluer le Training Stress Balance (TSB = forme - fatigue).
"""
import json
from typing import Optional
from models import AgentSignal, UserContext
from config import get_settings

settings = get_settings()


def analyze(ctx: UserContext) -> Optional[AgentSignal]:
    """Point d'entrée principal de l'agent sport."""
    sessions = ctx.activity_week or []
    if not sessions:
        return None

    signals: list[AgentSignal] = []

    overtraining = _detect_overtraining(sessions, ctx.sleep)
    if overtraining:
        signals.append(overtraining)

    stagnation = _detect_stagnation(sessions)
    if stagnation:
        signals.append(stagnation)

    underload = _detect_underload(sessions)
    if underload:
        signals.append(underload)

    if not signals:
        return None

    # Retourner le signal le plus urgent
    return max(signals, key=lambda s: s.urgency * s.confidence)


def _detect_overtraining(sessions: list[dict], sleep: Optional[dict]) -> Optional[AgentSignal]:
    """
    TSB = CTL - ATL
    ATL = charge aiguë sur 7 jours (exponentielle décroissante, τ=7)
    CTL = charge chronique sur 42 jours (τ=42)
    Signal si TSB < -15 ET sleep dégradé
    """
    if len(sessions) < 3:
        return None

    atl = _compute_training_load(sessions, tau=7)
    weekly_sessions = len([s for s in sessions[-7:]])
    avg_rpe = _avg(sessions, "rpe") or 6
    sleep_quality = (sleep or {}).get("quality_score", 3)

    overtraining_score = 0.0

    if atl > 800:
        overtraining_score += 0.3
    if weekly_sessions >= 6:
        overtraining_score += 0.2
    if avg_rpe >= 8:
        overtraining_score += 0.25
    if sleep_quality and float(sleep_quality) < 3:
        overtraining_score += 0.25

    if overtraining_score < 0.5:
        return None

    return AgentSignal(
        agent="sport",
        signal_type="overtraining_risk",
        description=(
            f"Risque de surentraînement détecté. "
            f"Charge aiguë : {atl:.0f}, RPE moyen : {avg_rpe:.1f}/10, "
            f"qualité de sommeil : {sleep_quality}/5."
        ),
        confidence=min(0.95, overtraining_score),
        urgency=0.85,
        impact=0.8,
        data={"atl": atl, "avg_rpe": avg_rpe, "sleep_quality": sleep_quality},
    )


def _detect_stagnation(sessions: list[dict]) -> Optional[AgentSignal]:
    """
    Stagnation si la progression de charge est < 2% sur les 3 dernières semaines
    pour au moins un exercice principal.
    """
    # TODO: comparer charges par exercice via exercise_sets dans la DB
    # Pour l'instant, signal basé sur volume total hebdomadaire
    if len(sessions) < 7:
        return None

    recent_volume = sum(
        (s.get("duration_minutes") or 0) * (s.get("rpe") or 6)
        for s in sessions[-7:]
    )
    older_volume = sum(
        (s.get("duration_minutes") or 0) * (s.get("rpe") or 6)
        for s in sessions[-14:-7]
    )

    if older_volume == 0:
        return None

    progression = (recent_volume - older_volume) / older_volume

    if progression > -0.05:  # Pas de stagnation
        return None

    return AgentSignal(
        agent="sport",
        signal_type="stagnation",
        description=(
            f"Volume d'entraînement en baisse de {abs(progression)*100:.0f}% "
            f"cette semaine par rapport à la précédente."
        ),
        confidence=0.7,
        urgency=0.4,
        impact=0.6,
        data={"recent_volume": recent_volume, "older_volume": older_volume, "progression": progression},
    )


def _detect_underload(sessions: list[dict]) -> Optional[AgentSignal]:
    """Sous-stimulation si < 2 séances sur 7 jours."""
    week_sessions = [s for s in sessions[-7:]]
    if len(week_sessions) >= 2:
        return None

    return AgentSignal(
        agent="sport",
        signal_type="underload",
        description=f"Seulement {len(week_sessions)} séance(s) cette semaine. "
                    "Un peu de mouvement t'aidera à te sentir mieux.",
        confidence=0.9,
        urgency=0.3,
        impact=0.5,
        data={"sessions_this_week": len(week_sessions)},
    )


def _compute_training_load(sessions: list[dict], tau: int) -> float:
    """Calcul TRIMP simplifié : durée × RPE, pondéré exponentiellement."""
    import math
    load = 0.0
    k = 1 - math.exp(-1 / tau)
    for s in sessions:
        daily_load = (s.get("duration_minutes") or 0) * (s.get("rpe") or 6)
        load = load * (1 - k) + daily_load * k
    return load


def _avg(sessions: list[dict], field: str) -> Optional[float]:
    values = [s[field] for s in sessions if s.get(field) is not None]
    return sum(values) / len(values) if values else None


def build_program_prompt(ctx: UserContext) -> str:
    """Génère le prompt pour demander à Claude de créer un programme."""
    profile = ctx.profile or {}
    snapshot = ctx.snapshot or {}
    goal = profile.get("primary_goal", "perform")
    level = profile.get("activity_level", 3)
    weight = snapshot.get("weight_kg", 75)

    return f"""Tu es un préparateur physique expert.
Génère un programme d'entraînement sur 4 semaines pour cet utilisateur :

- Objectif : {goal}
- Niveau activité (1-5) : {level}
- Poids : {weight} kg
- Séances disponibles par semaine : {min(5, level + 1)}

Réponds en JSON avec la structure :
{{
  "program_name": "...",
  "weeks": [
    {{
      "week": 1,
      "sessions": [
        {{
          "day_of_week": 1,
          "name": "...",
          "focus": "...",
          "estimated_duration_min": 60,
          "exercises": [
            {{"name": "...", "sets": 3, "reps": "8-10", "rest_sec": 90}}
          ]
        }}
      ]
    }}
  ]
}}"""
