"""
MealPlannerAgent — Premier agent spécialisé de VITA.

Rôle : construire un planning hebdomadaire personnalisé à partir des recettes
choisies par l'utilisateur, de son profil nutritionnel et de son garde-manger.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RÉPARTITION ALGORITHME LOCAL vs CLAUDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ALGORITHME LOCAL (toujours, déterministe) :
  ✓ Remplir 14 créneaux (7j × lunch + dinner)
  ✓ Variété maximale (pas de recette identique consécutive)
  ✓ Recettes rapides en priorité pour les déjeuners (≤ 30 min)
  ✓ Batch cooking : recettes longues le dimanche
  ✓ Éviter deux repas identiques le même jour
  ✓ Calcul des macros par créneau, par jour, pour la semaine (déterministe)
  ✓ Consolidation des ingrédients (addition des quantités, dédoublonnage)
  ✓ Filtrage par le garde-manger (retrait des ingrédients disponibles)
  ✓ Catégorisation des ingrédients (rayon)
  ✓ Fallback complet si Claude indisponible

CLAUDE (seulement quand profil disponible + arbitrage utile) :
  ✓ Réorganiser les créneaux pour équilibrer les protéines sur la semaine
  ✓ Prioriser les recettes les plus adaptées à l'objectif (gain, perte, maintien)
  ✓ Adapter l'ordre des repas selon les contraintes (batch cooking, temps disponible)
  ✗ Ne calcule JAMAIS les macros (algorithmique uniquement)
  ✗ Ne génère JAMAIS de nouvelles recettes
  ✗ Ne juge JAMAIS l'alimentation de l'utilisateur

VITA ne prescrit pas. VITA organise.
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import anthropic

from config import get_settings
from .macro_calculator import (
    MacroTargets,
    MealMacros,
    DayMacros,
    calculate_meal_macros,
    sum_day_macros,
)
from .models import MealDistribution, RecipeForPlan
from .planner import MealPlanner

logger = logging.getLogger(__name__)

# Lazy init — settings et client chargés au premier appel (pas à l'import)
_settings = None
_anthropic_client = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _settings, _anthropic_client
    if _anthropic_client is None:
        _settings = get_settings()
        _anthropic_client = anthropic.AsyncAnthropic(api_key=_settings.anthropic_api_key)
    return _anthropic_client


def _get_settings():
    global _settings
    if _settings is None:
        _settings = get_settings()
    return _settings


# ── Modèles d'entrée / sortie ─────────────────────────────────────────────────

from dataclasses import dataclass, field
from pydantic import BaseModel


class NutritionProfile(BaseModel):
    """Profil nutritionnel de l'utilisateur. Tous les champs sont optionnels."""
    objective:           str = "maintain"
    weight_kg:           Optional[float] = None
    height_cm:           Optional[int]   = None
    age:                 Optional[int]   = None
    sex:                 Optional[str]   = None
    activity_level:      str = "moderate"
    meals_per_day:       int = 3
    batch_cooking:       bool = False
    cook_time_available: Optional[str] = None
    budget:              Optional[str] = None
    allergies:           list[str] = field(default_factory=list)
    intolerances:        list[str] = field(default_factory=list)
    excluded_foods:      list[str] = field(default_factory=list)
    target_calories:     Optional[int]   = None
    target_protein_g:    Optional[float] = None
    target_carbs_g:      Optional[float] = None
    target_fat_g:        Optional[float] = None
    target_fiber_g:      Optional[float] = None

    class Config:
        extra = "ignore"


class RecipeWithMacros(BaseModel):
    """Recette avec ses macros par portion."""
    id:           str
    name:         str
    servings:     int = 1
    prep_minutes: Optional[int] = None
    cook_minutes: Optional[int] = None
    calories:     Optional[int]   = None
    protein_g:    Optional[float] = None
    carbs_g:      Optional[float] = None
    fat_g:        Optional[float] = None
    fiber_g:      Optional[float] = None

    @property
    def total_minutes(self) -> int:
        return (self.prep_minutes or 0) + (self.cook_minutes or 0)


class SmartMealPlanInput(BaseModel):
    """Entrée complète de l'agent."""
    user_id:    str
    recipes:    list[RecipeWithMacros]
    profile:    Optional[NutritionProfile] = None
    pantry:     list[str] = []  # noms d'ingrédients en minuscules


