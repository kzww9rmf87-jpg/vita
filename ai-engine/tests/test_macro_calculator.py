"""
Tests du calculateur de macros — module 100 % déterministe.

Invariants vérifiés :
- Formule Mifflin-St Jeor correcte pour male/female/other
- TDEE = BMR × multiplicateur d'activité connu
- Macros cohérentes par objectif (ratios, calories)
- calculate_meal_macros : ratio portions/servings appliqué correctement
- sum_day_macros : addition correcte, None si aucune donnée
- calculate_targets : retourne None si données anthropométriques manquantes
"""
import pytest
from meal_planner.macro_calculator import (
    calculate_bmr,
    calculate_tdee,
    calculate_targets,
    calculate_meal_macros,
    sum_day_macros,
    MacroTargets,
    MealMacros,
    DayMacros,
    ACTIVITY_MULTIPLIERS,
    MACRO_RATIOS,
    OBJECTIVE_CALORIE_FACTOR,
)


# ── BMR (Mifflin-St Jeor) ─────────────────────────────────────────────────────

class TestCalculateBMR:

    def test_male_formula(self):
        # 10×80 + 6.25×175 - 5×30 + 5 = 800 + 1093.75 - 150 + 5 = 1748.75
        result = calculate_bmr(80, 175, 30, "male")
        assert abs(result - 1748.75) < 0.01

    def test_female_formula(self):
        # 10×60 + 6.25×165 - 5×25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
        result = calculate_bmr(60, 165, 25, "female")
        assert abs(result - 1345.25) < 0.01

    def test_other_is_median_of_male_and_female(self):
        bmr_m = calculate_bmr(70, 170, 35, "male")
        bmr_f = calculate_bmr(70, 170, 35, "female")
        bmr_o = calculate_bmr(70, 170, 35, "other")
        assert abs(bmr_o - (bmr_m + bmr_f) / 2) < 0.01

    def test_male_gt_female_same_params(self):
        assert calculate_bmr(70, 170, 35, "male") > calculate_bmr(70, 170, 35, "female")

    def test_higher_weight_raises_bmr(self):
        assert calculate_bmr(90, 175, 30, "male") > calculate_bmr(70, 175, 30, "male")

    def test_higher_height_raises_bmr(self):
        assert calculate_bmr(70, 185, 30, "male") > calculate_bmr(70, 165, 30, "male")

    def test_older_age_lowers_bmr(self):
        assert calculate_bmr(70, 175, 50, "male") < calculate_bmr(70, 175, 25, "male")


# ── TDEE ─────────────────────────────────────────────────────────────────────

class TestCalculateTDEE:

    def test_sedentary_multiplier(self):
        bmr = 1500.0
        assert abs(calculate_tdee(bmr, "sedentary") - bmr * 1.20) < 0.01

    def test_moderate_multiplier(self):
        bmr = 1600.0
        assert abs(calculate_tdee(bmr, "moderate") - bmr * 1.55) < 0.01

    def test_very_active_multiplier(self):
        bmr = 1800.0
        assert abs(calculate_tdee(bmr, "very_active") - bmr * 1.90) < 0.01

    def test_all_known_levels_use_correct_multiplier(self):
        bmr = 1000.0
        for level, mult in ACTIVITY_MULTIPLIERS.items():
            assert abs(calculate_tdee(bmr, level) - bmr * mult) < 0.01

    def test_unknown_level_falls_back_to_moderate(self):
        bmr = 1500.0
        result = calculate_tdee(bmr, "unknown_level")
        assert abs(result - bmr * 1.55) < 0.01

    def test_higher_activity_yields_higher_tdee(self):
        bmr = 1500.0
        assert calculate_tdee(bmr, "sedentary") < calculate_tdee(bmr, "moderate") < calculate_tdee(bmr, "very_active")


# ── calculate_targets ────────────────────────────────────────────────────────

