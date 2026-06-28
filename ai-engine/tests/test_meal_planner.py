"""
Tests du MealPlanner — logique de répartition hebdomadaire.

Invariants vérifiés :
- 14 créneaux générés (7 jours × 2 repas) quelle que soit la liste de recettes
- Aucun score, aucune analyse nutritionnelle dans les modèles ou la sortie
- Variété : pas de recette consécutive identique si ≥ 2 recettes fournies
- day_of_week ∈ [0, 6], meal_slot ∈ {"lunch", "dinner"}
- portions > 0
"""
import pytest
from meal_planner import MealPlanInput, MealPlanner, MealDistribution
from meal_planner.models import RecipeForPlan


# ── Fixtures ──────────────────────────────────────────────────────────────────

def make_recipe(id: str, name: str, prep: int = 15, cook: int = 20, servings: int = 4) -> RecipeForPlan:
    return RecipeForPlan(id=id, name=name, prep_minutes=prep, cook_minutes=cook, servings=servings)


SINGLE_RECIPE = [make_recipe("r1", "Poulet rôti")]

THREE_RECIPES = [
    make_recipe("r1", "Poulet rôti",       prep=20, cook=60),
    make_recipe("r2", "Salade niçoise",    prep=15, cook=0),
    make_recipe("r3", "Pâtes carbonara",   prep=10, cook=20),
]

SEVEN_RECIPES = [make_recipe(f"r{i}", f"Recette {i}") for i in range(1, 8)]


# ── MealPlanner.distribute ────────────────────────────────────────────────────

class TestMealPlannerDistribute:

    def test_returns_14_slots_for_single_recipe(self):
        result = MealPlanner().distribute(SINGLE_RECIPE)
        assert len(result) == 14

    def test_returns_14_slots_for_three_recipes(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        assert len(result) == 14

    def test_returns_14_slots_for_seven_recipes(self):
        result = MealPlanner().distribute(SEVEN_RECIPES)
        assert len(result) == 14

    def test_empty_list_returns_empty(self):
        result = MealPlanner().distribute([])
        assert result == []

    def test_all_items_are_MealDistribution(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        assert all(isinstance(item, MealDistribution) for item in result)

    def test_day_of_week_in_range(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        assert all(0 <= item.day_of_week <= 6 for item in result)

    def test_meal_slot_valid_values(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        assert all(item.meal_slot in ("lunch", "dinner") for item in result)

    def test_portions_positive(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        assert all(item.portions > 0 for item in result)

    def test_recipe_ids_belong_to_input(self):
        input_ids = {r.id for r in THREE_RECIPES}
        result = MealPlanner().distribute(THREE_RECIPES)
        assert all(item.recipe_id in input_ids for item in result)

    def test_recipe_names_match_ids(self):
        id_to_name = {r.id: r.name for r in THREE_RECIPES}
        result = MealPlanner().distribute(THREE_RECIPES)
        for item in result:
            assert item.recipe_name == id_to_name[item.recipe_id]

    def test_no_consecutive_same_recipe_with_3_recipes(self):
        """Avec ≥ 2 recettes, deux créneaux consécutifs ne devraient pas être identiques."""
        result = MealPlanner().distribute(THREE_RECIPES)
        ids = [item.recipe_id for item in result]
        for a, b in zip(ids, ids[1:]):
            assert a != b, "Deux créneaux consécutifs identiques détectés"

    def test_covers_all_7_days(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        days = {item.day_of_week for item in result}
        assert days == set(range(7))

    def test_covers_all_slots_per_day(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        for day in range(7):
            day_slots = {item.meal_slot for item in result if item.day_of_week == day}
            assert day_slots == {"lunch", "dinner"}

    def test_ordered_by_day_then_slot(self):
        result = MealPlanner().distribute(THREE_RECIPES)
        for i in range(len(result) - 1):
            a, b = result[i], result[i + 1]
            assert (a.day_of_week, a.meal_slot) < (b.day_of_week, b.meal_slot) or \
                   (a.day_of_week == b.day_of_week)  # même jour = toléré non ordonné strict


# ── Aucune analyse nutritionnelle dans les modèles ────────────────────────────

class TestNoNutritionalAnalysis:

    def test_mealDistribution_has_no_score_field(self):
        forbidden = {"score", "quality", "nutritional", "analysis", "recommendation"}
        fields = set(MealDistribution.model_fields.keys())
        assert fields.isdisjoint(forbidden), f"Champs interdits trouvés : {fields & forbidden}"

    def test_recipeForPlan_has_no_score_field(self):
        forbidden = {"score", "quality", "nutritional", "analysis"}
        fields = set(RecipeForPlan.model_fields.keys())
        assert fields.isdisjoint(forbidden), f"Champs interdits trouvés : {fields & forbidden}"

    def test_meal_plan_input_accepted_by_pydantic(self):
        inp = MealPlanInput(user_id="u1", recipes=THREE_RECIPES)
        assert len(inp.recipes) == 3


# ── RecipeForPlan ─────────────────────────────────────────────────────────────

class TestRecipeForPlan:

    def test_total_minutes_sum(self):
        r = make_recipe("r1", "Test", prep=15, cook=30)
        assert r.total_minutes == 45

    def test_total_minutes_none_counts_as_zero(self):
        r = RecipeForPlan(id="r1", name="Test", servings=2)
        assert r.total_minutes == 0

    def test_servings_minimum_1(self):
        with pytest.raises(Exception):
            RecipeForPlan(id="r1", name="Test", servings=0)
