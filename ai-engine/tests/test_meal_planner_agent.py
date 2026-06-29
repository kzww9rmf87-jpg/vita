"""
Tests du MealPlannerAgent — Sprint 9 + Sprint 9.3.

Invariants vérifiés :
- _local_distribute produit N créneaux selon meals_per_day (2→14, 3→21, 4→28)
- Batch cooking place une recette longue au dimanche soir
- _should_call_claude respecte ses conditions (≥4 recettes, objectif, macros)
- _parse_claude_plan valide les entrées Claude (count, IDs, doublons, slots valides)
- plan() retourne SmartMealPlanResult complet même sans profil
- plan() retourne used_claude=False si conditions non remplies
- activity_schedule accepté sans erreur (§7 — réservé Sprint futur)
- weekMacros == somme des dayMacros
- Aucun jugement alimentaire dans les résultats
"""
import json
import pytest
from unittest import mock

from meal_planner.agent import (
    MealPlannerAgent,
    SmartMealPlanInput,
    NutritionProfile,
    RecipeWithMacros,
    PlannedSlot,
    SmartMealPlanResult,
    _local_distribute,
    _build_slots_order,
    _should_call_claude,
    _parse_claude_plan,
)


# ── Fixtures ──────────────────────────────────────────────────────────────────

def make_recipe(rid: str, name: str, prep: int = 15, cook: int = 20,
                servings: int = 4, calories: int | None = None,
                protein_g: float | None = None) -> RecipeWithMacros:
    return RecipeWithMacros(
        id=rid, name=name, servings=servings,
        prep_minutes=prep, cook_minutes=cook,
        calories=calories, protein_g=protein_g,
    )


RECIPES_2 = [
    make_recipe("r1", "Poulet rôti", prep=20, cook=60),
    make_recipe("r2", "Salade niçoise", prep=15, cook=0),
]

RECIPES_4_WITH_MACROS = [
    make_recipe("r1", "Poulet rôti",     prep=20, cook=60, calories=450, protein_g=35.0),
    make_recipe("r2", "Salade niçoise",  prep=15, cook=0,  calories=250, protein_g=12.0),
    make_recipe("r3", "Pâtes carbonara", prep=10, cook=20, calories=520, protein_g=20.0),
    make_recipe("r4", "Soupe lentilles", prep=15, cook=40, calories=300, protein_g=18.0),
]

RECIPES_4_NO_MACROS = [
    make_recipe(f"r{i}", f"Recette {i}") for i in range(1, 5)
]

PROFILE_GAIN    = NutritionProfile(objective="gain",     batch_cooking=False, meals_per_day=2)
PROFILE_BATCH   = NutritionProfile(objective="maintain", batch_cooking=True,  meals_per_day=2)
PROFILE_MAINTAIN = NutritionProfile(objective="maintain", batch_cooking=False, meals_per_day=2)

PROFILE_3_MEALS = NutritionProfile(objective="maintain", batch_cooking=False, meals_per_day=3)
PROFILE_4_MEALS = NutritionProfile(objective="maintain", batch_cooking=False, meals_per_day=4)


# ── Distribution locale ───────────────────────────────────────────────────────