@dataclass
class PlannedSlot:
    """Un créneau planifié avec ses macros."""
    recipe_id:   str
    recipe_name: str
    day_of_week: int
    meal_slot:   str  # "lunch" | "dinner"
    portions:    float
    macros:      MealMacros = field(default_factory=MealMacros.empty)


@dataclass
class SmartMealPlanResult:
    """Résultat complet de la planification."""
    slots:       list[PlannedSlot]
    day_macros:  list[DayMacros]
    week_macros: DayMacros
    used_claude: bool = False


# ── Agent principal ───────────────────────────────────────────────────────────

class MealPlannerAgent:
    """
    Agent de planification hebdomadaire.
    Combine logique locale déterministe et appel optionnel à Claude.
    """

    async def plan(self, input: SmartMealPlanInput) -> SmartMealPlanResult:
        """
        Point d'entrée principal.
        1. Distribution locale des créneaux
        2. Calcul des macros (déterministe)
        3. Raffinement via Claude si profil disponible + macros utiles
        4. Retour du plan complet
        """
        recipes = input.recipes
        profile = input.profile

        if not recipes:
            return _empty_result()

        # ── Étape 1 : distribution locale ─────────────────────────────────────
        raw_slots = _local_distribute(recipes, profile)

        # ── Étape 2 : calcul des macros par créneau (toujours déterministe) ──
        recipe_map = {r.id: r for r in recipes}
        slots_with_macros = _attach_macros(raw_slots, recipe_map)

        # ── Étape 3 : raffinement Claude (optionnel) ──────────────────────────
        used_claude = False
        if profile and _should_call_claude(recipes, profile):
            refined = await _refine_with_claude(slots_with_macros, recipes, profile)
            if refined is not None:
                slots_with_macros = _attach_macros(refined, recipe_map)
                used_claude = True

        # ── Étape 4 : calcul des macros par jour et pour la semaine ───────────
        day_macros  = _compute_day_macros(slots_with_macros)
        week_macros = _compute_week_macros(day_macros)

        return SmartMealPlanResult(
            slots=slots_with_macros,
            day_macros=day_macros,
            week_macros=week_macros,
            used_claude=used_claude,
        )


# ── Algorithme local ─────────────────────────────────────────────────────────

SLOTS_ORDER: list[tuple[int, str]] = [
    (day, slot)
    for day in range(7)
    for slot in ("lunch", "dinner")
]


def _local_distribute(
    recipes: list[RecipeWithMacros],
    profile: Optional[NutritionProfile],
) -> list[PlannedSlot]:
    """
    Distribue les recettes sur 14 créneaux selon des règles locales.
    Aucun appel réseau. Résultat déterministe.
    """
    batch_cooking = profile.batch_cooking if profile else False
    cook_time = profile.cook_time_available if profile else "moderate"

    quick = [r for r in recipes if r.total_minutes <= 30]
    slow  = [r for r in recipes if r.total_minutes > 30]
    if not quick:
        quick = list(recipes)  # tout devient "rapide" si rien de rapide

    result: list[PlannedSlot] = []
    used: set[str] = set()
    cycle_idx = 0
    last_id: Optional[str] = None

    for day, slot in SLOTS_ORDER:
        is_weekend = day >= 5  # sam = 5, dim = 6
        is_sunday_dinner = (day == 6 and slot == "dinner")

        # Batch cooking : réserver le dimanche soir pour les préparations longues
        if batch_cooking and is_sunday_dinner and slow:
            recipe = _pick(slow, used, last_id) or _pick(recipes, set(), last_id) or recipes[cycle_idx % len(recipes)]
        elif slot == "lunch" and not is_weekend:
            # Jours de semaine → déjeuner rapide
            recipe = _pick(quick, used, last_id) or _pick(recipes, set(), last_id) or recipes[cycle_idx % len(recipes)]
        elif is_weekend and cook_time == "generous":
            # Week-end avec temps disponible → recettes élaborées en priorité
            recipe = _pick(slow or recipes, used, last_id) or _pick(recipes, set(), last_id) or recipes[cycle_idx % len(recipes)]
        else:
            recipe = _pick(recipes, used, last_id) or recipes[cycle_idx % len(recipes)]

        used.add(recipe.id)
        if len(used) >= len(recipes):
            used.clear()

        last_id = recipe.id
        cycle_idx += 1

        result.append(PlannedSlot(
            recipe_id=recipe.id,
            recipe_name=recipe.name,
            day_of_week=day,
            meal_slot=slot,
            portions=float(recipe.servings),  # portions = servings par défaut
        ))

    return result


