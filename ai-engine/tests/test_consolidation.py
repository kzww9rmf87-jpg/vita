"""
Tests unitaires — Memory Consolidation.

Teste la logique de déduplication sans appeler Claude ni la DB.
Les fonctions _extract_candidates et _consolidate_one sont testées
via des doubles (monkeypatch) pour rester rapides et déterministes.
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock

from memory.consolidation import (
    _jaccard_score,
    _merge_summaries,
    consolidate_from_interaction,
    _extract_candidates,
    _consolidate_one,
)
from memory.models import LongMemory, MemoryType, MemorySource


# ── _jaccard_score ────────────────────────────────────────────────────────────

class TestJaccardScore:

    def test_identical(self):
        assert _jaccard_score("courir un marathon", "courir un marathon") == 1.0

    def test_no_overlap(self):
        assert _jaccard_score("courir", "graphiste") == 0.0

    def test_partial(self):
        s = _jaccard_score("courir un marathon", "courir")
        assert 0 < s < 1.0

    def test_both_empty(self):
        assert _jaccard_score("", "") == 0.0

    def test_one_empty(self):
        assert _jaccard_score("courir", "") == 0.0


# ── _extract_candidates ───────────────────────────────────────────────────────

class TestExtractCandidates:

    @pytest.mark.asyncio
    async def test_valid_json_returned(self):
        fake_response = MagicMock()
        fake_response.content = [MagicMock(text='[{"type": "goal", "summary": "Veut courir", "importance": 3, "confidence": 0.9}]')]
        with patch("memory.consolidation._client") as mock_client:
            mock_client.messages.create = AsyncMock(return_value=fake_response)
            result = await _extract_candidates("Je veux courir un marathon.")
        assert len(result) == 1
        assert result[0]["type"] == "goal"
        assert result[0]["summary"] == "Veut courir"

    @pytest.mark.asyncio
    async def test_invalid_json_returns_empty(self):
        fake_response = MagicMock()
        fake_response.content = [MagicMock(text="ceci n'est pas du JSON")]
        with patch("memory.consolidation._client") as mock_client:
            mock_client.messages.create = AsyncMock(return_value=fake_response)
            result = await _extract_candidates("texte quelconque")
        assert result == []

    @pytest.mark.asyncio
    async def test_api_error_returns_empty(self):
        with patch("memory.consolidation._client") as mock_client:
            mock_client.messages.create = AsyncMock(side_effect=Exception("API down"))
            result = await _extract_candidates("texte quelconque")
        assert result == []

    @pytest.mark.asyncio
    async def test_empty_json_array(self):
        fake_response = MagicMock()
        fake_response.content = [MagicMock(text="[]")]
        with patch("memory.consolidation._client") as mock_client:
            mock_client.messages.create = AsyncMock(return_value=fake_response)
            result = await _extract_candidates("texte sans mémoire")
        assert result == []


# ── _consolidate_one ──────────────────────────────────────────────────────────

class TestConsolidateOne:

    def _make_memory(self, summary: str, importance: int = 3) -> LongMemory:
        m = LongMemory(
            user_id="u1",
            type=MemoryType.GOAL,
            summary=summary,
            importance=importance,
        )
        m.id = "existing-id"
        return m

    @pytest.mark.asyncio
    async def test_no_similar_calls_save(self):
        """Quand aucun doublon, save() est appelé."""
        candidate = {"type": "goal", "summary": "Veut courir un marathon", "importance": 3, "confidence": 0.9}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[])
            mock_provider.save = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.JOURNAL, None)
            mock_provider.save.assert_called_once()

    @pytest.mark.asyncio
    async def test_exact_duplicate_calls_touch_and_update(self):
        """Jaccard ≥ 0.85 (quasi-exact) → touch() + update_importance(), pas de save()."""
        existing = self._make_memory("Veut courir un marathon en octobre", importance=3)
        candidate = {"type": "goal", "summary": "Veut courir un marathon en octobre", "importance": 4, "confidence": 0.95}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[existing])
            mock_provider.update_importance = AsyncMock()
            mock_provider.touch = AsyncMock()
            mock_provider.save = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.JOURNAL, None)
            mock_provider.update_importance.assert_called_once()
            mock_provider.touch.assert_called_once_with("existing-id")
            mock_provider.save.assert_not_called()

    @pytest.mark.asyncio
    async def test_jaccard_0_86_is_exact_duplicate(self):
        """Jaccard légèrement supérieur à 0.85 → traitement quasi-exact (touch/reinforce, pas merge)."""
        # "courir un marathon objectif" vs "courir un marathon" → 3/4 = 0.75 (< 0.85)
        # On construit un cas garantissant Jaccard ≥ 0.85
        a = "veut courir un semi-marathon en octobre prochain"
        b = "veut courir un semi-marathon en octobre prochain aussi"
        # Jaccard = 8/(8+1) ≈ 0.89
        score = _jaccard_score(a, b)
        assert score >= 0.85, f"Test mal construit : Jaccard = {score:.2f}"

        existing = self._make_memory(a, importance=3)
        candidate = {"type": "goal", "summary": b, "importance": 3, "confidence": 0.9}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[existing])
            mock_provider.update_importance = AsyncMock()
            mock_provider.touch = AsyncMock()
            mock_provider.save = AsyncMock()
            mock_provider.update_summary = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.JOURNAL, None)
            # Quasi-exact → touch et reinforce, pas de save ni merge
            mock_provider.touch.assert_called_once()
            mock_provider.save.assert_not_called()

    @pytest.mark.asyncio
    async def test_partial_duplicate_calls_update_summary_not_merge(self):
        """Jaccard entre 0.3 et 0.85 → update_summary + update_importance + touch, JAMAIS merge()."""
        # Jaccard partiel : les deux phrases partagent suffisamment de mots pour atteindre 0.3–0.85
        # a = {courir, marathon, objectif, principal, pour, cet, été}  (7 tokens)
        # b = {courir, marathon, dici, octobre}                        (4 tokens)
        # intersection = {courir, marathon}  → 2/9 ≈ 0.22 — trop faible
        # On utilise des phrases qui partagent ~40% des tokens
        a = "Veut courir un marathon et améliorer son temps de course"
        b = "Veut courir un marathon et battre son record personnel"
        score = _jaccard_score(a, b)
        assert 0.3 <= score < 0.85, f"Test mal construit : Jaccard = {score:.2f}"

        existing = self._make_memory(a, importance=2)
        candidate = {"type": "work", "summary": b, "importance": 3, "confidence": 0.85}

        merge_response = MagicMock()
        merge_response.content = [MagicMock(text="Travaille comme graphiste freelance indépendant depuis plusieurs années")]

        with patch("memory.consolidation._provider") as mock_provider, \
             patch("memory.consolidation._client") as mock_client:
            mock_provider.find_similar = AsyncMock(return_value=[existing])
            mock_provider.update_summary = AsyncMock()
            mock_provider.update_importance = AsyncMock()
            mock_provider.touch = AsyncMock()
            mock_provider.save = AsyncMock()
            mock_provider.merge = AsyncMock()
            mock_client.messages.create = AsyncMock(return_value=merge_response)

            await _consolidate_one("u1", candidate, MemorySource.CHAT, None)

            # Le doublon partiel doit update_summary, PAS merge()
            mock_provider.update_summary.assert_called_once()
            mock_provider.update_importance.assert_called_once()
            mock_provider.touch.assert_called_once()
            mock_provider.merge.assert_not_called()
            mock_provider.save.assert_not_called()

    @pytest.mark.asyncio
    async def test_update_importance_called_with_correct_args(self):
        """Quasi-exact : importance incrémentée de 1, bornée à 5, confidence renforcée."""
        existing = self._make_memory("Veut courir", importance=4)
        existing.confidence = 0.7
        candidate = {"type": "goal", "summary": "Veut courir", "importance": 5, "confidence": 0.9}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[existing])
            mock_provider.update_importance = AsyncMock()
            mock_provider.touch = AsyncMock()
            mock_provider.save = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.JOURNAL, None)
            # importance = min(5, 4+1) = 5
            # confidence = min(1.0, (0.7+0.9)/2 + 0.05) = min(1.0, 0.85) = 0.85
            call_args = mock_provider.update_importance.call_args[0]
            assert call_args[1] == 5          # importance
            assert abs(call_args[2] - 0.85) < 0.01  # confidence

    @pytest.mark.asyncio
    async def test_empty_summary_skipped(self):
        """Candidat avec summary vide est ignoré sans erreur."""
        candidate = {"type": "goal", "summary": "", "importance": 3, "confidence": 0.9}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[])
            mock_provider.save = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.JOURNAL, None)
            mock_provider.save.assert_not_called()

    @pytest.mark.asyncio
    async def test_invalid_type_falls_back_to_other(self):
        """Type inconnu → MemoryType.OTHER sans lever d'exception."""
        candidate = {"type": "unknown_type", "summary": "Quelque chose", "importance": 2, "confidence": 0.7}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[])
            mock_provider.save = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.CHAT, None)
            mock_provider.save.assert_called_once()
            call_args = mock_provider.save.call_args[0][0]
            assert call_args.type == MemoryType.OTHER

    @pytest.mark.asyncio
    async def test_importance_clamped_to_1_5(self):
        """importance hors bornes est clampé silencieusement."""
        candidate = {"type": "goal", "summary": "Objectif", "importance": 99, "confidence": 0.9}
        with patch("memory.consolidation._provider") as mock_provider:
            mock_provider.find_similar = AsyncMock(return_value=[])
            mock_provider.save = AsyncMock()
            await _consolidate_one("u1", candidate, MemorySource.CHAT, None)
            call_args = mock_provider.save.call_args[0][0]
            assert call_args.importance == 5


