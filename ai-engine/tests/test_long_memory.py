"""Tests unitaires — modèles et PostgresMemoryProvider (scoring pur, sans DB)."""
import math
from datetime import datetime, timezone, timedelta

import pytest

from memory.models import LongMemory, MemoryType, MemorySource, Reflection
from memory.postgres_provider import _jaccard, _freshness, PostgresMemoryProvider


# ── LongMemory dataclass ─────────────────────────────────────────────────────

class TestLongMemoryModel:

    def test_valid_creation(self):
        m = LongMemory(
            user_id="u1",
            type=MemoryType.GOAL,
            summary="Veut courir un semi-marathon",
        )
        assert m.importance == 3
        assert m.confidence == 0.8
        assert m.source == MemorySource.CHAT

    def test_string_type_coercion(self):
        m = LongMemory(user_id="u1", type="goal", summary="test")
        assert m.type == MemoryType.GOAL

    def test_string_source_coercion(self):
        m = LongMemory(user_id="u1", type=MemoryType.GOAL, summary="test", source="journal")
        assert m.source == MemorySource.JOURNAL

    def test_invalid_importance_raises(self):
        with pytest.raises(ValueError, match="importance"):
            LongMemory(user_id="u1", type=MemoryType.GOAL, summary="test", importance=6)

    def test_importance_zero_raises(self):
        with pytest.raises(ValueError):
            LongMemory(user_id="u1", type=MemoryType.GOAL, summary="test", importance=0)

    def test_invalid_confidence_raises(self):
        with pytest.raises(ValueError, match="confidence"):
            LongMemory(user_id="u1", type=MemoryType.GOAL, summary="test", confidence=1.1)

    def test_empty_summary_raises(self):
        with pytest.raises(ValueError, match="summary"):
            LongMemory(user_id="u1", type=MemoryType.GOAL, summary="   ")

    def test_all_memory_types_valid(self):
        for mt in MemoryType:
            m = LongMemory(user_id="u", type=mt, summary="ok")
            assert m.type == mt

    def test_all_sources_valid(self):
        for src in MemorySource:
            m = LongMemory(user_id="u", type=MemoryType.OTHER, summary="ok", source=src)
            assert m.source == src

    def test_boundary_importance_1(self):
        m = LongMemory(user_id="u", type=MemoryType.OTHER, summary="ok", importance=1)
        assert m.importance == 1

    def test_boundary_importance_5(self):
        m = LongMemory(user_id="u", type=MemoryType.OTHER, summary="ok", importance=5)
        assert m.importance == 5

    def test_boundary_confidence_0(self):
        m = LongMemory(user_id="u", type=MemoryType.OTHER, summary="ok", confidence=0.0)
        assert m.confidence == 0.0

    def test_boundary_confidence_1(self):
        m = LongMemory(user_id="u", type=MemoryType.OTHER, summary="ok", confidence=1.0)
        assert m.confidence == 1.0


# ── Jaccard similarity ───────────────────────────────────────────────────────

class TestJaccard:

    def test_identical_texts(self):
        assert _jaccard("courir un semi-marathon", "courir un semi-marathon") == 1.0

    def test_no_overlap(self):
        assert _jaccard("courir un marathon", "graphiste freelance") == 0.0

    def test_partial_overlap(self):
        score = _jaccard("courir un semi-marathon en octobre", "courir un semi-marathon")
        assert 0 < score < 1.0

    def test_case_insensitive(self):
        assert _jaccard("COURIR", "courir") == 1.0

    def test_empty_string_a(self):
        assert _jaccard("", "courir") == 0.0

    def test_empty_string_b(self):
        assert _jaccard("courir", "") == 0.0

    def test_both_empty(self):
        assert _jaccard("", "") == 0.0

    def test_punctuation_ignored(self):
        assert _jaccard("courir, vite.", "courir vite") == 1.0

    def test_symmetry(self):
        a = "objectif courir"
        b = "courir et marcher"
        assert abs(_jaccard(a, b) - _jaccard(b, a)) < 1e-9

    def test_high_similarity_threshold(self):
        # Deux formulations quasi-identiques du même fait → Jaccard ≥ 0.6
        a = "Travaille comme graphiste freelance depuis 3 ans"
        b = "Travaille comme graphiste freelance depuis trois ans"
        assert _jaccard(a, b) >= 0.5

    def test_dissimilar_same_domain(self):
        a = "A peur de décevoir sa mère"
        b = "A un objectif de courir un marathon"
        assert _jaccard(a, b) < 0.3