def _pick(
    candidates: list[RecipeWithMacros],
    used: set[str],
    last_id: Optional[str],
) -> Optional[RecipeWithMacros]:
    for r in candidates:
        if r.id not in used and r.id != last_id:
            return r
    return None


# ── Calcul des macros ────────────────────────────────────────────────────────

def _attach_macros(
    slots: list[PlannedSlot],
    recipe_map: dict[str, RecipeWithMacros],
) -> list[PlannedSlot]:
    """Calcule et attache les macros à chaque créneau."""
    result = []
    for slot in slots:
        recipe = recipe_map.get(slot.recipe_id)
        if recipe and recipe.calories is not None:
            macros = calculate_meal_macros(
                calories_per_serving=recipe.calories,
                protein_g_per_serving=recipe.protein_g,
                carbs_g_per_serving=recipe.carbs_g,
                fat_g_per_serving=recipe.fat_g,
                fiber_g_per_serving=recipe.fiber_g,
                portions=slot.portions,
                servings=recipe.servings,
            )
        else:
            macros = MealMacros.empty()
        result.append(PlannedSlot(
            recipe_id=slot.recipe_id,
            recipe_name=slot.recipe_name,
            day_of_week=slot.day_of_week,
            meal_slot=slot.meal_slot,
            portions=slot.portions,
            macros=macros,
        ))
    return result


def _compute_day_macros(slots: list[PlannedSlot]) -> list[DayMacros]:
    days: dict[int, list[MealMacros]] = {d: [] for d in range(7)}
    for slot in slots:
        days[slot.day_of_week].append(slot.macros)
    return [sum_day_macros(day, macros_list) for day, macros_list in days.items()]


def _compute_week_macros(day_macros: list[DayMacros]) -> DayMacros:
    """Somme les macros de tous les jours de la semaine."""
    total_cal = sum(d.calories  or 0 for d in day_macros) or None
    total_pro = sum(d.protein_g or 0 for d in day_macros) or None
    total_car = sum(d.carbs_g   or 0 for d in day_macros) or None
    total_fat = sum(d.fat_g     or 0 for d in day_macros) or None
    total_fib = sum(d.fiber_g   or 0 for d in day_macros) or None
    return DayMacros(
        day_of_week=-1,  # convention : -1 = semaine entière
        calories=total_cal,
        protein_g=round(total_pro, 1) if total_pro else None,
        carbs_g=round(total_car, 1)   if total_car else None,
        fat_g=round(total_fat, 1)     if total_fat else None,
        fiber_g=round(total_fib, 1)   if total_fib else None,
    )


# ── Raffinement Claude ────────────────────────────────────────────────────────

def _should_call_claude(
    recipes: list[RecipeWithMacros],
    profile: NutritionProfile,
) -> bool:
    """
    Appeler Claude uniquement si :
    - Il y a au moins 4 recettes (sinon l'algorithme local est optimal)
    - L'objectif n'est pas "maintain" (sinon la distribution par variété suffit)
    - Ou si l'utilisateur a des contraintes spécifiques (batch cooking + temps limité)
    """
    has_enough_recipes = len(recipes) >= 4
    has_specific_objective = profile.objective != "maintain"
    has_constraints = bool(profile.excluded_foods or profile.allergies or profile.batch_cooking)
    has_macros = any(r.calories is not None for r in recipes)

    return has_enough_recipes and (has_specific_objective or has_constraints) and has_macros


_REFINE_SYSTEM_PROMPT = """
Tu es VITA, Témoin Bienveillant. Tu aides à organiser la semaine alimentaire
d'un utilisateur en répartissant ses recettes sur ses créneaux.

RÈGLES ABSOLUES
— Tu ne juges JAMAIS l'alimentation. Aucun commentaire du type "ce n'est pas équilibré".
— Tu n'inventes AUCUNE recette. Tu travailles uniquement avec celles fournies.
— Tu ne calcules AUCUNE macro (le calcul est fait par l'algorithme).
— Tu te contentes de RÉORDONNER les créneaux pour mieux servir l'objectif.
— Si l'objectif est "gain" (prise de masse), privilégier les recettes riches en protéines
  le soir et en énergie le matin, sans rigidité.
— Si l'objectif est "lose" (perte de poids), privilégier les repas légers le soir.
— Si batch_cooking=true, la recette la plus longue doit être au créneau 6-dinner (dimanche soir).
— Toujours garder 14 créneaux. Ne pas en supprimer.

FORMAT DE RÉPONSE OBLIGATOIRE — JSON pur, aucun commentaire :
[
  {"recipe_id": "uuid", "day_of_week": 0, "meal_slot": "lunch"},
  ...
]

day_of_week : 0=lundi, 1=mardi, 2=mercredi, 3=jeudi, 4=vendredi, 5=samedi, 6=dimanche
meal_slot : "lunch" ou "dinner"
Exactement 14 objets.
"""


