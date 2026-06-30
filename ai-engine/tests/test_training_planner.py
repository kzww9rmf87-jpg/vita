"""
Tests du TrainingPlannerAgent — Sprint 12.

Invariants vérifiés :
- FitnessLevel et SessionType acceptent les valeurs attendues
- plan_locally produit ≤ sessions_per_week séances, sur les jours disponibles
- Les durées respectent les limites (10–300 min)
- La mobilité est insérée automatiquement si 3+ séances de musculation seule
- _should_call_claude : False si ≤1 type de séance ou aucune contrainte
- _should_call_claude : True si ≥2 types + contraintes
- TrainingPlannerAgent.plan() retourne toujours un résultat (même si Claude échoue)
- Aucun jugement, score ou badge dans les résultats
- TrainingWeekPlan.rationale n'est jamais vide
"""
import pytest
from unittest import mock

from training_planner.models import (
    FitnessLevel, SessionType,
    SportProfileInput, TrainingPlannerInput,
    PlannedSession, TrainingWeekPlan,
)
from training_planner.planner import (
    plan_locally, build_rationale, _infer_type, _adjusted_duration,
)
from training_planner.agent import TrainingPlannerAgent


# ── Fixtures ──────────────────────────────────────────────────────────────────

def make_input(
    activities: list[str] = ["Musculation", "Course"],
    sessions_per_week: int = 3,
    duration: int = 45,
    days: "list[int] | None" = None,
    fitness: FitnessLevel = FitnessLevel.intermediate,
    pain_areas: "list[str] | None" = None,
    equipment: "list[str] | None" = None,
) -> TrainingPlannerInput:
    return TrainingPlannerInput(
        user_id="test-user",
        sport_profile=SportProfileInput(
            fitness_level=fitness,
            preferred_activities=activities,
            sessions_per_week=sessions_per_week,
            session_duration_min=duration,
            available_days=days or [1, 3, 5],
        ),
        pain_areas=pain_areas or [],
        equipment=equipment or [],
    )


# ── Modèles ───────────────────────────────────────────────────────────────────

def test_fitness_level_enum():
    assert FitnessLevel.beginner == "beginner"
    assert FitnessLevel.elite    == "elite"


def test_session_type_enum():
    assert SessionType.strength == "strength"
    assert SessionType.mobility == "mobility"
    assert SessionType.recovery == "recovery"


# ── Inférence de type ─────────────────────────────────────────────────────────

def test_infer_type_strength():
    assert _infer_type("Musculation") == SessionType.strength
    assert _infer_type("muscu")       == SessionType.strength


def test_infer_type_cardio():
    assert _infer_type("Course à pied") == SessionType.cardio
    assert _infer_type("Natation")      == SessionType.cardio
    assert _infer_type("Vélo")          == SessionType.cardio


def test_infer_type_mobility():
    assert _infer_type("Yoga")     == SessionType.mobility
    assert _infer_type("Mobilité") == SessionType.mobility


def test_infer_type_walk():
    assert _infer_type("Marche rapide") == SessionType.walk


def test_infer_type_combat():
    assert _infer_type("Krav maga") == SessionType.combat


def test_infer_type_default():
    assert _infer_type("Activité libre") == SessionType.cardio


# ── Algorithme local ──────────────────────────────────────────────────────────

def test_plan_locally_respects_sessions_per_week():
    inp = make_input(sessions_per_week=2, days=[0, 1, 2, 3, 4])
    sessions = plan_locally(inp)
    assert len(sessions) == 2


def test_plan_locally_uses_available_days():
    inp = make_input(days=[1, 3, 5], sessions_per_week=3)
    sessions = plan_locally(inp)
    days_used = {s.day_of_week for s in sessions}
    assert days_used.issubset({1, 3, 5})


def test_plan_locally_duration_in_bounds():
    inp = make_input(duration=45, fitness=FitnessLevel.elite)
    sessions = plan_locally(inp)
    for s in sessions:
        assert 10 <= s.duration_min <= 300


def test_plan_locally_beginner_shorter_duration():
    inp_beg = make_input(duration=60, fitness=FitnessLevel.beginner)
    inp_adv = make_input(duration=60, fitness=FitnessLevel.advanced)
    dur_beg = [s.duration_min for s in plan_locally(inp_beg)]
    dur_adv = [s.duration_min for s in plan_locally(inp_adv)]
    assert max(dur_beg) < max(dur_adv)