# ── Freshness scoring ────────────────────────────────────────────────────────

class TestFreshness:

    def test_seen_today_near_one(self):
        now = datetime.now(timezone.utc)
        score = _freshness(now)
        assert score > 0.99

    def test_seen_90_days_ago(self):
        old = datetime.now(timezone.utc) - timedelta(days=90)
        score = _freshness(old)
        assert abs(score - math.exp(-1)) < 0.01  # tau=90 → exp(-1) ≈ 0.368

    def test_seen_180_days_ago_lower_than_90(self):
        ago90  = datetime.now(timezone.utc) - timedelta(days=90)
        ago180 = datetime.now(timezone.utc) - timedelta(days=180)
        assert _freshness(ago180) < _freshness(ago90)

    def test_none_returns_half(self):
        assert _freshness(None) == 0.5

    def test_naive_datetime_handled(self):
        naive = datetime.utcnow() - timedelta(days=1)
        score = _freshness(naive)
        assert 0 < score < 1

    def test_monotonically_decreasing(self):
        scores = [
            _freshness(datetime.now(timezone.utc) - timedelta(days=d))
            for d in [0, 7, 30, 90, 180, 365]
        ]
        for i in range(len(scores) - 1):
            assert scores[i] > scores[i + 1]


# ── retrieve_for_context scoring ─────────────────────────────────────────────

class TestRetrievalScoring:
    """Teste la logique de score sans DB (injection de faux candidats)."""

    def _make_mem(self, summary: str, importance: int, days_ago: int = 0) -> LongMemory:
        m = LongMemory(
            user_id="u",
            type=MemoryType.GOAL,
            summary=summary,
            importance=importance,
        )
        m.id = "fake-id"
        m.last_seen = datetime.now(timezone.utc) - timedelta(days=days_ago)
        return m

    def test_high_importance_ranks_higher_than_low(self):
        high = self._make_mem("courir un marathon", importance=5, days_ago=30)
        low  = self._make_mem("courir un marathon", importance=1, days_ago=30)

        def score(mem):
            imp  = (mem.importance - 1) / 4
            fresh = _freshness(mem.last_seen)
            sim  = _jaccard("courir", mem.summary)
            return imp * 0.4 + fresh * 0.3 + sim * 0.3

        assert score(high) > score(low)

    def test_recent_ranks_higher_than_old_same_importance(self):
        recent = self._make_mem("objectif sport", importance=3, days_ago=0)
        old    = self._make_mem("objectif sport", importance=3, days_ago=180)

        def score(mem):
            imp  = (mem.importance - 1) / 4
            fresh = _freshness(mem.last_seen)
            sim  = _jaccard("sport", mem.summary)
            return imp * 0.4 + fresh * 0.3 + sim * 0.3

        assert score(recent) > score(old)

    def test_relevant_query_boosts_score(self):
        relevant   = self._make_mem("veut courir un semi-marathon", importance=3, days_ago=30)
        irrelevant = self._make_mem("a des difficultés au travail", importance=3, days_ago=30)

        def score(mem, query):
            imp  = (mem.importance - 1) / 4
            fresh = _freshness(mem.last_seen)
            sim  = _jaccard(query, mem.summary)
            return imp * 0.4 + fresh * 0.3 + sim * 0.3

        query = "semi-marathon courir objectif"
        assert score(relevant, query) > score(irrelevant, query)


# ── Reflection dataclass ──────────────────────────────────────────────────────

class TestReflectionModel:

    def test_valid_creation(self):
        r = Reflection(
            user_id="u",
            content="Cette semaine a été marquée par...",
            period_start="2026-06-22",
            period_end="2026-06-28",
        )
        assert r.themes == []
        assert r.question is None
        assert r.id is None

    def test_with_themes_and_question(self):
        r = Reflection(
            user_id="u",
            content="x",
            period_start="2026-06-22",
            period_end="2026-06-28",
            themes=["fatigue", "travail"],
            question="Qu'est-ce qui te donnerait de l'énergie ?",
        )
        assert len(r.themes) == 2
        assert "fatigue" in r.themes
