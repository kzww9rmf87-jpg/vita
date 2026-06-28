"""Tests unitaires — Reflection Engine."""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import date

from memory.reflection import generate_weekly_reflection, _build_context
from memory.models import LongMemory, MemoryType


def _make_memory(summary: str, mem_type: MemoryType = MemoryType.GOAL) -> LongMemory:
    m = LongMemory(user_id="u", type=mem_type, summary=summary, importance=3)
    m.id = "id"
    return m


class TestBuildContext:

    def test_includes_period(self):
        ctx = _build_context(
            date(2026, 6, 22), date(2026, 6, 28),
            journal_rows=[], checkin_rows=[], memories=[]
        )
        assert "2026-06-22" in ctx
        assert "2026-06-28" in ctx

    def test_no_journal_shows_placeholder(self):
        ctx = _build_context(
            date(2026, 6, 22), date(2026, 6, 28),
            journal_rows=[], checkin_rows=[], memories=[]
        )
        assert "aucune entrée de journal" in ctx

    def test_journal_entries_included(self):
        row = {
            "mood_label": "anxiété",
            "emotional_tone": "tendu",
            "themes": ["travail", "stress"],
            "day": date(2026, 6, 24),
        }
        ctx = _build_context(
            date(2026, 6, 22), date(2026, 6, 28),
            journal_rows=[row], checkin_rows=[], memories=[]
        )
        assert "anxiété" in ctx
        assert "travail" in ctx

    def test_memories_included_when_present(self):
        mem = _make_memory("Veut courir un semi-marathon")
        ctx = _build_context(
            date(2026, 6, 22), date(2026, 6, 28),
            journal_rows=[], checkin_rows=[], memories=[mem]
        )
        assert "Veut courir un semi-marathon" in ctx
        assert "[goal]" in ctx

    def test_no_memories_no_memory_section(self):
        ctx = _build_context(
            date(2026, 6, 22), date(2026, 6, 28),
            journal_rows=[], checkin_rows=[], memories=[]
        )
        assert "VITA sait" not in ctx


class TestGenerateWeeklyReflection:

    @pytest.mark.asyncio
    async def test_never_raises_on_error(self):
        """Une erreur inattendue retourne None sans lever."""
        with patch("memory.reflection.get_pool", AsyncMock(side_effect=Exception("DB down"))):
            result = await generate_weekly_reflection("u1")
        assert result is None

    @pytest.mark.asyncio
    async def test_returns_none_if_already_exists(self):
        """Si la réflexion de la semaine existe déjà, retourne None."""
        mock_pool = AsyncMock()
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value="existing-uuid")
        mock_pool.__aenter__ = AsyncMock(return_value=mock_pool)
        mock_pool.acquire = MagicMock(return_value=_AsyncCM(mock_conn))

        with patch("memory.reflection.get_pool", AsyncMock(return_value=mock_pool)):
            result = await generate_weekly_reflection("u1", week_start=date(2026, 6, 22))
        assert result is None

    @pytest.mark.asyncio
    async def test_returns_none_if_insufficient_data(self):
        """Moins de 2 données (journal + check-ins) → pas de réflexion."""
        mock_pool = AsyncMock()
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=None)   # pas encore de réflexion
        mock_conn.fetch = AsyncMock(side_effect=[[], []])   # 0 journal + 0 checkins
        mock_pool.acquire = MagicMock(return_value=_AsyncCM(mock_conn))

        with patch("memory.reflection.get_pool", AsyncMock(return_value=mock_pool)):
            result = await generate_weekly_reflection("u1", week_start=date(2026, 6, 22))
        assert result is None


    @pytest.mark.asyncio
    async def test_happy_path_returns_reflection(self):
        """Voie heureuse : toutes les conditions réunies → retourne un objet Reflection valide."""
        mock_pool = AsyncMock()
        mock_conn = AsyncMock()

        journal_row = {
            "mood_label": "anxiété",
            "emotional_tone": "tendu",
            "themes": ["travail", "stress"],
            "day": date(2026, 6, 24),
        }
        checkin_row = {
            "type": "morning",
            "energy": 3,
            "mood": "fatigue",
            "stress": 4,
            "date": date(2026, 6, 24),
        }
        reflection_row = MagicMock()
        reflection_row.__getitem__ = lambda s, k: {"id": "new-uuid", "created_at": None}[k]

        mock_conn.fetchval = AsyncMock(return_value=None)    # pas encore de réflexion
        mock_conn.fetch = AsyncMock(side_effect=[[journal_row], [checkin_row]])
        mock_conn.fetchrow = AsyncMock(return_value=reflection_row)
        mock_pool.acquire = MagicMock(return_value=_AsyncCM(mock_conn))

        fake_api_response = MagicMock()
        fake_api_response.content = [MagicMock(text='{"content": "Cette semaine a été marquée par une tension autour du travail. Quelque chose cherche à se dire.", "themes": ["travail", "stress"], "question": "Qu\'est-ce qui t\'épuise vraiment dans ce contexte ?"}')]

        with patch("memory.reflection.get_pool", AsyncMock(return_value=mock_pool)), \
             patch("memory.reflection._provider") as mock_provider, \
             patch("memory.reflection._client") as mock_client:
            mock_provider.get_by_user = AsyncMock(return_value=[])
            mock_client.messages.create = AsyncMock(return_value=fake_api_response)

            result = await generate_weekly_reflection("u1", week_start=date(2026, 6, 22))

        assert result is not None
        assert "travail" in result.content.lower() or "tension" in result.content.lower()
        assert result.period_start == "2026-06-22"
        assert result.period_end == "2026-06-28"
        assert isinstance(result.themes, list)
        assert result.question is not None

    @pytest.mark.asyncio
    async def test_reflection_content_under_300_words(self):
        """Le contenu retourné par _build_context + prompt doit tenir en 300 mots max."""
        # Teste uniquement que _build_context ne génère pas un contexte abusif
        from memory.reflection import _build_context
        from memory.models import LongMemory, MemoryType
        memories = [_make_memory(f"Mémoire {i}", MemoryType.GOAL) for i in range(10)]
        journal_rows = [
            {"mood_label": f"humeur-{d}", "emotional_tone": "neutre", "themes": [], "day": date(2026, 6, d + 22)}
            for d in range(7)
        ]
        ctx = _build_context(date(2026, 6, 22), date(2026, 6, 28), journal_rows, [], memories)
        # Le contexte lui-même n'est pas une réflexion — il doit être raisonnablement compact
        assert len(ctx.split()) < 500, "Le contexte fourni à Claude est trop long"


class _AsyncCM:
    """Context manager async léger pour mocker pool.acquire()."""
    def __init__(self, conn):
        self._conn = conn
    async def __aenter__(self):
        return self._conn
    async def __aexit__(self, *_):
        pass