def test_plan_locally_inserts_mobility_if_only_strength():
    inp = make_input(activities=["Musculation"], sessions_per_week=3, days=[1, 3, 5])
    sessions = plan_locally(inp)
    types = {s.session_type for s in sessions}
    # Mobilité insérée automatiquement pour varier
    assert SessionType.mobility in types


def test_plan_locally_pain_areas_reduce_duration():
    inp_no_pain  = make_input(duration=60, pain_areas=[])
    inp_with_pain = make_input(duration=60, pain_areas=["genou"])
    dur_no   = [s.duration_min for s in plan_locally(inp_no_pain)]
    dur_pain = [s.duration_min for s in plan_locally(inp_with_pain)]
    assert max(dur_pain) < max(dur_no)


def test_plan_locally_pain_area_note():
    inp = make_input(pain_areas=["épaule"])
    sessions = plan_locally(inp)
    notes = [s.notes for s in sessions if s.notes]
    assert any("épaule" in (n or "") for n in notes)


def test_plan_locally_empty_activities_fallback():
    inp = make_input(activities=[])
    sessions = plan_locally(inp)
    assert len(sessions) > 0
    for s in sessions:
        assert s.activity_name == "Activité libre"


def test_build_rationale_not_empty():
    inp      = make_input()
    sessions = plan_locally(inp)
    rationale = build_rationale(inp.sport_profile, sessions)
    assert isinstance(rationale, str) and len(rationale) > 10


def test_build_rationale_no_judgement_words():
    inp      = make_input()
    sessions = plan_locally(inp)
    rationale = build_rationale(inp.sport_profile, sessions).lower()
    forbidden = ["score", "badge", "échec", "fail", "faible", "mauvais"]
    for word in forbidden:
        assert word not in rationale, f"Mot interdit trouvé : {word}"


# ── Agent — _should_call_claude ───────────────────────────────────────────────

def test_should_not_call_claude_single_type():
    """Un seul type de séance → pas besoin de Claude."""
    agent    = TrainingPlannerAgent()
    inp      = make_input(activities=["Musculation"], sessions_per_week=2, days=[1, 3])
    sessions = plan_locally(inp)
    # Force single type
    for s in sessions:
        object.__setattr__(s, "session_type", SessionType.strength)
    assert not agent._should_call_claude(inp, sessions)


def test_should_not_call_claude_no_constraints():
    """Plusieurs types mais sans contraintes → Claude n'apporte pas grand-chose."""
    agent    = TrainingPlannerAgent()
    inp      = make_input(activities=["Musculation", "Course"], pain_areas=[], equipment=[])
    sessions = plan_locally(inp)
    assert not agent._should_call_claude(inp, sessions)


def test_should_call_claude_with_constraints():
    """Plusieurs types + contraintes → Claude personnalise les notes."""
    agent    = TrainingPlannerAgent()
    inp      = make_input(activities=["Musculation", "Yoga"], pain_areas=["genou"])
    sessions = plan_locally(inp)
    # Forcer 2 types différents pour être sûr
    if len(sessions) >= 2:
        # Les activités mixtes produisent déjà 2 types
        types = {s.session_type for s in sessions}
        if len(types) >= 2:
            assert agent._should_call_claude(inp, sessions)


# ── Agent — plan() avec fallback ──────────────────────────────────────────────

@pytest.mark.asyncio
async def test_plan_returns_result_without_claude():
    """plan() retourne un résultat même si Claude n'est pas appelé."""
    agent  = TrainingPlannerAgent()
    inp    = make_input(activities=["Course"], sessions_per_week=2, days=[1, 3])
    result = await agent.plan(inp)
    assert isinstance(result, TrainingWeekPlan)
    assert len(result.sessions) > 0
    assert result.used_claude is False