class TestLocalDistribute:

    def test_produces_14_slots(self):
        slots = _local_distribute(RECIPES_2, None)
        assert len(slots) == 14

    def test_all_days_covered(self):
        slots = _local_distribute(RECIPES_2, None)
        days = {s.day_of_week for s in slots}
        assert days == set(range(7))

    def test_all_slots_covered_per_day(self):
        slots = _local_distribute(RECIPES_2, None)
        for day in range(7):
            day_slots = {s.meal_slot for s in slots if s.day_of_week == day}
            assert day_slots == {"lunch", "dinner"}

    def test_recipe_ids_from_input(self):
        input_ids = {r.id for r in RECIPES_4_WITH_MACROS}
        slots = _local_distribute(RECIPES_4_WITH_MACROS, None)
        for slot in slots:
            assert slot.recipe_id in input_ids

    def test_portions_positive(self):
        slots = _local_distribute(RECIPES_2, None)
        assert all(s.portions > 0 for s in slots)

    def test_no_consecutive_same_recipe_with_4_recipes(self):
        slots = _local_distribute(RECIPES_4_WITH_MACROS, None)
        ids = [s.recipe_id for s in slots]
        for a, b in zip(ids, ids[1:]):
            assert a != b, "Deux créneaux consécutifs identiques"

    def test_batch_cooking_sunday_dinner_is_slow_recipe(self):
        long_recipe  = make_recipe("long",  "Cassoulet", prep=30, cook=120)
        quick_recipe = make_recipe("quick", "Salade",    prep=5,  cook=0)
        slow_recipe2 = make_recipe("slow2", "Poulet",    prep=10, cook=40)
        recipes = [long_recipe, quick_recipe, slow_recipe2]
        profile = NutritionProfile(objective="maintain", batch_cooking=True)
        slots = _local_distribute(recipes, profile)
        sunday_dinner = next(
            (s for s in slots if s.day_of_week == 6 and s.meal_slot == "dinner"), None
        )
        assert sunday_dinner is not None
        # Batch cooking : dimanche soir = une recette longue (> 30 min)
        recipe_map = {r.id: r for r in recipes}
        placed = recipe_map[sunday_dinner.recipe_id]
        assert placed.total_minutes > 30

    def test_single_recipe_fills_all_14(self):
        single = [make_recipe("r1", "Riz sauté")]
        slots = _local_distribute(single, None)
        assert len(slots) == 14
        assert all(s.recipe_id == "r1" for s in slots)


# ── _should_call_claude ───────────────────────────────────────────────────────

class TestShouldCallClaude:

    def test_false_when_fewer_than_4_recipes(self):
        assert not _should_call_claude(RECIPES_2, PROFILE_GAIN)

    def test_false_when_maintain_and_no_constraints(self):
        assert not _should_call_claude(RECIPES_4_WITH_MACROS, PROFILE_MAINTAIN)

    def test_false_when_no_macros_in_recipes(self):
        assert not _should_call_claude(RECIPES_4_NO_MACROS, PROFILE_GAIN)

    def test_true_when_gain_objective_with_macros(self):
        assert _should_call_claude(RECIPES_4_WITH_MACROS, PROFILE_GAIN)

    def test_true_when_batch_cooking_with_macros(self):
        assert _should_call_claude(RECIPES_4_WITH_MACROS, PROFILE_BATCH)

    def test_true_when_allergies_with_macros(self):
        profile = NutritionProfile(objective="maintain", allergies=["lait"])
        assert _should_call_claude(RECIPES_4_WITH_MACROS, profile)

    def test_true_when_excluded_foods_with_macros(self):
        profile = NutritionProfile(objective="maintain", excluded_foods=["porc"])
        assert _should_call_claude(RECIPES_4_WITH_MACROS, profile)

    def test_false_when_exactly_3_recipes(self):
        three = RECIPES_4_WITH_MACROS[:3]
        assert not _should_call_claude(three, PROFILE_GAIN)


# ── _parse_claude_plan ────────────────────────────────────────────────────────