# ── consolidate_from_interaction ─────────────────────────────────────────────

class TestConsolidateFromInteraction:

    @pytest.mark.asyncio
    async def test_never_raises_on_api_error(self):
        """Si Claude échoue, la fonction doit retourner None sans lever."""
        with patch("memory.consolidation._extract_candidates", AsyncMock(side_effect=Exception("boom"))):
            # Ne doit pas lever
            await consolidate_from_interaction("u1", "texte", MemorySource.JOURNAL)

    @pytest.mark.asyncio
    async def test_empty_candidates_returns_early(self):
        """Si Claude retourne [], aucune opération DB n'est tentée."""
        with patch("memory.consolidation._extract_candidates", AsyncMock(return_value=[])):
            with patch("memory.consolidation._consolidate_one") as mock_consolidate:
                await consolidate_from_interaction("u1", "texte", MemorySource.CHAT)
                mock_consolidate.assert_not_called()

    @pytest.mark.asyncio
    async def test_multiple_candidates_each_consolidated(self):
        """Chaque candidat est consolidé indépendamment."""
        candidates = [
            {"type": "goal", "summary": "Courir", "importance": 3, "confidence": 0.9},
            {"type": "fear", "summary": "Peur d'échouer", "importance": 4, "confidence": 0.8},
        ]
        with patch("memory.consolidation._extract_candidates", AsyncMock(return_value=candidates)):
            with patch("memory.consolidation._consolidate_one", AsyncMock()) as mock_c:
                await consolidate_from_interaction("u1", "texte", MemorySource.JOURNAL, "entry-id")
                assert mock_c.call_count == 2
