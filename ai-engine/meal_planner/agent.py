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
from .models import ActivityDayContext, ActivityLoadLevel, MealDistribution, RecipeForPlan
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
    user_id:           str
    recipes:           list[RecipeWithMacros]
    profile:           Optional[NutritionProfile] = None
    pantry:            list[str] = []
    activity_schedule: Optional[list[ActivityDayContext]] = None  # Sprint 13 — plan sportif actif


@dataclass
class PlannedSlot:
    """Un créneau planifié avec ses macros."""
    recipe_id:   str
    recipe_name: str
    day_of_week: int
    meal_slot:   str  # "breakfast" | "lunch" | "dinner" | "snack"
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
        recipes           = input.recipes
        profile           = input.profile
        activity_schedule = input.activity_schedule

        if not recipes:
            return _empty_result()

        # ── Étape 1 : distribution locale ─────────────────────────────────────
        raw_slots = _local_distribute(recipes, profile, activity_schedule)

        # ── Étape 1b : nudge sport-aware (si plan sportif disponible + macros) ─
        if activity_schedule and any(r.calories for r in recipes):
            raw_slots = _nudge_for_sport_context(raw_slots, recipes, activity_schedule)

        # ── Étape 2 : calcul des macros par créneau (toujours déterministe) ──
        recipe_map = {r.id: r for r in recipes}
        slots_with_macros = _attach_macros(raw_slots, recipe_map)

        # ── Étape 3 : raffinement Claude (optionnel) ──────────────────────────
        used_claude = False
        if profile and _should_call_claude(recipes, profile, activity_schedule):
            refined = await _refine_with_claude(
                slots_with_macros, recipes, profile, activity_schedule
            )
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

# Créneaux disponibles selon le nombre de repas par jour (§1)
_SLOT_SETS: dict[int, tuple[str, ...]] = {
    2: ("lunch", "dinner"),
    3: ("breakfast", "lunch", "dinner"),
    4: ("breakfast", "lunch", "dinner", "snack"),
}


def _build_slots_order(meals_per_day: int) -> list[tuple[int, str]]:
    """Construit la liste des créneaux pour une semaine selon le rythme choisi."""
    n = max(2, min(4, meals_per_day))
    slots = _SLOT_SETS.get(n, ("lunch", "dinner"))
    return [(day, slot) for day in range(7) for slot in slots]


def _local_distribute(
    recipes: list[RecipeWithMacros],
    profile: Optional[NutritionProfile],
    activity_schedule: Optional[list[ActivityDayContext]] = None,
) -> list[PlannedSlot]:
    """
    Distribue les recettes sur les créneaux selon des règles locales.
    Le nombre de créneaux dépend de meals_per_day (2→14, 3→21, 4→28).
    Aucun appel réseau. Résultat déterministe.
    """
    meals_per_day = profile.meals_per_day if profile else 2
    slots_order   = _build_slots_order(meals_per_day)
    batch_cooking = profile.batch_cooking if profile else False
    cook_time     = profile.cook_time_available if profile else "moderate"

    very_quick = [r for r in recipes if r.total_minutes <= 15]
    quick      = [r for r in recipes if r.total_minutes <= 30]
    slow       = [r for r in recipes if r.total_minutes > 30]
    if not quick:
        quick = list(recipes)

    result: list[PlannedSlot] = []
    used: set[str] = set()
    cycle_idx = 0
    last_id: Optional[str] = None

    for day, slot in slots_order:
        is_weekend             = day >= 5
        is_sunday_dinner       = (day == 6 and slot == "dinner")
        is_pre_sunday_dinner   = (batch_cooking and day == 6 and slot != "dinner")

        if batch_cooking and is_sunday_dinner and slow:
            # Batch cooking : réserver le dimanche soir pour les préparations longues
            recipe = _pick(slow, used, last_id) or _pick(recipes, set(), last_id) or recipes[cycle_idx % len(recipes)]
        elif is_pre_sunday_dinner and slow:
            # Dimanche avant le dîner batch cooking : éviter les recettes lentes (les garder pour le soir)
            # Fallback progressif dans le pool non-lent uniquement
            pool   = very_quick or quick
            recipe = (
                _pick(pool, used, last_id)
                or _pick(pool, set(), last_id)
                or _pick(pool, set(), None)
                or recipes[cycle_idx % len(recipes)]
            )
        elif slot in ("breakfast", "snack"):
            # Petit-déjeuner et collation : recettes très rapides en priorité
            pool   = very_quick or quick
            recipe = _pick(pool, used, last_id) or _pick(recipes, set(), last_id) or recipes[cycle_idx % len(recipes)]
        elif slot == "lunch" and not is_weekend:
            # Déjeuners de semaine → recette rapide
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
            portions=float(recipe.servings),
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

