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


class TrainingPlannerInput(BaseModel):
    user_id:         str
    sport_profile:   SportProfileInput
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
    day_of_week:   int
    activity_name: str
    session_type:  SessionType
    duration_min:  int
    notes:         Optional[str] = None
    sort_order:    int = 0


class TrainingWeekPlan(BaseModel):
    sessions:    list[PlannedSession]
    rationale:   str
    used_claude: bool = False
