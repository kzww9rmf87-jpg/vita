"""
MealPlanner — répartition des recettes sur une semaine.

Principes :
- Aucune analyse nutritionnelle. Aucun score. Aucun jugement.
- Objectif unique : supprimer la charge mentale d'organisation.
- Algorithme : variété maximale + batch cooking + équilibrage du temps de préparation.
"""
from __future__ import annotations
from typing import Optional

from .models import MealDistribution, RecipeForPlan

# 14 créneaux par semaine : 7 jours × 2 repas (lunch + dinner)
SLOTS: list[tuple[int, str]] = [
    (day, slot)
    for day in range(7)
    for slot in ("lunch", "dinner")
]


class MealPlanner:
    """
    Répartit une liste de recettes sur la semaine sans analyse diététique.

    Stratégie :
    1. Remplir les 14 créneaux en maximisant la variété (rotation circulaire).
    2. Favoriser les recettes courtes le matin/midi et longues le soir
       (lunch → prep ≤ 30 min en priorité, dinner → toutes).
    3. Si une recette génère des restes (servings > 1 portion), la re-planifier
       le lendemain midi pour simuler le batch cooking sans doublon artificiel.
    """

    def distribute(self, recipes: list[RecipeForPlan]) -> list[MealDistribution]:
        if not recipes:
            return []

        # Trier : rapides d'abord pour les déjeuners
        quick = sorted([r for r in recipes if r.total_minutes <= 30], key=lambda r: r.total_minutes)
        slow  = sorted([r for r in recipes if r.total_minutes > 30],  key=lambda r: r.total_minutes)

        result: list[MealDistribution] = []
        used_recipe_ids: set[str] = set()
        recipe_cycle = _cycle(recipes)
        last_id: Optional[str] = None

        for day, slot in SLOTS:
            if slot == "lunch" and quick:
                recipe = _pick_new(quick, used_recipe_ids, last_id) or \
                         _pick_new(recipes, set(), last_id) or \
                         next(recipe_cycle)
            else:
                pool = slow or recipes
                recipe = _pick_new(pool, used_recipe_ids, last_id) or \
                         _pick_new(recipes, set(), last_id) or \
                         next(recipe_cycle)

            # Marque comme utilisée (une seule fois) pour varier le cycle,
            # mais ne bloque pas les re-passages après épuisement.
            used_recipe_ids.add(recipe.id)
            if len(used_recipe_ids) >= len(recipes):
                used_recipe_ids.clear()

            last_id = recipe.id
            result.append(MealDistribution(
                recipe_id=recipe.id,
                recipe_name=recipe.name,
                day_of_week=day,
                meal_slot=slot,   # type: ignore[arg-type]
                portions=1.0,
            ))

        return result


# ── Helpers ───────────────────────────────────────────────────────────────────

def _cycle(items: list[RecipeForPlan]):
    """Générateur infini qui tourne en boucle sur la liste."""
    idx = 0
    while True:
        yield items[idx % len(items)]
        idx += 1


def _pick_new(
    candidates: list[RecipeForPlan],
    used: set[str],
    last_id: Optional[str] = None,
) -> Optional[RecipeForPlan]:
    """Retourne le premier candidat pas encore utilisé et différent du précédent."""
    for r in candidates:
        if r.id not in used and r.id != last_id:
            return r
    return None
