"""
Tests unitaires — _extract_context_categories (chat.py).

Vérifie que la fonction produit des libellés lisibles à partir du bloc mémoire
longue durée, sans jamais exposer de contenu brut.
"""
from chat import _extract_context_categories


class TestExtractContextCategories:

    def test_empty_inputs_returns_empty(self):
        assert _extract_context_categories("", False) == []

    def test_only_memory_block_adds_data_category(self):
        result = _extract_context_categories("", has_memory_block=True)
        assert result == ["tes données des derniers jours"]

    def test_single_goal_type(self):
        block = (
            "[VITA connaît cet utilisateur]\n"
            "• (goal, ★★★★) Veut courir un semi-marathon d'ici octobre"
        )
        result = _extract_context_categories(block, False)
        assert "ton projet personnel" in result

    def test_multiple_distinct_types(self):
        block = (
            "[VITA connaît cet utilisateur]\n"
            "• (goal, ★★★★) Objectif marathon\n"
            "• (work, ★★) Graphiste freelance\n"
            "• (family, ★★★) Relation difficile avec son père"
        )
        result = _extract_context_categories(block, False)
        assert "ton projet personnel" in result
        assert "ta vie professionnelle" in result
        assert "ta vie familiale" in result

    def test_duplicate_type_deduplicated(self):
        block = (
            "[VITA connaît cet utilisateur]\n"
            "• (goal, ★★★★) Marathon\n"
            "• (goal, ★★★) Sommeil amélioré"
        )
        result = _extract_context_categories(block, False)
        assert result.count("ton projet personnel") == 1

    def test_order_preserved_long_memory_then_data(self):
        block = (
            "[VITA connaît cet utilisateur]\n"
            "• (work, ★★★) Graphiste\n"
            "• (family, ★★) Relation compliquée"
        )
        result = _extract_context_categories(block, has_memory_block=True)
        assert result[0] == "ta vie professionnelle"
        assert result[1] == "ta vie familiale"
        assert result[-1] == "tes données des derniers jours"

    def test_unknown_memory_type_skipped(self):
        block = (
            "[VITA connaît cet utilisateur]\n"
            "• (unknown_type, ★★) Quelque chose d'inconnu"
        )
        result = _extract_context_categories(block, False)
        assert result == []

    def test_all_known_types_have_labels(self):
        """Chaque type de MemoryType doit avoir un libellé lisible."""
        from chat import _MEMORY_TYPE_LABELS
        known_types = [
            "goal", "work", "family", "health", "habit",
            "fear", "motivation", "value", "emotion",
            "event", "person", "project", "other",
        ]
        for t in known_types:
            assert t in _MEMORY_TYPE_LABELS, f"Type '{t}' n'a pas de libellé dans _MEMORY_TYPE_LABELS"

    def test_no_long_memory_block_no_long_memory_categories(self):
        result = _extract_context_categories("", False)
        assert result == []

    def test_memory_block_flag_deduped_if_label_already_present(self):
        """'tes données des derniers jours' n'apparaît qu'une fois, même combiné."""
        block = ""
        result1 = _extract_context_categories(block, True)
        result2 = _extract_context_categories(block, True)
        assert result1.count("tes données des derniers jours") == 1
        assert result2.count("tes données des derniers jours") == 1

    def test_health_type_label(self):
        block = "[VITA connaît cet utilisateur]\n• (health, ★★★) Douleur chronique au dos"
        result = _extract_context_categories(block, False)
        assert "ta santé" in result

    def test_content_of_memory_never_in_result(self):
        """Le résultat ne doit contenir aucun mot du contenu brut de la mémoire."""
        block = (
            "[VITA connaît cet utilisateur]\n"
            "• (goal, ★★★★) Veut courir un semi-marathon d'ici octobre prochain"
        )
        result = _extract_context_categories(block, False)
        for category in result:
            assert "semi-marathon" not in category
            assert "octobre" not in category