async def _refine_with_claude(
    slots: list[PlannedSlot],
    recipes: list[RecipeWithMacros],
    profile: NutritionProfile,
) -> Optional[list[PlannedSlot]]:
    """
    Demande à Claude de réorganiser les créneaux pour mieux servir l'objectif.
    Retourne None en cas d'échec (l'algorithme local est alors utilisé).
    """
    # Préparer le contexte pour Claude — compact et structuré
    recipes_summary = [
        {
            "id": r.id,
            "name": r.name,
            "total_minutes": r.total_minutes,
            "calories_per_serving": r.calories,
            "protein_g_per_serving": r.protein_g,
        }
        for r in recipes
    ]

    current_plan = [
        {"recipe_id": s.recipe_id, "day_of_week": s.day_of_week, "meal_slot": s.meal_slot}
        for s in slots
    ]

    profile_summary = {
        "objective": profile.objective,
        "activity_level": profile.activity_level,
        "batch_cooking": profile.batch_cooking,
        "cook_time_available": profile.cook_time_available,
        "excluded_foods": profile.excluded_foods[:5],  # max 5 pour rester compact
    }

    user_message = (
        f"Recettes disponibles : {json.dumps(recipes_summary, ensure_ascii=False)}\n\n"
        f"Profil : {json.dumps(profile_summary, ensure_ascii=False)}\n\n"
        f"Plan actuel (algorithme) : {json.dumps(current_plan, ensure_ascii=False)}\n\n"
        "Réorganise les créneaux pour mieux servir l'objectif de l'utilisateur. "
        "Retourne uniquement le JSON des 14 créneaux réordonnés."
    )

    try:
        msg = await _get_client().messages.create(
            model=_get_settings().model_fast,  # claude-haiku — appel léger
            max_tokens=600,
            system=_REFINE_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = msg.content[0].text.strip()
        return _parse_claude_plan(raw, slots, recipes)
    except Exception as exc:
        logger.warning("[meal_planner_agent] Claude refinement failed: %s", exc)
        return None


def _parse_claude_plan(
    raw: str,
    original_slots: list[PlannedSlot],
    recipes: list[RecipeWithMacros],
) -> Optional[list[PlannedSlot]]:
    """
    Parse la réponse JSON de Claude.
    Valide que : 14 créneaux, recipe_ids connus, pas de doublon jour+slot.
    """
    import re

    # Extraire le tableau JSON
    match = re.search(r"\[.*\]", raw, re.DOTALL)
    if not match:
        return None

    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None

    if len(data) != 14:
        return None

    valid_ids    = {r.id for r in recipes}
    recipe_map   = {r.id: r for r in recipes}
    seen_slots   = set()
    result: list[PlannedSlot] = []

    for item in data:
        rid   = item.get("recipe_id", "")
        day   = item.get("day_of_week")
        slot  = item.get("meal_slot", "")

        if rid not in valid_ids:
            return None
        if not isinstance(day, int) or day not in range(7):
            return None
        if slot not in ("lunch", "dinner"):
            return None

        key = (day, slot)
        if key in seen_slots:
            return None
        seen_slots.add(key)

        recipe = recipe_map[rid]
        result.append(PlannedSlot(
            recipe_id=rid,
            recipe_name=recipe.name,
            day_of_week=day,
            meal_slot=slot,
            portions=float(recipe.servings),
        ))

    return result


# ── Helpers ───────────────────────────────────────────────────────────────────

def _empty_result() -> SmartMealPlanResult:
    return SmartMealPlanResult(
        slots=[],
        day_macros=[DayMacros(d, None, None, None, None, None) for d in range(7)],
        week_macros=DayMacros(-1, None, None, None, None, None),
    )