class TestCalculateTargets:

    def test_returns_none_without_weight(self):
        result = calculate_targets(None, 175, 30, "male", "moderate", "maintain")
        assert result is None

    def test_returns_none_without_height(self):
        result = calculate_targets(70, None, 30, "male", "moderate", "maintain")
        assert result is None

    def test_returns_none_without_age(self):
        result = calculate_targets(70, 175, None, "male", "moderate", "maintain")
        assert result is None

    def test_returns_none_without_sex(self):
        result = calculate_targets(70, 175, 30, None, "moderate", "maintain")
        assert result is None

    def test_returns_macro_targets_when_complete(self):
        result = calculate_targets(70, 175, 30, "male", "moderate", "maintain")
        assert isinstance(result, MacroTargets)

    def test_calories_positive(self):
        result = calculate_targets(70, 175, 30, "male", "moderate", "maintain")
        assert result is not None and result.calories > 0

    def test_gain_objective_has_more_calories_than_maintain(self):
        maintain = calculate_targets(70, 175, 30, "male", "moderate", "maintain")
        gain     = calculate_targets(70, 175, 30, "male", "moderate", "gain")
        assert maintain is not None and gain is not None
        assert gain.calories > maintain.calories

    def test_lose_objective_has_fewer_calories_than_maintain(self):
        maintain = calculate_targets(70, 175, 30, "male", "moderate", "maintain")
        lose     = calculate_targets(70, 175, 30, "male", "moderate", "lose")
        assert maintain is not None and lose is not None
        assert lose.calories < maintain.calories

    def test_macro_ratios_respected_for_maintain(self):
        result = calculate_targets(70, 175, 30, "male", "moderate", "maintain")
        assert result is not None
        protein_kcal = result.protein_g * 4
        carbs_kcal   = result.carbs_g   * 4
        fat_kcal     = result.fat_g     * 9
        total = protein_kcal + carbs_kcal + fat_kcal
        assert abs(protein_kcal / total - 0.25) < 0.02
        assert abs(carbs_kcal   / total - 0.50) < 0.02
        assert abs(fat_kcal     / total - 0.25) < 0.02

    def test_lose_has_higher_protein_ratio_than_maintain(self):
        maintain = calculate_targets(70, 175, 30, "female", "moderate", "maintain")
        lose     = calculate_targets(70, 175, 30, "female", "moderate", "lose")
        assert maintain is not None and lose is not None
        assert lose.protein_g / lose.calories > maintain.protein_g / maintain.calories

    def test_fiber_uses_male_recommendation(self):
        result = calculate_targets(80, 180, 30, "male", "moderate", "maintain")
        assert result is not None
        assert result.fiber_g == 38.0

    def test_fiber_uses_female_recommendation(self):
        result = calculate_targets(60, 165, 25, "female", "light", "maintain")
        assert result is not None
        assert result.fiber_g == 25.0

    def test_to_dict_has_all_keys(self):
        result = calculate_targets(70, 175, 30, "male", "moderate", "maintain")
        assert result is not None
        d = result.to_dict()
        assert "target_calories" in d
        assert "target_protein_g" in d
        assert "target_carbs_g" in d
        assert "target_fat_g" in d
        assert "target_fiber_g" in d


# ── calculate_meal_macros ────────────────────────────────────────────────────

class TestCalculateMealMacros:

    def test_returns_empty_when_no_calories(self):
        result = calculate_meal_macros(None, None, None, None, None, 1, 4)
        assert result.calories is None

    def test_portions_equal_servings_returns_full_macros(self):
        result = calculate_meal_macros(400, 30.0, 50.0, 15.0, 5.0, 4, 4)
        assert result.calories == 400
        assert abs(result.protein_g - 30.0) < 0.1
        assert abs(result.carbs_g   - 50.0) < 0.1
        assert abs(result.fat_g     - 15.0) < 0.1
        assert abs(result.fiber_g   -  5.0) < 0.1

    def test_half_portions_halves_macros(self):
        result = calculate_meal_macros(400, 30.0, 50.0, 15.0, 5.0, 2, 4)
        assert result.calories == 200
        assert abs(result.protein_g - 15.0) < 0.1

    def test_double_portions_doubles_macros(self):
        result = calculate_meal_macros(400, 30.0, 50.0, 15.0, 5.0, 8, 4)
        assert result.calories == 800
        assert abs(result.protein_g - 60.0) < 0.1

    def test_none_protein_stays_none(self):
        result = calculate_meal_macros(300, None, 40.0, 10.0, None, 1, 2)
        assert result.protein_g is None
        assert result.calories is not None

    def test_servings_zero_guard(self):
        # servings=0 ne doit pas faire de ZeroDivisionError
        result = calculate_meal_macros(400, 30.0, 50.0, 15.0, 5.0, 1, 0)
        assert result.calories is not None


# ── sum_day_macros ────────────────────────────────────────────────────────────

class TestSumDayMacros:

    def test_returns_none_when_no_data(self):
        macros = [MealMacros.empty(), MealMacros.empty()]
        result = sum_day_macros(0, macros)
        assert result.calories is None
        assert result.protein_g is None

    def test_sums_calories(self):
        m1 = MealMacros(calories=400, protein_g=30.0, carbs_g=50.0, fat_g=15.0, fiber_g=5.0)
        m2 = MealMacros(calories=500, protein_g=40.0, carbs_g=60.0, fat_g=20.0, fiber_g=6.0)
        result = sum_day_macros(0, [m1, m2])
        assert result.calories == 900
        assert abs(result.protein_g - 70.0) < 0.1
        assert abs(result.carbs_g   - 110.0) < 0.1

    def test_preserves_day_of_week(self):
        result = sum_day_macros(3, [MealMacros.empty()])
        assert result.day_of_week == 3

    def test_mixed_none_and_values(self):
        m1 = MealMacros(calories=400, protein_g=30.0, carbs_g=50.0, fat_g=15.0, fiber_g=5.0)
        m2 = MealMacros.empty()
        result = sum_day_macros(1, [m1, m2])
        assert result.calories == 400

    def test_to_dict_keys(self):
        m1 = MealMacros(calories=300, protein_g=20.0, carbs_g=35.0, fat_g=10.0, fiber_g=3.0)
        result = sum_day_macros(2, [m1])
        d = result.to_dict()
        assert "day_of_week" in d
        assert "calories" in d
        assert "protein_g" in d
