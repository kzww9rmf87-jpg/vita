"""
Algorithme local de planification d'entraînement.
Déterministe, sans appel réseau. Fournit le fallback si Claude est indisponible.
"""
from __future__ import annotations
from .models import (
    FitnessLevel, SessionType,
    SportProfileInput, PlannedSession, TrainingPlannerInput,
)

# ── Détection du type de séance à partir du nom de l'activité ─────────────────

_ACTIVITY_TYPE_MAP: list[tuple[list[str], SessionType]] = [
    (["musculation", "muscu", "weight", "haltère", "gym", "force"], SessionType.strength),
    (["krav", "combat", "boxe", "judo", "mma", "arts martiaux"],    SessionType.combat),
    (["yoga", "mobilité", "mobilite", "étirement", "stretching",
      "pilates", "souplesse"],                                       SessionType.mobility),
    (["marche", "walk", "randonnée", "rando", "promenade"],         SessionType.walk),
    (["course", "run", "vélo", "velo", "cyclisme", "natation",
      "swim", "cardio", "endurance", "hiit"],                       SessionType.cardio),
]

_DEFAULT_TYPE = SessionType.cardio


def _infer_type(activity: str) -> SessionType:
    low = activity.lower()
    for keywords, stype in _ACTIVITY_TYPE_MAP:
        if any(k in low for k in keywords):
            return stype
    return _DEFAULT_TYPE


# ── Facteurs d'ajustement par niveau ──────────────────────────────────────────

_DURATION_FACTOR: dict[FitnessLevel, float] = {
    FitnessLevel.beginner:     0.80,
    FitnessLevel.intermediate: 1.00,
    FitnessLevel.advanced:     1.10,
    FitnessLevel.elite:        1.20,
}

# ── Algorithme ─────────────────────────────────────────────────────────────────

def plan_locally(inp: TrainingPlannerInput) -> list[PlannedSession]:
    """Retourne la liste de séances pour une semaine type."""
    profile  = inp.sport_profile
    days     = sorted(set(profile.available_days)) or [1, 3, 5]  # fallback si vide
    n        = min(len(days), profile.sessions_per_week)
    factor   = _DURATION_FACTOR[profile.fitness_level]
    base_dur = profile.session_duration_min

    activities = _resolve_activities(profile, n)
    sessions: list[PlannedSession] = []

    for sort_idx, (day, activity) in enumerate(zip(days[:n], activities)):
        stype    = _infer_type(activity)
        duration = _adjusted_duration(stype, base_dur, factor, inp.pain_areas)
        notes    = _build_notes(stype, profile.fitness_level, inp.pain_areas, inp.equipment)
        sessions.append(PlannedSession(
            day_of_week   = day,
            activity_name = activity,
            session_type  = stype,
            duration_min  = duration,
            notes         = notes,
            sort_order    = sort_idx,
        ))

    return sessions


def build_rationale(profile: SportProfileInput, sessions: list[PlannedSession]) -> str:
    """Génère l'explication non-culpabilisante de la structure de la semaine."""
    types  = {s.session_type for s in sessions}
    n      = len(sessions)
    days_s = ", ".join(_day_name(s.day_of_week) for s in sessions)

    parts = [f"VITA a organisé {n} séance{'s' if n > 1 else ''} ({days_s})"]

    if SessionType.strength in types and SessionType.cardio in types:
        parts.append("en alternant renforcement et cardio pour un équilibre global")
    elif SessionType.mobility in types:
        parts.append("en incluant un travail de mobilité pour soutenir la récupération")

    if profile.fitness_level in (FitnessLevel.beginner, FitnessLevel.intermediate):
        parts.append("Les durées restent accessibles — l'important est la régularité")

    return ". ".join(parts) + "."


# ── Helpers ───────────────────────────────────────────────────────────────────

def _resolve_activities(profile: SportProfileInput, n: int) -> list[str]:
    """Sélectionne les activités à placer, en cyclant si nécessaire."""
    if not profile.preferred_activities:
        return ["Activité libre"] * n

    result: list[str] = []
    pool = profile.preferred_activities
    for i in range(n):
        result.append(pool[i % len(pool)])

    # Si plusieurs séances, tous du même type strength → insérer mobilité en fin
    if n >= 3 and len({_infer_type(a) for a in result}) == 1 and _infer_type(result[0]) == SessionType.strength:
        result[-1] = "Mobilité"

    return result


def _adjusted_duration(
    stype: SessionType,
    base: int,
    factor: float,
    pain_areas: list[str],
) -> int:
    raw = int(base * factor)
    # Mobilité et marche plafonnent à 60 min même pour les niveaux avancés
    if stype in (SessionType.mobility, SessionType.walk):
        raw = min(raw, 60)
    # Réduction si douleur signalée
    if pain_areas:
        raw = int(raw * 0.85)
    return max(10, min(raw, 300))


def _build_notes(
    stype: SessionType,
    level: FitnessLevel,
    pain_areas: list[str],
    equipment: list[str],
) -> str | None:
    notes: list[str] = []

    if pain_areas:
        zones = ", ".join(pain_areas)
        notes.append(f"Adapte les exercices sollicitant : {zones}")

    if stype == SessionType.strength and not equipment:
        notes.append("Poids du corps ou matériel disponible")

    if level == FitnessLevel.beginner and stype == SessionType.cardio:
        notes.append("Commence à un rythme confortable — augmente progressivement")

    return " · ".join(notes) if notes else None


_DAY_NAMES = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]

def _day_name(day: int) -> str:
    return _DAY_NAMES[day % 7]
