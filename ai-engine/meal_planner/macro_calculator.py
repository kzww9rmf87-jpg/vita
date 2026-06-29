"""
Calculateur de macros nutritionnelles — 100 % déterministe.

Aucune IA, aucune approximation variable. Ce module doit rester stable et testable.

Formule BMR : Harris-Benedict révisée (Mifflin-St Jeor)
Source : Mifflin MD et al., 1990 — validée pour la population générale.

Principes VITA (FOUNDING_PRINCIPLES.md §7) :
- Ces cibles guident la PLANIFICATION. Elles ne jugent pas l'utilisateur.
- Jamais affichées comme "objectif à atteindre" ou "limite à ne pas dépasser".
- VITA organise. VITA ne prescrit pas.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


# ── Constantes ────────────────────────────────────────────────────────────────

ACTIVITY_MULTIPLIERS = {
    "sedentary":  1.20,   # Peu ou pas d'exercice
    "light":      1.375,  # 1-3 jours/semaine
    "moderate":   1.55,   # 3-5 jours/semaine
    "active":     1.725,  # 6-7 jours/semaine
    "very_active": 1.90,  # Travail physique + entraînement
}

# Ajustement calorique par objectif (multiplicateur du TDEE)
OBJECTIVE_CALORIE_FACTOR = {
    "maintain":   1.00,
    "lose":       0.80,   # Déficit ~20 %
    "gain":       1.10,   # Surplus ~10 %
    "recompose":  1.00,   # Maintien calorique, protéines élevées
}

# Distribution des macros (% de l'apport calorique) par objectif
MACRO_RATIOS = {
    #              protein  carbs   fat
    "maintain":   (0.25,   0.50,  0.25),
    "lose":       (0.35,   0.40,  0.25),
    "gain":       (0.30,   0.45,  0.25),
    "recompose":  (0.35,   0.40,  0.25),
}

# Fibres recommandées (g/jour) — indépendantes des macros
FIBER_RECOMMENDATIONS = {
    "male":   38,
    "female": 25,
    "other":  30,   # Médiane
}

# Calories par gramme de macronutriment
KCAL_PER_G_PROTEIN = 4.0
KCAL_PER_G_CARBS   = 4.0
KCAL_PER_G_FAT     = 9.0


# ── Modèle de résultat ────────────────────────────────────────────────────────

@dataclass
class MacroTargets:
    calories:   int
    protein_g:  float
    carbs_g:    float
    fat_g:      float
    fiber_g:    float

    def to_dict(self) -> dict:
        return {
            "target_calories":  self.calories,
            "target_protein_g": round(self.protein_g, 1),
            "target_carbs_g":   round(self.carbs_g, 1),
            "target_fat_g":     round(self.fat_g, 1),
            "target_fiber_g":   round(self.fiber_g, 1),
        }


@dataclass
class MealMacros:
    """Macros calculées pour un créneau repas (portions × macros recette / servings)."""
    calories:  Optional[int]
    protein_g: Optional[float]
    carbs_g:   Optional[float]
    fat_g:     Optional[float]
    fiber_g:   Optional[float]

    @classmethod
    def empty(cls) -> "MealMacros":
        return cls(None, None, None, None, None)

    def to_dict(self) -> dict:
        return {
            "calories":  self.calories,
            "protein_g": round(self.protein_g, 1) if self.protein_g is not None else None,
            "carbs_g":   round(self.carbs_g, 1)   if self.carbs_g   is not None else None,
            "fat_g":     round(self.fat_g, 1)      if self.fat_g     is not None else None,
            "fiber_g":   round(self.fiber_g, 1)    if self.fiber_g   is not None else None,
        }


@dataclass
class DayMacros:
    """Macros sommées pour une journée complète."""
    day_of_week: int   # 0 = lundi … 6 = dimanche
    calories:    Optional[int]
    protein_g:   Optional[float]
    carbs_g:     Optional[float]
    fat_g:       Optional[float]
    fiber_g:     Optional[float]

    def to_dict(self) -> dict:
        return {
            "day_of_week": self.day_of_week,
            "calories":    self.calories,
            "protein_g":   round(self.protein_g, 1) if self.protein_g is not None else None,
            "carbs_g":     round(self.carbs_g, 1)   if self.carbs_g   is not None else None,
            "fat_g":       round(self.fat_g, 1)      if self.fat_g     is not None else None,
            "fiber_g":     round(self.fiber_g, 1)    if self.fiber_g   is not None else None,
        }


# ── Fonctions publiques ───────────────────────────────────────────────────────

def calculate_bmr(
    weight_kg: float,
    height_cm: int,
    age: int,
    sex: str,  # "male" | "female" | "other"
) -> float:
    """
    Métabolisme de base (BMR) via Mifflin-St Jeor.
    Retourne les kcal/jour au repos.
    """
    bmr_male   = 10 * weight_kg + 6.25 * height_cm - 5 * age + 5
    bmr_female = 10 * weight_kg + 6.25 * height_cm - 5 * age - 161
    if sex == "male":
        return bmr_male
    if sex == "female":
        return bmr_female
    return (bmr_male + bmr_female) / 2  # "other" → médiane


def calculate_tdee(bmr: float, activity_level: str) -> float:
    """Dépense énergétique totale (TDEE) = BMR × activité."""
    multiplier = ACTIVITY_MULTIPLIERS.get(activity_level, 1.55)
    return bmr * multiplier


def calculate_targets(
    weight_kg: Optional[float],
    height_cm: Optional[int],
    age: Optional[int],
    sex: Optional[str],
    activity_level: str,
    objective: str,
) -> Optional[MacroTargets]:
    """
    Calcule les cibles nutritionnelles journalières.
    Retourne None si les données anthropométriques sont manquantes.
    """
    if not all([weight_kg, height_cm, age, sex]):
        return None

    bmr  = calculate_bmr(weight_kg, height_cm, age, sex)  # type: ignore[arg-type]
    tdee = calculate_tdee(bmr, activity_level)
    target_kcal = round(tdee * OBJECTIVE_CALORIE_FACTOR.get(objective, 1.0))

    protein_ratio, carbs_ratio, fat_ratio = MACRO_RATIOS.get(objective, (0.25, 0.50, 0.25))

    protein_g = (target_kcal * protein_ratio) / KCAL_PER_G_PROTEIN
    carbs_g   = (target_kcal * carbs_ratio)   / KCAL_PER_G_CARBS
    fat_g     = (target_kcal * fat_ratio)      / KCAL_PER_G_FAT
    fiber_g   = float(FIBER_RECOMMENDATIONS.get(sex or "other", 30))  # type: ignore[arg-type]

    return MacroTargets(
        calories=target_kcal,
        protein_g=round(protein_g, 1),
        carbs_g=round(carbs_g, 1),
        fat_g=round(fat_g, 1),
        fiber_g=fiber_g,
    )


def calculate_meal_macros(
    calories_per_serving: Optional[int],
    protein_g_per_serving: Optional[float],
    carbs_g_per_serving: Optional[float],
    fat_g_per_serving: Optional[float],
    fiber_g_per_serving: Optional[float],
    portions: float,
    servings: int,
) -> MealMacros:
    """
    Calcule les macros pour un repas planifié en tenant compte des portions.
    Toutes les valeurs de la recette sont par portion (= par serving).
    portions / servings = ratio d'échelle.
    """
    if calories_per_serving is None:
        return MealMacros.empty()

    ratio = portions / max(servings, 1)

    def scale(v: Optional[float]) -> Optional[float]:
        return round(v * ratio, 1) if v is not None else None

    return MealMacros(
        calories=round(calories_per_serving * ratio) if calories_per_serving else None,
        protein_g=scale(protein_g_per_serving),
        carbs_g=scale(carbs_g_per_serving),
        fat_g=scale(fat_g_per_serving),
        fiber_g=scale(fiber_g_per_serving),
    )


def sum_day_macros(day_of_week: int, meal_macros_list: list[MealMacros]) -> DayMacros:
    """Additionne les macros de tous les repas d'une journée."""
    has_data = any(m.calories is not None for m in meal_macros_list)
    if not has_data:
        return DayMacros(day_of_week, None, None, None, None, None)

    calories  = sum(m.calories  or 0 for m in meal_macros_list) or None
    protein_g = sum(m.protein_g or 0 for m in meal_macros_list) or None
    carbs_g   = sum(m.carbs_g   or 0 for m in meal_macros_list) or None
    fat_g     = sum(m.fat_g     or 0 for m in meal_macros_list) or None
    fiber_g   = sum(m.fiber_g   or 0 for m in meal_macros_list) or None

    return DayMacros(
        day_of_week=day_of_week,
        calories=calories,
        protein_g=round(protein_g, 1) if protein_g else None,
        carbs_g=round(carbs_g, 1)     if carbs_g   else None,
        fat_g=round(fat_g, 1)         if fat_g     else None,
        fiber_g=round(fiber_g, 1)     if fiber_g   else None,
    )
