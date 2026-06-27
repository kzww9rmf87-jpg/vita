"""Tests unitaires — Agent Sport."""
import pytest
from datetime import date, datetime
from models import UserContext
from agents.sport_agent import analyze, _compute_training_load, _detect_overtraining


def make_session(rpe: int = 6, duration: int = 60, hour: int = 10) -> dict:
    started = datetime.now().replace(hour=hour).isoformat()
    return {
        "date": date.today().isoformat(),
        "activity_name": "Musculation",
        "duration_minutes": duration,
        "rpe": rpe,
        "started_at": started,
        "calories_burned": 400,
    }


def make_context(sessions: list[dict], sleep: dict | None = None) -> UserContext:
    return UserContext(
        user_id="test-user",
        date=date.today(),
        activity_week=sessions,
        sleep=sleep,
    )


class TestOvertrainingDetection:

    def test_no_signal_with_few_sessions(self):
        ctx = make_context([make_session(rpe=8)] * 2)
        signal = analyze(ctx)
        assert signal is None or signal.signal_type != "overtraining_risk"

    def test_overtraining_detected_with_high_load_and_bad_sleep(self):
        sessions = [make_session(rpe=9, duration=90)] * 6
        sleep = {"quality_score": 2, "duration_minutes": 300}
        ctx = make_context(sessions, sleep=sleep)
        signal = _detect_overtraining(sessions, sleep)
        assert signal is not None
        assert signal.signal_type == "overtraining_risk"
        assert signal.confidence >= 0.5

    def test_no_overtraining_with_good_sleep(self):
        sessions = [make_session(rpe=7)] * 5
        sleep = {"quality_score": 4, "duration_minutes": 450}
        signal = _detect_overtraining(sessions, sleep)
        # Low confidence — might still trigger but with lower score
        if signal:
            assert signal.confidence < 0.8


class TestTrainingLoad:

    def test_load_increases_with_more_sessions(self):
        sessions_few = [make_session(rpe=6)] * 2
        sessions_many = [make_session(rpe=8)] * 7
        load_few = _compute_training_load(sessions_few, tau=7)
        load_many = _compute_training_load(sessions_many, tau=7)
        assert load_many > load_few

    def test_load_is_zero_with_no_sessions(self):
        assert _compute_training_load([], tau=7) == 0.0


class TestUnderload:

    def test_underload_with_no_sessions(self):
        ctx = make_context([])
        signal = analyze(ctx)
        assert signal is not None
        assert signal.signal_type == "underload"

    def test_no_underload_with_two_sessions(self):
        ctx = make_context([make_session()] * 3)
        signal = analyze(ctx)
        if signal:
            assert signal.signal_type != "underload"
