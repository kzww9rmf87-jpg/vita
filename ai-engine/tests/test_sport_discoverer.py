"""
Tests — SportDiscovererAgent (Sprint 12.2).

Couvre :
  - Algorithme local : débutant sédentaire → options douces
  - Algorithme local : niveau avancé → options variées
  - Activités rejetées exclues
  - Activités attractives prioritaires
  - Temps réaliste pris en compte dans le plan (via planner)
"""
import pytest
from training_planner.discoverer import _local_select, _GENTLE_NAMES
from training_planner.models import SportDiscoverInput, FitnessLevel, SportProfileInput
from training_planner.planner import _resolve_activities


class TestLocalSelect:

    def test_beginner_sedentary_gets_gentle_options(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="beginner",
            apprehension_level="elevee",
        )
        opts = _local_select(inp)
        # Au moins 4 options pour les profils doux
        assert len(opts) >= 4
        # Toutes les premières options doivent être douces
        first_names = {o.name.lower() for o in opts[:3]}
        assert first_names.issubset(_GENTLE_NAMES), f"Options non douces en tête: {first_names}"

    def test_advanced_level_gets_options(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="advanced",
            apprehension_level="aucune",
        )
        opts = _local_select(inp)
        # Un profil non-doux reçoit 4 options (n=4 dans l'algorithme)
        assert len(opts) == 4
        # Toutes les options ont les champs requis
        for o in opts:
            assert o.name
            assert o.why
            assert o.first_step

    def test_rejected_activities_are_excluded(self):
        rejected = ["HIIT", "Musculation", "Course à pied"]
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="advanced",
            rejected_activities=rejected,
        )
        opts = _local_select(inp)
        names = {o.name for o in opts}
        for r in rejected:
            assert r not in names, f"Activité rejetée présente : {r}"

    def test_rejected_case_insensitive(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="intermediate",
            rejected_activities=["hiit", "NATATION"],
        )
        opts = _local_select(inp)
        names_lower = {o.name.lower() for o in opts}
        assert "hiit" not in names_lower
        assert "natation" not in names_lower

    def test_attractive_activities_come_first(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="intermediate",
            attractive_activities=["Natation", "Pilates"],
        )
        opts = _local_select(inp)
        assert opts[0].name == "Natation"
        assert opts[1].name == "Pilates"

    def test_attractive_not_shown_if_rejected(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="intermediate",
            attractive_activities=["HIIT"],
            rejected_activities=["HIIT"],
        )
        opts = _local_select(inp)
        names = {o.name for o in opts}
        assert "HIIT" not in names

    def test_preferred_context_maison_boosts_home_options(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="intermediate",
            preferred_context=["maison"],
        )
        opts = _local_select(inp)
        # Les options maison (strength, mobility) devraient apparaître
        home_types = {o.session_type for o in opts[:3]}
        assert home_types & {"mobility", "strength"}

    def test_beginner_motivation_bouger_gives_gentle(self):
        inp = SportDiscoverInput(
            user_id="u1",
            fitness_level="intermediate",  # niveau pas beginner
            motivation="bouger_un_peu",
        )
        opts = _local_select(inp)
        # La motivation "bouger_un_peu" déclenche le profil doux
        first_names_lower = {o.name.lower() for o in opts[:2]}
        assert first_names_lower & _GENTLE_NAMES


class TestPlannerRejectedAndAttractive:

    def test_rejected_activities_not_in_plan(self):
        profile = SportProfileInput(
            fitness_level=FitnessLevel.intermediate,
            preferred_activities=["HIIT", "Course à pied"],
            rejected_activities=["HIIT"],
            sessions_per_week=2,
        )
        result = _resolve_activities(profile, 2)
        assert "HIIT" not in result

    def test_attractive_activities_prioritized(self):
        profile = SportProfileInput(
            fitness_level=FitnessLevel.intermediate,
            preferred_activities=["Musculation"],
            attractive_activities=["Natation"],
            sessions_per_week=2,
        )
        result = _resolve_activities(profile, 2)
        assert result[0] == "Natation"

    def test_realistic_time_caps_duration(self):
        from training_planner.planner import plan_locally
        from training_planner.models import TrainingPlannerInput

        profile = SportProfileInput(
            fitness_level=FitnessLevel.beginner,
            preferred_activities=["Marche"],
            sessions_per_week=2,
            session_duration_min=60,
            available_days=[1, 3],
            realistic_time_min=20,
        )
        inp = TrainingPlannerInput(user_id="u1", sport_profile=profile)
        sessions = plan_locally(inp)
        # Le cap est appliqué APRÈS le facteur niveau (beginner 0.80 × 60 = 48 → cap à 20)
        for s in sessions:
            assert s.duration_min <= 20, f"Durée {s.duration_min} dépasse realistic_time_min=20"
        # Et la durée doit être exactement 20 (pas inférieure, car le facteur 0.80 × 60 = 48 > 20)
        for s in sessions:
            assert s.duration_min == 20, f"Durée {s.duration_min} devrait être exactement 20"
