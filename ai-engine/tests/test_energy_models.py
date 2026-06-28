"""
Tests unitaires — Modèles du domaine Énergie.

Vérifie :
  - Validation Pydantic (champs requis, contraintes)
  - Pas de scoring, pas de calcul intelligent dans les modèles
  - EnergyContext agrège correctement les sous-modèles
  - HealthKitProvider : stubs NotImplementedError, is_available() False
"""
import pytest
from datetime import date, datetime, timezone

from energy.models import (
    SleepEntry, SleepWeekSummary,
    ActivitySession, ExerciseSet, ActivityWeekSummary,
    NutritionDaily, Meal, FoodItem, RecipeIngredient, Recipe,
    EnergyContext,
)
from energy.healthkit_provider import HealthKitProvider, HEALTHKIT_READ_PERMISSIONS


# ── Sommeil ───────────────────────────────────────────────────────────────────

class TestSleepEntry:

    def test_minimal_valid_entry(self):
        entry = SleepEntry(date=date.today(), quality_score=3)
        assert entry.quality_score == 3
        assert entry.awakenings == 0
        assert entry.source == "manual"

    def test_quality_score_bounds(self):
        with pytest.raises(Exception):
            SleepEntry(date=date.today(), quality_score=0)
        with pytest.raises(Exception):
            SleepEntry(date=date.today(), quality_score=6)

    def test_awakenings_bounds(self):
        with pytest.raises(Exception):
            SleepEntry(date=date.today(), quality_score=3, awakenings=51)

    def test_duration_computed_from_bedtime_wake(self):
        bedtime   = datetime(2026, 6, 28, 22, 30, tzinfo=timezone.utc)
        wake_time = datetime(2026, 6, 29,  7,  0, tzinfo=timezone.utc)
        entry = SleepEntry(date=date.today(), quality_score=4,
                           bedtime=bedtime, wake_time=wake_time)
        assert entry.duration_minutes == 510  # 8h30

    def test_explicit_duration_not_overwritten(self):
        bedtime   = datetime(2026, 6, 28, 22, 0, tzinfo=timezone.utc)
        wake_time = datetime(2026, 6, 29,  6, 0, tzinfo=timezone.utc)
        entry = SleepEntry(date=date.today(), quality_score=3,
                           bedtime=bedtime, wake_time=wake_time,
                           duration_minutes=500)
        assert entry.duration_minutes == 500

    def test_valid_sources(self):
        for source in ("manual", "apple_health", "oura", "whoop", "garmin"):
            entry = SleepEntry(date=date.today(), quality_score=3, source=source)
            assert entry.source == source

    def test_no_score_field_on_model(self):
        entry = SleepEntry(date=date.today(), quality_score=3)
        fields = entry.model_fields_set | set(entry.__class__.model_fields.keys())
        # Aucun champ "score" calculé ne doit exister (quality_score est une saisie brute)
        assert "sleep_debt" not in fields
        assert "sleep_efficiency" not in fields
        assert "computed_score" not in fields

    def test_week_summary_no_scoring(self):
        entries = [SleepEntry(date=date.today(), quality_score=i, duration_minutes=450)
                   for i in range(1, 6)]
        summary = SleepWeekSummary(entries=entries, nights_logged=5)
        # Le résumé stocke les valeurs brutes, pas un score calculé
        assert summary.nights_logged == 5
        assert len(summary.entries) == 5
        assert not hasattr(summary, "performance_score")


# ── Activité ──────────────────────────────────────────────────────────────────

class TestActivitySession:

    def test_minimal_session(self):
        session = ActivitySession(date=date.today(), activity_name="Course")
        assert session.activity_name == "Course"
        assert session.source == "manual"
        assert session.sets == []

    def test_rpe_bounds(self):
        with pytest.raises(Exception):
            ActivitySession(date=date.today(), activity_name="X", rpe=0)
        with pytest.raises(Exception):
            ActivitySession(date=date.today(), activity_name="X", rpe=11)

    def test_duration_bounds(self):
        with pytest.raises(Exception):
            ActivitySession(date=date.today(), activity_name="X", duration_minutes=601)

    def test_exercise_sets_attached(self):
        s = ExerciseSet(exercise_name="Squat", set_number=1, reps=10, weight_kg=100)
        session = ActivitySession(date=date.today(), activity_name="Musculation",
                                  sets=[s])
        assert len(session.sets) == 1
        assert session.sets[0].exercise_name == "Squat"

    def test_no_load_score_field(self):
        session = ActivitySession(date=date.today(), activity_name="X")
        fields = set(session.__class__.model_fields.keys())
        assert "training_load" not in fields
        assert "fitness_score" not in fields
        assert "overtraining_risk" not in fields

    def test_week_summary_raw_values_only(self):
        sessions = [
            ActivitySession(date=date.today(), activity_name="Course",
                            duration_minutes=60, calories_burned=500)
        ]
        summary = ActivityWeekSummary(sessions=sessions, total_sessions=1,
                                      total_duration_min=60, total_calories=500)
        assert summary.total_sessions == 1
        assert summary.total_calories == 500