def _nudge_for_sport_context(
    slots: list[PlannedSlot],
    recipes: list[RecipeWithMacros],
    activity_schedule: list[ActivityDayContext],
) -> list[PlannedSlot]:
    """
    Réorganise légèrement les créneaux pour que les journées sportives intenses
    reçoivent les recettes plus caloriques disponibles, et les journées de repos
    les plus légères — sans modifier les jours ni les créneaux meal_slot.

    Algorithme : échange les recipe_ids entre créneaux de même meal_slot
    quand cela améliore l'alignement sport × calorie.
    Silencieux : aucune donnée sport n'est exposée à l'utilisateur.
    """
    if not slots:
        return slots

    recipe_map   = {r.id: r for r in recipes}
    day_load     = {ctx.day_of_week: ctx.load_level for ctx in activity_schedule}

    # Score pour chaque slot : calories × préférence (+1 demanding, -1 rest, 0 autre)
    def _load_score(day: int) -> int:
        load = day_load.get(day, ActivityLoadLevel.rest)
        if load == ActivityLoadLevel.demanding: return  1
        if load == ActivityLoadLevel.rest:      return -1
        return 0

    # Grouper les slots par meal_slot pour ne permuter que les équivalents
    from collections import defaultdict
    by_slot: dict[str, list[int]] = defaultdict(list)
    for i, s in enumerate(slots):
        by_slot[s.meal_slot].append(i)

    result = list(slots)

    for meal_slot, indices in by_slot.items():
        # Trier les indices : les journées demanding d'abord
        sorted_indices = sorted(indices, key=lambda i: -_load_score(result[i].day_of_week))
        # Trier les recipe_ids par calories desc pour les allouer aux jours demandants
        current_recipes = [result[i].recipe_id for i in indices]
        calories_by_id  = lambda rid: (recipe_map.get(rid) and recipe_map[rid].calories) or 0
        sorted_recipes  = sorted(current_recipes, key=calories_by_id, reverse=True)

        # Réattribuer
        for idx, recipe_id in zip(sorted_indices, sorted_recipes):
            recipe = recipe_map.get(recipe_id)
            if recipe:
                old = result[idx]
                result[idx] = PlannedSlot(
                    recipe_id=recipe.id,
                    recipe_name=recipe.name,
                    day_of_week=old.day_of_week,
                    meal_slot=old.meal_slot,
                    portions=float(recipe.servings),
                )

    return result


def _should_call_claude(
    recipes: list[RecipeWithMacros],
    profile: NutritionProfile,
    activity_schedule: Optional[list[ActivityDayContext]] = None,
) -> bool:
    """
    Appeler Claude si :
    - ≥ 4 recettes avec macros
    - objectif non-"maintain" OU contraintes OU contexte sportif actif
    """
    has_enough_recipes     = len(recipes) >= 4
    has_macros             = any(r.calories is not None for r in recipes)
    has_specific_objective = profile.objective != "maintain"
    has_constraints        = bool(profile.excluded_foods or profile.allergies or profile.batch_cooking)
    has_sport_context      = bool(
        activity_schedule and
        any(d.load_level != ActivityLoadLevel.rest for d in activity_schedule)
    )

    return has_enough_recipes and has_macros and (
        has_specific_objective or has_constraints or has_sport_context
    )


