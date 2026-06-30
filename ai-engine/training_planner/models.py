"""Pydantic models — input/output du TrainingPlannerAgent."""
from __future__ import annotations
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class FitnessLevel(str, Enum):
    beginner     = "beginner"
    intermediate = "intermediate"
    advanced     = "advanced"
    elite        = "elite"


class SessionType(str, Enum):
    strength = "strength"   # musculation
    cardio   = "cardio"     # course, vélo, natation
    combat   = "combat"     # krav maga
    mobility = "mobility"   # mobilité, yoga
    walk     = "walk"       # marche
    recovery = "recovery"   # récupération active


# ── Input ──────────────────────────────────────────────────────────────────────

class SportProfileInput(BaseModel):
    fitness_level:        FitnessLevel = FitnessLevel.beginner
    preferred_activities: list[str]    = Field(default_factory=list)
    sessions_per_week:    int          = Field(default=3, ge=1, le=14)
    session_duration_min: int          = Field(default=45, ge=10, le=300)
    available_days:       list[int]    = Field(default_factory=lambda: [1, 3, 5])
    context:              Optional[str] = None
    # Sprint 12.2 — préférences de découverte
    motivation:            Optional[str] = None   # bouger_un_peu | reprendre_confiance | ...
    attractive_activities: list[str]     = Field(default_factory=list)
    rejected_activities:   list[str]     = Field(default_factory=list)
    preferred_context:     list[str]     = Field(default_factory=list)  # seul | groupe | dehors | maison | salle
    apprehension_level:    str           = "aucune"  # aucune | legere | moderee | elevee
    realistic_time_min:    Optional[int] = None


# ── Discover ───────────────────────────────────────────────────────────────────

class SportDiscoverInput(BaseModel):
    """Input de la découverte de préférences sportives."""
    user_id:               str
    fitness_level:         str          = "beginner"
    motivation:            Optional[str] = None
    attractive_activities: list[str]    = Field(default_factory=list)
    rejected_activities:   list[str]    = Field(default_factory=list)
    preferred_context:     list[str]    = Field(default_factory=list)
    apprehension_level:    str          = "aucune"
    realistic_time_min:    Optional[int] = None
    context:               Optional[str] = None


class ActivityOption(BaseModel):
    """Une option d'activité proposée par VITA lors de la découverte."""
    name:                str
    why:                 str   # pourquoi ça pourrait convenir — bienveillant, jamais de jugement
    constraint_level:    str   # tres_faible | faible | modere | eleve
    first_step:          str   # première étape très simple et concrète
    suggested_frequency: str   # ex: "2 fois par semaine, 20 min"
    session_type:        str   # strength | cardio | mobility | walk | combat


class SportDiscoverResult(BaseModel):
    """Résultat de la découverte — 3 à 5 options + question finale."""
    options:            list[ActivityOption]
    discovery_question: str = "Laquelle te semble la plus réaliste pour commencer ?"
    used_claude:        bool = False


class SportIdentityInput(BaseModel):
    """Profil riche issu de la découverte conversationnelle (Sprint 12.3)."""
    rapport_au_sport:        Optional[str] = None
    motivations:             list[str]     = Field(default_factory=list)
    freins:                  list[str]     = Field(default_factory=list)
    experiences_positives:   list[str]     = Field(default_factory=list)
    experiences_negatives:   list[str]     = Field(default_factory=list)
    personnalite:            Optional[str] = None
    contexte_prefere:        list[str]     = Field(default_factory=list)
    contraintes:             list[str]     = Field(default_factory=list)
    activites_recommandees:  list[str]     = Field(default_factory=list)
    activites_refusees:      list[str]     = Field(default_factory=list)
    resume_valide:           Optional[str] = None


class TrainingPlannerInput(BaseModel):
    user_id:         str
    sport_profile:   SportProfileInput
    # Sprint 12.4 — identité sportive issue de la découverte conversationnelle
    sport_identity:  Optional[SportIdentityInput] = None
    # Hooks contextuels — préparés, utilisés à partir de Sprint 13
    has_sleep_issue: bool      = False
    is_high_energy:  bool      = False
    # Contraintes
    equipment:       list[str] = Field(default_factory=list)
    pain_areas:      list[str] = Field(default_factory=list)
    prefer_outdoors: bool      = False
    # Contextes adaptatifs futurs — champs optionnels, ignorés jusqu'au moteur adaptatif (Sprint 13+)
    journal_context:            Optional[dict] = None
    sleep_context:              Optional[dict] = None
    nutrition_context:          Optional[dict] = None
    meal_plan_context:          Optional[dict] = None
    recovery_context:           Optional[dict] = None
    uploaded_documents_context: Optional[list] = None


# ── Output ─────────────────────────────────────────────────────────────────────

class PlannedSession(BaseModel):
    day_of_week:       int
    activity_name:     str
    session_type:      SessionType
    duration_min:      int
    notes:             Optional[str] = None
    sort_order:        int           = 0
    # Sprint 12.4 — enrichissement de la carte séance
    intensity_label:   Optional[str] = None   # douce | modérée | soutenue
    session_goal:      Optional[str] = None   # objectif de la séance (1 phrase)
    simple_instruction:Optional[str] = None   # consigne simple et concrète
    progression_note:  Optional[str] = None   # note de progression bienveillante
    why_this_session:  Optional[str] = None   # pourquoi VITA l'a choisie


class TrainingWeekPlan(BaseModel):
    sessions:         list[PlannedSession]
    rationale:        str
    used_claude:      bool = False
    used_identity:    bool = False   # True si sport_identity a influencé le plan
