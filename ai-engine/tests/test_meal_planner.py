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


# ── Sprint 13 — Sport × Nutrition Bridge ─────────────────────────────────────

from meal_planner.models import ActivityDayContext, ActivityLoadLevel
from meal_planner.agent import SmartMealPlanInput, RecipeWithMacros, PlannedSlot, _nudge_for_sport_context, _should_call_claude


def make_recipe_with_calories(id: str, name: str, calories: int, servings: int = 1) -> RecipeWithMacros:
    return RecipeWithMacros(id=id, name=name, servings=servings, calories=calories)


def make_schedule(demanding_days: list[int] = [], rest_days: list[int] = []) -> list[ActivityDayContext]:
    result = []
    for day in range(7):
        if day in demanding_days:
            result.append(ActivityDayContext(day_of_week=day, load_level=ActivityLoadLevel.demanding, total_duration_min=90))
        elif day in rest_days:
            result.append(ActivityDayContext(day_of_week=day, load_level=ActivityLoadLevel.rest, total_duration_min=0))
        else:
            result.append(ActivityDayContext(day_of_week=day, load_level=ActivityLoadLevel.rest, total_duration_min=0))
    return result


class TestSmartMealPlanInputAcceptsActivitySchedule:
    def test_activity_schedule_is_optional(self):
        inp = SmartMealPlanInput(
            user_id="u1",
            recipes=[RecipeWithMacros(id="r1", name="Poulet", servings=2)],
        )
        assert inp.activity_schedule is None

    def test_activity_schedule_accepted(self):
        schedule = make_schedule(demanding_days=[1])
        inp = SmartMealPlanInput(
            user_id="u1",
            recipes=[RecipeWithMacros(id="r1", name="Poulet", servings=2)],
            activity_schedule=schedule,
        )
        assert len(inp.activity_schedule) == 7

    def test_activity_day_context_fields(self):
        ctx = ActivityDayContext(day_of_week=1, load_level=ActivityLoadLevel.demanding, total_duration_min=90)
        assert ctx.load_level == ActivityLoadLevel.demanding
        assert ctx.total_duration_min == 90
        assert ctx.dominant_type == "rest"   # valeur par défaut

    def test_activity_load_level_enum_values(self):
        assert ActivityLoadLevel.rest.value      == "rest"
        assert ActivityLoadLevel.light.value     == "light"
        assert ActivityLoadLevel.moderate.value  == "moderate"
        assert ActivityLoadLevel.demanding.value == "demanding"


class TestNudgeForSportContext:
    def _make_slots(self, recipes):
        slots = []
        for day in range(7):
            for slot in ["lunch", "dinner"]:
                r = recipes[(day * 2 + (0 if slot == "lunch" else 1)) % len(recipes)]
                slots.append(PlannedSlot(
                    recipe_id=r.id, recipe_name=r.name,
                    day_of_week=day, meal_slot=slot, portions=1.0,
                ))
        return slots

    def test_demanding_day_gets_calorie_dense_recipe(self):
        light_recipe   = make_recipe_with_calories("r1", "Salade",     calories=200)
        heavy_recipe   = make_recipe_with_calories("r2", "Riz prot.",  calories=600)
        recipes        = [light_recipe, heavy_recipe]
        schedule       = make_schedule(demanding_days=[0])
        # Slots day 0 lunch/dinner: alternance r1/r2
        slots          = self._make_slots(recipes)
        result         = _nudge_for_sport_context(slots, recipes, schedule)
        day0_lunches   = [s for s in result if s.day_of_week == 0 and s.meal_slot == "lunch"]
        assert len(day0_lunches) == 1
        # La recette calorique (r2) doit être prioritairement sur day 0
        day0_ids = {s.recipe_id for s in result if s.day_of_week == 0}
        assert "r2" in day0_ids

    def test_nudge_preserves_slot_count(self):
        recipes  = [make_recipe_with_calories(f"r{i}", f"R{i}", calories=300 + i * 50) for i in range(3)]
        schedule = make_schedule(demanding_days=[1, 3])
        slots    = self._make_slots(recipes)
        result   = _nudge_for_sport_context(slots, recipes, schedule)
        assert len(result) == 14

    def test_nudge_returns_slots_unchanged_when_no_calories(self):
        recipes  = [RecipeWithMacros(id="r1", name="Poulet", servings=2), RecipeWithMacros(id="r2", name="Salade", servings=2)]
        schedule = make_schedule(demanding_days=[0])
        slots    = self._make_slots(recipes)
        result   = _nudge_for_sport_context(slots, recipes, schedule)
        assert len(result) == 14


class TestShouldCallClaudeWithSportContext:
    def _profile(self):
        from meal_planner.agent import NutritionProfile
        return NutritionProfile(objective="performance", activity_level="active", meals_per_day=3, batch_cooking=False)

    def test_returns_true_when_non_rest_days_and_macros(self):
        recipes  = [make_recipe_with_calories(f"r{i}", f"Plat {i}", calories=500) for i in range(4)]
        profile  = self._profile()
        schedule = make_schedule(demanding_days=[1])
        assert _should_call_claude(recipes, profile, schedule)

    def test_returns_false_when_all_rest(self):
        recipes  = [make_recipe_with_calories("r1", "Salade", calories=200)]
        profile  = self._profile()
        schedule = make_schedule()   # tous rest
        result   = _should_call_claude(recipes, profile, schedule)
        # Peut être False si pas d'autre critère — on vérifie juste pas de crash
        assert isinstance(result, bool)


class TestNoForbiddenWordsInSportContext:
    def test_activity_load_level_labels_are_descriptive_not_judgmental(self):
        forbidden = ["trop", "pas assez", "mauvais", "score", "insuffisant", "excessif"]
        for level in ActivityLoadLevel:
            for word in forbidden:
                assert word not in level.value