# ── Nutrition ─────────────────────────────────────────────────────────────────

class TestNutritionModels:

    def test_nutrition_daily_minimal(self):
        entry = NutritionDaily(date=date.today())
        assert entry.date == date.today()
        assert entry.calories is None

    def test_no_quality_score(self):
        entry = NutritionDaily(date=date.today(), calories=2000)
        fields = set(entry.__class__.model_fields.keys())
        assert "quality_score" not in fields
        assert "adherence_score" not in fields

    def test_meal_minimal(self):
        meal = Meal(date=date.today(), description="Salade César")
        assert meal.description == "Salade César"
        assert meal.is_restaurant is False

    def test_food_item_per_100g(self):
        item = FoodItem(name="Poulet grillé",
                        calories_per_100g=165, protein_per_100g=31)
        assert item.calories_per_100g == 165
        assert item.source == "user"

    def test_recipe_totals_optional(self):
        recipe = Recipe(name="Riz au poulet", servings=2)
        assert recipe.calories is None  # Pas calculé automatiquement
        assert recipe.servings == 2

    def test_recipe_ingredient_quantity_positive(self):
        with pytest.raises(Exception):
            RecipeIngredient(name="Sel", quantity_g=0)

    def test_food_item_micronutrients_extensible(self):
        item = FoodItem(name="Épinards",
                        micronutrients={"vitamine_c_mg": 28, "fer_mg": 2.7})
        assert item.micronutrients["vitamine_c_mg"] == 28


# ── EnergyContext ─────────────────────────────────────────────────────────────

class TestEnergyContext:

    def test_empty_context(self):
        ctx = EnergyContext()
        assert ctx.sleep_last_night is None
        assert ctx.sleep_week == []
        assert ctx.activity_week == []
        assert ctx.nutrition_today is None

    def test_full_context(self):
        sleep = SleepEntry(date=date.today(), quality_score=4, duration_minutes=480)
        meal  = Meal(date=date.today(), description="Pâtes")
        ctx = EnergyContext(
            sleep_last_night=sleep,
            sleep_week=[sleep],
            meals_today=[meal],
        )
        assert ctx.sleep_last_night.quality_score == 4
        assert len(ctx.meals_today) == 1

    def test_context_has_no_analysis_fields(self):
        ctx = EnergyContext()
        fields = set(ctx.__class__.model_fields.keys())
        assert "recommendations" not in fields
        assert "insights" not in fields
        assert "energy_score" not in fields


# ── HealthKit Provider ────────────────────────────────────────────────────────

class TestHealthKitProvider:

    def test_is_available_returns_false_sprint7(self):
        assert HealthKitProvider.is_available() is False

    def test_read_permissions_not_empty(self):
        assert len(HEALTHKIT_READ_PERMISSIONS) > 0
        assert "HKCategoryTypeIdentifierSleepAnalysis" in HEALTHKIT_READ_PERMISSIONS
        assert "HKWorkoutTypeIdentifier" in HEALTHKIT_READ_PERMISSIONS

    def test_write_permissions_empty(self):
        from energy.healthkit_provider import HEALTHKIT_WRITE_PERMISSIONS
        assert HEALTHKIT_WRITE_PERMISSIONS == ()

    def test_sleep_provider_raises_not_implemented(self):
        provider = HealthKitProvider()
        with pytest.raises(NotImplementedError):
            import asyncio
            asyncio.run(provider.sleep.get_entry("user-1", date.today()))

    def test_activity_provider_raises_not_implemented(self):
        provider = HealthKitProvider()
        with pytest.raises(NotImplementedError):
            import asyncio
            asyncio.run(provider.activity.get_sessions("user-1"))

    def test_nutrition_provider_raises_not_implemented(self):
        provider = HealthKitProvider()
        with pytest.raises(NotImplementedError):
            import asyncio
            asyncio.run(provider.nutrition.get_daily("user-1", date.today()))

    def test_provider_has_all_three_sub_providers(self):
        p = HealthKitProvider()
        assert p.sleep is not None
        assert p.activity is not None
        assert p.nutrition is not None


# ── Providers ─────────────────────────────────────────────────────────────────

class TestProviderInterfaces:

    def test_sleep_provider_is_abstract(self):
        from energy.providers import SleepProvider
        with pytest.raises(TypeError):
            SleepProvider()

    def test_activity_provider_is_abstract(self):
        from energy.providers import ActivityProvider
        with pytest.raises(TypeError):
            ActivityProvider()

    def test_nutrition_provider_is_abstract(self):
        from energy.providers import NutritionProvider
        with pytest.raises(TypeError):
            NutritionProvider()

    def test_energy_data_provider_is_abstract(self):
        from energy.providers import EnergyDataProvider
        with pytest.raises(TypeError):
            EnergyDataProvider()
