"""
Modèles Pydantic pour le domaine Énergie.

Ces modèles représentent les données brutes — sans aucun score,
sans aucune analyse, sans aucune interprétation.
Ils correspondent exactement aux tables DB et aux routes du data-service.
"""
from __future__ import annotations

from datetime import date as DateType, datetime
from typing import Optional, Literal
from pydantic import BaseModel, Field, model_validator


# ── Sommeil ───────────────────────────────────────────────────────────────────

SleepSource = Literal[
    "manual", "apple_health", "google_fit", "oura", "whoop", "garmin", "polar"
]


class SleepEntry(BaseModel):
    """Une nuit de sommeil — données brutes."""
    date:             DateType
    bedtime:          Optional[datetime]  = None
    wake_time:        Optional[datetime]  = None
    duration_minutes: Optional[int]       = Field(None, ge=0, le=1440)
    quality_score:    int                 = Field(..., ge=1, le=5)
    awakenings:       int                 = Field(0, ge=0, le=50)
    energy_on_wake:   Optional[int]       = Field(None, ge=1, le=5)
    nap_duration_min: int                 = Field(0, ge=0, le=180)
    notes:            Optional[str]       = Field(None, max_length=1000)
    source:           SleepSource         = "manual"

    @model_validator(mode="after")
    def compute_duration_if_missing(self) -> "SleepEntry":
        """Calcule la durée depuis bedtime/wake_time si non fournie."""
        if self.duration_minutes is None and self.bedtime and self.wake_time:
            delta = self.wake_time - self.bedtime
            self.duration_minutes = max(0, int(delta.total_seconds() / 60))
        return self


class SleepWeekSummary(BaseModel):
    """Résumé hebdomadaire du sommeil — valeurs brutes, jamais de score."""
    entries:          list[SleepEntry]
    avg_duration_min: Optional[float]     = None
    avg_quality:      Optional[float]     = None
    nights_logged:    int                 = 0


# ── Activité physique ─────────────────────────────────────────────────────────

class ExerciseSet(BaseModel):
    """Une série d'un exercice lors d'une séance."""
    exercise_name: str          = Field(..., min_length=1, max_length=100)
    muscle_groups: list[str]    = Field(default_factory=list)
    set_number:    int          = Field(..., ge=1)
    reps:          Optional[int]        = Field(None, ge=0)
    weight_kg:     Optional[float]      = Field(None, ge=0)
    duration_sec:  Optional[int]        = Field(None, ge=0)
    rest_sec:      Optional[int]        = Field(None, ge=0)
    rpe:           Optional[int]        = Field(None, ge=1, le=10)
    notes:         Optional[str]        = None


class ActivitySession(BaseModel):
    """Une séance d'activité physique — données brutes."""
    id:               Optional[str]     = None
    date:             DateType
    started_at:       Optional[datetime] = None
    ended_at:         Optional[datetime] = None
    activity_name:    str               = Field(..., min_length=1, max_length=100)
    duration_minutes: Optional[int]     = Field(None, ge=0, le=600)
    calories_burned:  Optional[int]     = Field(None, ge=0)
    hr_avg_bpm:       Optional[int]     = Field(None, ge=30, le=250)
    hr_max_bpm:       Optional[int]     = Field(None, ge=30, le=250)
    rpe:              Optional[int]     = Field(None, ge=1, le=10)
    distance_meters:  Optional[int]     = Field(None, ge=0)
    steps:            Optional[int]     = Field(None, ge=0)
    notes:            Optional[str]     = None
    source:           str               = "manual"
    sets:             list[ExerciseSet] = Field(default_factory=list)


class ActivityWeekSummary(BaseModel):
    """Résumé hebdomadaire d'activité — valeurs brutes."""
    sessions:            list[ActivitySession]
    total_sessions:      int   = 0
    total_duration_min:  int   = 0
    total_calories:      int   = 0


# ── Nutrition ─────────────────────────────────────────────────────────────────