def _build_refine_system_prompt(
    total_slots: int,
    slot_types: list[str],
    activity_schedule: Optional[list[ActivityDayContext]] = None,
) -> str:
    """Construit le prompt système de raffinement selon le nombre de créneaux, les slots et le sport."""
    slots_str = " ou ".join(f'"{s}"' for s in slot_types)

    sport_block = ""
    if activity_schedule and any(d.load_level != ActivityLoadLevel.rest for d in activity_schedule):
        day_names = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
        lines = []
        for d in sorted(activity_schedule, key=lambda x: x.day_of_week):
            if d.load_level != ActivityLoadLevel.rest:
                lines.append(
                    f"  • {day_names[d.day_of_week]} : {d.load_level.value} "
                    f"({d.total_duration_min} min, {d.dominant_type})"
                )
        if lines:
            sport_block = (
                "\n\nCONTEXTE SPORTIF DE LA SEMAINE\n"
                + "\n".join(lines)
                + "\n— Journées 'demanding' : placer naturellement les recettes plus riches en glucides/énergie si disponibles."
                + "\n— Journées 'rest' : placer les recettes plus légères si disponibles."
                + "\n— Ne JAMAIS mentionner ce contexte à l'utilisateur. Aucun commentaire sur la charge sportive."
            )

    return f"""Tu es VITA, Témoin Bienveillant. Tu aides à organiser la semaine alimentaire
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
— Toujours garder {total_slots} créneaux. Ne pas en supprimer.{sport_block}

FORMAT DE RÉPONSE OBLIGATOIRE — JSON pur, aucun commentaire :
[
  {{"recipe_id": "uuid", "day_of_week": 0, "meal_slot": "lunch"}},
  ...
]

day_of_week : 0=lundi, 1=mardi, 2=mercredi, 3=jeudi, 4=vendredi, 5=samedi, 6=dimanche
meal_slot : {slots_str}
Exactement {total_slots} objets.
"""


async def _refine_with_claude(
    slots: list[PlannedSlot],
    recipes: list[RecipeWithMacros],
    profile: NutritionProfile,
    activity_schedule: Optional[list[ActivityDayContext]] = None,
) -> Optional[list[PlannedSlot]]:
    """
    Demande à Claude de réorganiser les créneaux pour mieux servir l'objectif.
    Retourne None en cas d'échec (l'algorithme local est alors utilisé).
    """
    total_slots      = len(slots)
    valid_slot_types = sorted(set(s.meal_slot for s in slots))
    system_prompt    = _build_refine_system_prompt(total_slots, valid_slot_types, activity_schedule)

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
        "excluded_foods": profile.excluded_foods[:5],
    }

    user_message = (
        f"Recettes disponibles : {json.dumps(recipes_summary, ensure_ascii=False)}\n\n"
        f"Profil : {json.dumps(profile_summary, ensure_ascii=False)}\n\n"
        f"Plan actuel (algorithme) : {json.dumps(current_plan, ensure_ascii=False)}\n\n"
        f"Réorganise les créneaux pour mieux servir l'objectif de l'utilisateur. "
        f"Retourne uniquement le JSON des {total_slots} créneaux réordonnés."
    )

    try:
        msg = await _get_client().messages.create(
            model=_get_settings().model_fast,
            max_tokens=900,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = msg.content[0].text.strip()
        return _parse_claude_plan(raw, slots, recipes,
                                  expected_count=total_slots,
                                  valid_slots=set(valid_slot_types))
    except Exception as exc:
        logger.warning("[meal_planner_agent] Claude refinement failed: %s", exc)
        return None


def _parse_claude_plan(
    raw: str,
    original_slots: list[PlannedSlot],
    recipes: list[RecipeWithMacros],
    expected_count: int = 14,
    valid_slots: Optional[set[str]] = None,
) -> Optional[list[PlannedSlot]]:
    """
    Parse la réponse JSON de Claude.
    Valide : N créneaux (selon meals_per_day), recipe_ids connus, pas de doublon jour+slot.
    """
    import re

    if valid_slots is None:
        valid_slots = {"lunch", "dinner"}

    match = re.search(r"\[.*\]", raw, re.DOTALL)
    if not match:
        return None

    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None

    if len(data) != expected_count:
        return None

    valid_ids  = {r.id for r in recipes}
    recipe_map = {r.id: r for r in recipes}
    seen_slots = set()
    result: list[PlannedSlot] = []

    for item in data:
        rid  = item.get("recipe_id", "")
        day  = item.get("day_of_week")
        slot = item.get("meal_slot", "")

        if rid not in valid_ids:
            return None
        if not isinstance(day, int) or day not in range(7):
            return None
        if slot not in valid_slots:
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
