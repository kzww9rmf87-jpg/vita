"""Tests unitaires — Agent Nutrition."""
import pytest
from datetime import date
from models import UserContext
from agents.nutrition_agent import analyze, _detect_binge_risk, _detect_protein_deficit, _detect_alcohol_pattern


def make_nutrition_entry(
    calories: int = 2000,
    protein: float = 130,
    alcohol: float = 0,
    water: int = 2000,
) -> dict:
    return {
        "date": date.today().isoformat(),
        "calories": calories,
        "protein_g": protein,
        "alcohol_g": alcohol,
        "water_ml": water,
        "fiber_g": 20,
    }


def make_context(entries: list[dict], weight_kg: float = 75) -> UserContext:
    return UserContext(
        user_id="test-user",
        date=date.today(),
        nutrition_week=entries,
        snapshot={"weight_kg": weight_kg},
    )


class TestBingeRisk:

    def test_binge_risk_detected_with_prolonged_deficit(self):
        entries = [make_nutrition_entry(calories=1400, protein=80)] * 3
        signal = _detect_binge_risk(entries, 75)
        assert signal is not None
        assert signal.signal_type == "binge_risk"

    def test_no_binge_risk_with_adequate_calories(self):
        entries = [make_nutrition_entry(calories=2000, protein=130)] * 3
        signal = _detect_binge_risk(entries, 75)
        assert signal is None

    def test_binge_risk_higher_confidence_with_low_protein(self):
        entries_low_protein = [make_nutrition_entry(calories=1400, protein=60)] * 3
        entries_ok_protein = [make_nutrition_entry(calories=1400, protein=120)] * 3
        s1 = _detect_binge_risk(entries_low_protein, 75)
        s2 = _detect_binge_risk(entries_ok_protein, 75)
        if s1 and s2:
            assert s1.confidence >= s2.confidence


class TestProteinDeficit:

    def test_low_protein_detected(self):
        entries = [make_nutrition_entry(protein=80)] * 5
        signal = _detect_protein_deficit(entries, 80)
        assert signal is not None
        assert signal.signal_type == "low_protein"

    def test_adequate_protein_no_signal(self):
        entries = [make_nutrition_entry(protein=140)] * 5
        signal = _detect_protein_deficit(entries, 75)
        assert signal is None


class TestAlcoholPattern:

    def test_alcohol_pattern_with_3_days(self):
        entries = [make_nutrition_entry(alcohol=15)] * 3 + [make_nutrition_entry()] * 4
        signal = _detect_alcohol_pattern(entries)
        assert signal is not None
        assert signal.signal_type == "alcohol_pattern"
        assert signal.confidence > 0.9

    def test_no_alcohol_pattern_with_one_day(self):
        entries = [make_nutrition_entry(alcohol=20)] + [make_nutrition_entry()] * 6
        signal = _detect_alcohol_pattern(entries)
        assert signal is None