class NutritionDaily(BaseModel):
    """Totaux nutritionnels journaliers — données brutes."""
    date:        DateType
    calories:    Optional[int]   = Field(None, ge=0)
    protein_g:   Optional[float] = Field(None, ge=0)
    carbs_g:     Optional[float] = Field(None, ge=0)
    fat_g:       Optional[float] = Field(None, ge=0)
    fiber_g:     Optional[float] = Field(None, ge=0)
    water_ml:    Optional[int]   = Field(None, ge=0)
    alcohol_g:   Optional[float] = Field(None, ge=0)
    caffeine_mg: Optional[int]   = Field(None, ge=0)
    sodium_mg:   Optional[int]   = Field(None, ge=0)
    supplements: list[str]       = Field(default_factory=list)
    notes:       Optional[str]   = None
    source:      str             = "manual"


class Meal(BaseModel):
    """Un repas individuel dans la journée."""
    id:           Optional[str]     = None
    date:         DateType
    eaten_at:     Optional[datetime] = None
    meal_type:    Optional[Literal["breakfast", "lunch", "dinner", "snack"]] = None
    description:  str
    calories:     Optional[int]     = Field(None, ge=0)
    protein_g:    Optional[float]   = Field(None, ge=0)
    carbs_g:      Optional[float]   = Field(None, ge=0)
    fat_g:        Optional[float]   = Field(None, ge=0)
    is_restaurant: bool             = False
    notes:        Optional[str]     = None


class FoodItem(BaseModel):
    """Un aliment du catalogue."""
    id:                Optional[str]   = None
    name:              str             = Field(..., min_length=1, max_length=200)
    brand:             Optional[str]   = None
    calories_per_100g: Optional[int]   = Field(None, ge=0)
    protein_per_100g:  Optional[float] = Field(None, ge=0)
    carbs_per_100g:    Optional[float] = Field(None, ge=0)
    fat_per_100g:      Optional[float] = Field(None, ge=0)
    fiber_per_100g:    Optional[float] = Field(None, ge=0)
    micronutrients:    dict            = Field(default_factory=dict)
    source:            Literal["user", "system", "openfoodfacts"] = "user"
    barcode:           Optional[str]   = None


class RecipeIngredient(BaseModel):
    """Un ingrédient d'une recette."""
    id:           Optional[str]   = None
    name:         str
    quantity_g:   float           = Field(..., gt=0)
    food_item_id: Optional[str]   = None
    sort_order:   int             = 0


class Recipe(BaseModel):
    """Recette de l'utilisateur — les totaux sont calculés depuis les ingrédients."""
    id:           Optional[str]           = None
    name:         str                     = Field(..., min_length=1, max_length=200)
    description:  Optional[str]           = None
    servings:     int                     = Field(1, ge=1)
    calories:     Optional[int]           = None
    protein_g:    Optional[float]         = None
    carbs_g:      Optional[float]         = None
    fat_g:        Optional[float]         = None
    fiber_g:      Optional[float]         = None
    prep_minutes: Optional[int]           = None
    cook_minutes: Optional[int]           = None
    notes:        Optional[str]           = None
    ingredients:  list[RecipeIngredient]  = Field(default_factory=list)


# ── Vue agrégée pour l'IA ─────────────────────────────────────────────────────

class EnergyContext(BaseModel):
    """
    Vue agrégée du domaine Énergie pour le contexte IA.
    Données brutes uniquement — l'interprétation est faite par les agents.
    """
    sleep_last_night: Optional[SleepEntry]         = None
    sleep_week:       list[SleepEntry]              = Field(default_factory=list)
    activity_week:    list[ActivitySession]         = Field(default_factory=list)
    nutrition_today:  Optional[NutritionDaily]      = None
    nutrition_week:   list[NutritionDaily]          = Field(default_factory=list)
    meals_today:      list[Meal]                    = Field(default_factory=list)