@pytest.mark.asyncio
async def test_plan_falls_back_if_claude_fails():
    """plan() utilise le local si Claude lève une exception."""
    agent = TrainingPlannerAgent()
    inp   = make_input(activities=["Musculation", "Yoga"], pain_areas=["dos"])

    with mock.patch.object(agent, "_refine_with_claude", side_effect=Exception("timeout")):
        result = await agent.plan(inp)

    assert isinstance(result, TrainingWeekPlan)
    assert result.used_claude is False
    assert len(result.sessions) > 0


@pytest.mark.asyncio
async def test_plan_no_score_or_badge():
    """Les résultats ne contiennent aucun jugement ou gamification."""
    agent  = TrainingPlannerAgent()
    inp    = make_input()
    result = await agent.plan(inp)

    full_text = result.rationale.lower()
    for s in result.sessions:
        full_text += (s.notes or "").lower()

    forbidden = ["score", "badge", "streak", "points", "échec", "mauvais"]
    for word in forbidden:
        assert word not in full_text, f"Mot interdit trouvé : {word}"


# ── Fallback jours vides ──────────────────────────────────────────────────────

def test_plan_locally_empty_days_fallback():
    """Si available_days est vide, le planner utilise [1, 3, 5] par défaut."""
    inp = make_input(days=[])
    sessions = plan_locally(inp)
    assert len(sessions) > 0
    days_used = {s.day_of_week for s in sessions}
    assert days_used.issubset({1, 3, 5})


# ── Contextes adaptatifs (Sprint 13+) ────────────────────────────────────────

def test_training_planner_input_accepts_adaptive_contexts():
    """Les champs contextuels optionnels sont acceptés sans modifier le résultat local."""
    inp = TrainingPlannerInput(
        user_id="test-user",
        sport_profile=SportProfileInput(
            fitness_level=FitnessLevel.intermediate,
            preferred_activities=["Course"],
            sessions_per_week=2,
            session_duration_min=45,
            available_days=[1, 3],
        ),
        journal_context={"mood": "fatigué", "stress": 3},
        sleep_context={"duration_minutes": 360, "quality_score": 2},
        nutrition_context={"calories": 1800},
        meal_plan_context={"plan_name": "Équilibre"},
        recovery_context={"hrv": 45},
        uploaded_documents_context=[{"type": "training_pdf", "filename": "prog.pdf"}],
    )
    sessions = plan_locally(inp)
    assert len(sessions) > 0
    # Le résultat local est identique — les contextes sont ignorés jusqu'au Sprint 13
    assert all(isinstance(s.duration_min, int) for s in sessions)


def test_training_planner_input_contexts_are_optional():
    """Sans aucun contexte adaptatif, le modèle est valide."""
    inp = TrainingPlannerInput(
        user_id="test-user",
        sport_profile=SportProfileInput(
            fitness_level=FitnessLevel.beginner,
            preferred_activities=["Marche"],
            sessions_per_week=2,
            session_duration_min=30,
            available_days=[2, 4],
        ),
    )
    assert inp.journal_context is None
    assert inp.sleep_context is None
    assert inp.uploaded_documents_context is None
    sessions = plan_locally(inp)
    assert len(sessions) > 0


# ── Stubs multimodaux ─────────────────────────────────────────────────────────

def test_uploaded_context_types_defined():
    """Tous les types multimodaux attendus sont définis."""
    from contexts.models import UploadedContextType, UploadedContext, ParsedNutritionContext, ParsedTrainingContext

    assert UploadedContextType.menu_photo   == "menu_photo"
    assert UploadedContextType.training_pdf == "training_pdf"
    assert UploadedContextType.nutrition_pdf == "nutrition_pdf"


def test_uploaded_context_stub_instantiation():
    """Les stubs sont instanciables avec seulement les champs obligatoires."""
    from contexts.models import UploadedContext, UploadedContextType

    ctx = UploadedContext(type=UploadedContextType.training_pdf, filename="prog.pdf")
    assert ctx.raw_text is None  # champ futur, vide pour l'instant


def test_parsed_nutrition_context_all_optional():
    from contexts.models import ParsedNutritionContext
    ctx = ParsedNutritionContext()
    assert ctx.meals is None
    assert ctx.total_calories is None


def test_parsed_training_context_all_optional():
    from contexts.models import ParsedTrainingContext
    ctx = ParsedTrainingContext()
    assert ctx.sessions is None
    assert ctx.program_name is None