class TestParseClaundePlan:

    def _make_valid_json(self, recipes: list[RecipeWithMacros]) -> str:
        slots_order = [(d, s) for d in range(7) for s in ("lunch", "dinner")]
        data = [
            {"recipe_id": recipes[i % len(recipes)].id, "day_of_week": day, "meal_slot": slot}
            for i, (day, slot) in enumerate(slots_order)
        ]
        return json.dumps(data)

    def _make_original_slots(self, recipes: list[RecipeWithMacros]) -> list[PlannedSlot]:
        slots_order = [(d, s) for d in range(7) for s in ("lunch", "dinner")]
        return [
            PlannedSlot(
                recipe_id=recipes[i % len(recipes)].id,
                recipe_name=recipes[i % len(recipes)].name,
                day_of_week=day,
                meal_slot=slot,
                portions=float(recipes[i % len(recipes)].servings),
            )
            for i, (day, slot) in enumerate(slots_order)
        ]

    def test_valid_json_returns_14_slots(self):
        recipes = RECIPES_4_WITH_MACROS
        raw = self._make_valid_json(recipes)
        original = self._make_original_slots(recipes)
        result = _parse_claude_plan(raw, original, recipes)
        assert result is not None
        assert len(result) == 14

    def test_wrong_count_returns_none(self):
        data = [{"recipe_id": "r1", "day_of_week": 0, "meal_slot": "lunch"}]
        result = _parse_claude_plan(json.dumps(data), [], RECIPES_4_WITH_MACROS)
        assert result is None

    def test_invalid_recipe_id_returns_none(self):
        slots_order = [(d, s) for d in range(7) for s in ("lunch", "dinner")]
        data = [
            {"recipe_id": "unknown-id", "day_of_week": day, "meal_slot": slot}
            for day, slot in slots_order
        ]
        result = _parse_claude_plan(json.dumps(data), [], RECIPES_4_WITH_MACROS)
        assert result is None

    def test_duplicate_day_slot_returns_none(self):
        # 14 entrées mais avec un doublon day+slot
        data = [{"recipe_id": "r1", "day_of_week": 0, "meal_slot": "lunch"}] * 14
        result = _parse_claude_plan(json.dumps(data), [], RECIPES_4_WITH_MACROS)
        assert result is None

    def test_invalid_day_returns_none(self):
        slots_order = [(d, s) for d in range(7) for s in ("lunch", "dinner")]
        data = [
            {"recipe_id": RECIPES_4_WITH_MACROS[i % 4].id, "day_of_week": day, "meal_slot": slot}
            for i, (day, slot) in enumerate(slots_order)
        ]
        data[0]["day_of_week"] = 99  # jour invalide
        result = _parse_claude_plan(json.dumps(data), [], RECIPES_4_WITH_MACROS)
        assert result is None

    def test_json_embedded_in_text_extracted(self):
        recipes = RECIPES_4_WITH_MACROS
        raw_json = self._make_valid_json(recipes)
        raw = f"Voici le plan réorganisé :\n{raw_json}\nBonne semaine !"
        original = self._make_original_slots(recipes)
        result = _parse_claude_plan(raw, original, recipes)
        assert result is not None

    def test_invalid_json_returns_none(self):
        result = _parse_claude_plan("Ce n'est pas du JSON", [], RECIPES_4_WITH_MACROS)
        assert result is None


# ── MealPlannerAgent.plan ─────────────────────────────────────────────────────

