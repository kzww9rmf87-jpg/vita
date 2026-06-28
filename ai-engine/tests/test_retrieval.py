"""Tests unitaires — Memory Retrieval (retrieve_context_block)."""
import pytest
from unittest.mock import AsyncMock, patch
from datetime import datetime, timezone, timedelta

from memory.models import LongMemory, MemoryType, MemorySource
from memory.retrieval import retrieve_context_block


def _make_mem(summary: str, importance: int, mem_type: MemoryType = MemoryType.GOAL) -> LongMemory:
    m = LongMemory(
        user_id="u",
        type=mem_type,
        summary=summary,
        importance=importance,
    )
    m.id = "id"
    m.last_seen = datetime.now(timezone.utc) - timedelta(days=7)
    return m


class TestRetrieveContextBlock:

    @pytest.mark.asyncio
    async def test_empty_memories_returns_empty_string(self):
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=[])
            result = await retrieve_context_block("u1", query="sport")
        assert result == ""

    @pytest.mark.asyncio
    async def test_returns_header_when_memories_exist(self):
        memories = [_make_mem("Veut courir un semi-marathon", importance=4)]
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=memories)
            result = await retrieve_context_block("u1", query="sport")
        assert "[VITA connaît cet utilisateur]" in result

    @pytest.mark.asyncio
    async def test_each_memory_appears_in_block(self):
        memories = [
            _make_mem("Veut courir un semi-marathon", importance=4),
            _make_mem("A peur de décevoir", importance=3, mem_type=MemoryType.FEAR),
        ]
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=memories)
            result = await retrieve_context_block("u1", query="")
        assert "Veut courir un semi-marathon" in result
        assert "A peur de décevoir" in result

    @pytest.mark.asyncio
    async def test_importance_stars_in_output(self):
        memories = [_make_mem("Objectif important", importance=5)]
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=memories)
            result = await retrieve_context_block("u1")
        assert "★★★★★" in result

    @pytest.mark.asyncio
    async def test_type_displayed_in_output(self):
        memories = [_make_mem("Peur d'échouer", importance=4, mem_type=MemoryType.FEAR)]
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=memories)
            result = await retrieve_context_block("u1")
        assert "fear" in result

    @pytest.mark.asyncio
    async def test_respects_limit_param(self):
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=[])
            await retrieve_context_block("u1", query="x", limit=5)
            mock.retrieve_for_context.assert_called_once_with("u1", query="x", limit=5)

    @pytest.mark.asyncio
    async def test_empty_query_allowed(self):
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=[])
            result = await retrieve_context_block("u1")
        assert result == ""

    @pytest.mark.asyncio
    async def test_max_15_memories_never_exceeded(self):
        """Le bloc injecté ne contient jamais plus de 15 mémoires, même si le provider en retourne plus."""
        # Simule un provider qui retourne 20 mémoires (ne devrait pas arriver avec limit=15, mais on teste le contrat)
        memories = [_make_mem(f"Mémoire numéro {i}", importance=3) for i in range(20)]
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=memories)
            result = await retrieve_context_block("u1", limit=15)
        # Compte les lignes commençant par "•"
        bullet_lines = [l for l in result.split("\n") if l.startswith("•")]
        assert len(bullet_lines) <= 15

    @pytest.mark.asyncio
    async def test_moment_magique_memory_appears_in_context_block(self):
        """MOMENT MAGIQUE : une mémoire précédente sur un objectif doit apparaître dans le contexte injecté."""
        marathon_memory = _make_mem(
            "Veut courir un semi-marathon d'ici octobre",
            importance=4,
            mem_type=MemoryType.GOAL,
        )
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=[marathon_memory])
            block = await retrieve_context_block("u1", query="je veux courir")

        # La mémoire doit être visible dans le bloc qui sera injecté dans le system prompt
        assert "semi-marathon" in block
        assert "goal" in block
        assert "★★★★" in block  # importance 4 → 4 étoiles

    @pytest.mark.asyncio
    async def test_context_block_contains_no_raw_journal_content(self):
        """Le bloc mémoire ne contient que des résumés IA (summary), jamais le texte brut du journal."""
        mem = _make_mem("Traversé une période difficile au travail", importance=3)
        with patch("memory.retrieval._provider") as mock:
            mock.retrieve_for_context = AsyncMock(return_value=[mem])
            block = await retrieve_context_block("u1")

        # Le bloc contient le résumé mais aucune autre donnée brute
        assert "Traversé une période difficile au travail" in block
        # Pas de clés de schéma DB
        assert "user_id" not in block
        assert "source_id" not in block
        assert "embedding" not in block