class TestMealPlannerAgentPlan:

    @pytest.mark.asyncio
    async def test_empty_recipes_returns_empty_result(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=[])
        result = await agent.plan(inp)
        assert isinstance(result, SmartMealPlanResult)
        assert result.slots == []
        assert not result.used_claude

    @pytest.mark.asyncio
    async def test_returns_14_slots_without_profile(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_2)
        result = await agent.plan(inp)
        assert len(result.slots) == 14

    @pytest.mark.asyncio
    async def test_used_claude_false_when_too_few_recipes(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_2, profile=PROFILE_GAIN)
        result = await agent.plan(inp)
        assert not result.used_claude

    @pytest.mark.asyncio
    async def test_used_claude_false_when_maintain_no_constraints(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(
            user_id="u1", recipes=RECIPES_4_WITH_MACROS, profile=PROFILE_MAINTAIN
        )
        result = await agent.plan(inp)
        assert not result.used_claude

    @pytest.mark.asyncio
    async def test_day_macros_has_7_entries(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_4_WITH_MACROS)
        result = await agent.plan(inp)
        assert len(result.day_macros) == 7

    @pytest.mark.asyncio
    async def test_week_macros_day_of_week_is_minus_one(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_4_WITH_MACROS)
        result = await agent.plan(inp)
        assert result.week_macros.day_of_week == -1

    @pytest.mark.asyncio
    async def test_macros_populated_when_recipes_have_calories(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_4_WITH_MACROS)
        result = await agent.plan(inp)
        assert result.week_macros.calories is not None
        assert result.week_macros.calories > 0

    @pytest.mark.asyncio
    async def test_macros_none_when_recipes_have_no_calories(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_4_NO_MACROS)
        result = await agent.plan(inp)
        assert result.week_macros.calories is None

    @pytest.mark.asyncio
    async def test_used_claude_true_when_conditions_met(self):
        valid_json_slots = [
            {"recipe_id": RECIPES_4_WITH_MACROS[i % 4].id, "day_of_week": d, "meal_slot": s}
            for i, (d, s) in enumerate([(d, s) for d in range(7) for s in ("lunch", "dinner")])
        ]

        mock_msg = mock.MagicMock()
        mock_msg.content = [mock.MagicMock(text=json.dumps(valid_json_slots))]

        with mock.patch(
            "meal_planner.agent._get_client",
            return_value=mock.MagicMock(
                messages=mock.MagicMock(
                    create=mock.AsyncMock(return_value=mock_msg)
                )
            ),
        ), mock.patch(
            "meal_planner.agent._get_settings",
            return_value=mock.MagicMock(model_fast="claude-haiku-4-5-20251001"),
        ):
            agent = MealPlannerAgent()
            inp = SmartMealPlanInput(
                user_id="u1",
                recipes=RECIPES_4_WITH_MACROS,
                profile=PROFILE_GAIN,
            )
            result = await agent.plan(inp)

        assert result.used_claude is True
        assert len(result.slots) == 14

    @pytest.mark.asyncio
    async def test_falls_back_to_local_when_claude_fails(self):
        with mock.patch(
            "meal_planner.agent._get_client",
            return_value=mock.MagicMock(
                messages=mock.MagicMock(
                    create=mock.AsyncMock(side_effect=Exception("API down"))
                )
            ),
        ), mock.patch(
            "meal_planner.agent._get_settings",
            return_value=mock.MagicMock(model_fast="claude-haiku-4-5-20251001"),
        ):
            agent = MealPlannerAgent()
            inp = SmartMealPlanInput(
                user_id="u1",
                recipes=RECIPES_4_WITH_MACROS,
                profile=PROFILE_GAIN,
            )
            result = await agent.plan(inp)

        assert result.used_claude is False
        assert len(result.slots) == 14


# ── Aucun jugement alimentaire ────────────────────────────────────────────────

class TestNoNutritionalJudgement:

    @pytest.mark.asyncio
    async def test_slot_has_no_score_field(self):
        agent = MealPlannerAgent()
        inp = SmartMealPlanInput(user_id="u1", recipes=RECIPES_2)
        result = await agent.plan(inp)
        for slot in result.slots:
            assert not hasattr(slot, "score")
            assert not hasattr(slot, "quality")
            assert not hasattr(slot, "recommendation")

    def test_result_has_no_judgement_fields(self):
        from dataclasses import fields
        for f in fields(SmartMealPlanResult):
            assert f.name not in {"score", "quality", "analysis", "recommendation"}


# ── Sprint 9.3 — Slots dynamiques ────────────────────────────────────────────

class TestBuildSlotsOrder:
    """§1 — VITA ne prescrit pas le rythme alimentaire."""

    def test_2_meals_produces_14_slots(self):
        order = _build_slots_order(2)
        assert len(order) == 14
        slot_types = {s for _, s in order}
        assert slot_types == {"lunch", "dinner"}

    def test_3_meals_produces_21_slots(self):
        order = _build_slots_order(3)
        assert len(order) == 21
        slot_types = {s for _, s in order}
        assert slot_types == {"breakfast", "lunch", "dinner"}

    def test_4_meals_produces_28_slots(self):
        order = _build_slots_order(4)
        assert len(order) == 28
        slot_types = {s for _, s in order}
        assert slot_types == {"breakfast", "lunch", "dinner", "snack"}

    def test_all_7_days_covered_regardless_of_meal_count(self):
        for n in (2, 3, 4):
            order  = _build_slots_order(n)
            days   = {d for d, _ in order}
            assert days == set(range(7)), f"meals_per_day={n} : tous les jours doivent être couverts"


class TestDynamicDistribute:
    """§1 — Distribution locale dynamique selon meals_per_day."""

    def test_no_profile_defaults_to_2_meals_14_slots(self):
        slots = _local_distribute(RECIPES_4_WITH_MACROS, None)
        assert len(slots) == 14
        slot_types = {s.meal_slot for s in slots}
        assert slot_types == {"lunch", "dinner"}

    def test_3_meals_per_day_produces_21_slots(self):
        slots = _local_distribute(RECIPES_4_WITH_MACROS, PROFILE_3_MEALS)
        assert len(slots) == 21
        slot_types = {s.meal_slot for s in slots}
        assert "breakfast" in slot_types
        assert "lunch" in slot_types
        assert "dinner" in slot_types

    def test_4_meals_per_day_produces_28_slots(self):
        slots = _local_distribute(RECIPES_4_WITH_MACROS, PROFILE_4_MEALS)
        assert len(slots) == 28
        slot_types = {s.meal_slot for s in slots}
        assert slot_types == {"breakfast", "lunch", "dinner", "snack"}

    def test_breakfast_prefers_very_quick_recipe(self):
        very_quick = make_recipe("fast", "Yaourt granola", prep=5, cook=0)
        slow_r     = make_recipe("slow", "Cassoulet",      prep=30, cook=90)
        mid_r      = make_recipe("mid",  "Omelette",       prep=10, cook=15)
        recipes    = [very_quick, slow_r, mid_r]

        slots = _local_distribute(recipes, PROFILE_3_MEALS)
        breakfast_slots = [s for s in slots if s.meal_slot == "breakfast"]
        assert len(breakfast_slots) == 7  # un par jour
        # La recette très rapide doit apparaître dans la majorité des petits-déjeuners
        fast_count = sum(1 for s in breakfast_slots if s.recipe_id == "fast")
        assert fast_count >= 3, "Le petit-déjeuner doit préférer les recettes rapides (≤15 min)"

    def test_all_days_covered_with_3_meals(self):
        slots = _local_distribute(RECIPES_4_WITH_MACROS, PROFILE_3_MEALS)
        days  = {s.day_of_week for s in slots}
        assert days == set(range(7))

    def test_all_days_covered_with_4_meals(self):
        slots = _local_distribute(RECIPES_4_WITH_MACROS, PROFILE_4_MEALS)
        days  = {s.day_of_week for s in slots}
        assert days == set(range(7))

    def test_batch_cooking_dinner_still_prioritised_with_3_meals(self):
        long_r  = make_recipe("long",  "Cassoulet", prep=30, cook=120)
        quick_r = make_recipe("quick", "Salade",    prep=5,  cook=0)
        mid_r   = make_recipe("mid",   "Pâtes",     prep=10, cook=20)
        recipes = [long_r, quick_r, mid_r]
        profile = NutritionProfile(objective="maintain", batch_cooking=True, meals_per_day=3)
        slots   = _local_distribute(recipes, profile)

        sunday_dinner = next(
            (s for s in slots if s.day_of_week == 6 and s.meal_slot == "dinner"), None
        )
        assert sunday_dinner is not None
        recipe_map = {r.id: r for r in recipes}
        placed = recipe_map[sunday_dinner.recipe_id]
        assert placed.total_minutes > 30


class TestWeekMacrosInvariant:
    """weekMacros doit être égal à la somme des dayMacros (§9)."""

    @pytest.mark.asyncio
    async def test_week_macros_equals_sum_of_day_macros(self):
        agent = MealPlannerAgent()
        inp   = SmartMealPlanInput(user_id="u1", recipes=RECIPES_4_WITH_MACROS)
        result = await agent.plan(inp)

        total_cal = sum(d.calories or 0 for d in result.day_macros)
        total_pro = sum(d.protein_g or 0 for d in result.day_macros)

        assert result.week_macros.day_of_week == -1
        assert result.week_macros.calories == total_cal
        assert abs((result.week_macros.protein_g or 0) - total_pro) < 0.05

    @pytest.mark.asyncio
    async def test_week_macros_none_when_no_calories(self):
        agent  = MealPlannerAgent()
        inp    = SmartMealPlanInput(user_id="u1", recipes=RECIPES_4_NO_MACROS)
        result = await agent.plan(inp)
        assert result.week_macros.calories is None


class TestActivitySchedulePlaceholder:
    """§7 — activity_schedule réservé pour un sprint futur."""

    @pytest.mark.asyncio
    async def test_activity_schedule_accepted_without_error(self):
        agent  = MealPlannerAgent()
        inp    = SmartMealPlanInput(
            user_id="u1",
            recipes=RECIPES_2,
            activity_schedule=[{"day": 1, "type": "running", "duration_min": 45}],
        )
        result = await agent.plan(inp)
        assert isinstance(result, SmartMealPlanResult)
        assert len(result.slots) == 14  # profile=None → 2 repas/jour


class TestParseClaundePlanDynamic:
    """_parse_claude_plan accepte n'importe quel slot valide fourni dynamiquement."""

    def _make_valid_json_for_slots(
        self,
        recipes: list[RecipeWithMacros],
        slot_order: list[tuple[int, str]],
    ) -> str:
        data = [
            {"recipe_id": recipes[i % len(recipes)].id, "day_of_week": day, "meal_slot": slot}
            for i, (day, slot) in enumerate(slot_order)
        ]
        return json.dumps(data)

    def test_parse_21_slots_breakfast_lunch_dinner(self):
        slot_order = [(d, s) for d in range(7) for s in ("breakfast", "lunch", "dinner")]
        raw        = self._make_valid_json_for_slots(RECIPES_4_WITH_MACROS, slot_order)
        result     = _parse_claude_plan(
            raw, [], RECIPES_4_WITH_MACROS,
            expected_count=21,
            valid_slots={"breakfast", "lunch", "dinner"},
        )
        assert result is not None
        assert len(result) == 21

    def test_parse_28_slots_all_four_slots(self):
        slot_order = [(d, s) for d in range(7) for s in ("breakfast", "lunch", "dinner", "snack")]
        raw        = self._make_valid_json_for_slots(RECIPES_4_WITH_MACROS, slot_order)
        result     = _parse_claude_plan(
            raw, [], RECIPES_4_WITH_MACROS,
            expected_count=28,
            valid_slots={"breakfast", "lunch", "dinner", "snack"},
        )
        assert result is not None
        assert len(result) == 28

    def test_wrong_slot_returns_none(self):
        slot_order = [(d, s) for d in range(7) for s in ("lunch", "dinner")]
        data       = [
            {"recipe_id": RECIPES_4_WITH_MACROS[i % 4].id, "day_of_week": day, "meal_slot": slot}
            for i, (day, slot) in enumerate(slot_order)
        ]
        data[0]["meal_slot"] = "breakfast"  # slot non autorisé pour un plan 2 repas
        result = _parse_claude_plan(
            json.dumps(data), [], RECIPES_4_WITH_MACROS,
            expected_count=14,
            valid_slots={"lunch", "dinner"},
        )
        assert result is None

    def test_fallback_to_local_when_claude_returns_wrong_count(self):
        """Claude renvoie 14 slots pour un plan 3 repas → fallback local."""
        slot_order = [(d, s) for d in range(7) for s in ("lunch", "dinner")]
        raw        = self._make_valid_json_for_slots(RECIPES_4_WITH_MACROS, slot_order)
        result     = _parse_claude_plan(
            raw, [], RECIPES_4_WITH_MACROS,
            expected_count=21,  # plan 3 repas attend 21
            valid_slots={"breakfast", "lunch", "dinner"},
        )
        assert result is None  # mismatch count → None → algorithme local
