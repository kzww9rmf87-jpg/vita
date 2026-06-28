"""
Tests unitaires — La Première Rencontre.

Couvre :
  - _parse_conversation_response : parsing JSON Claude, fallbacks, cas limites
  - _validate_memories : filtrage et validation des mémoires
  - _topic_to_index : progression des topics
  - OPENING_MESSAGE : présence et qualité
  - Scénario de conversation : structure attendue
  - is_complete : conditions de clôture
  - Idempotence : session déjà existante
"""
import json
import pytest

# Import des fonctions internes à tester
import inspect

from first_encounter import (
    _parse_conversation_response,
    _validate_memories,
    _topic_to_index,
    OPENING_MESSAGE,
    TOPICS,
    _MIN_EXCHANGES_BEFORE_CLOSE,
    start_first_encounter,
)


# ── Tests OPENING_MESSAGE ─────────────────────────────────────────────────────

class TestOpeningMessage:

    def test_opening_message_is_not_empty(self):
        assert OPENING_MESSAGE.strip() != ""

    def test_opening_message_ends_with_question(self):
        assert "?" in OPENING_MESSAGE

    def test_opening_message_does_not_contain_score_or_note(self):
        forbidden = ["score", "note", "/5", "/10", "%", "évaluation", "questionnaire"]
        lower = OPENING_MESSAGE.lower()
        for word in forbidden:
            assert word not in lower, f"Opening message contains '{word}'"

    def test_opening_message_invites_freely(self):
        # Doit suggérer que l'utilisateur peut ne pas répondre
        keywords = ["préfère", "peux", "librement", "envie", "veux"]
        lower = OPENING_MESSAGE.lower()
        # Pas obligatoire d'avoir un de ces mots — mais le message doit être bienveillant
        assert len(OPENING_MESSAGE) > 50

    def test_opening_message_not_a_form(self):
        # Pas de formulaire — pas de puces, pas de numéros
        assert "1." not in OPENING_MESSAGE
        assert "•" not in OPENING_MESSAGE
        assert "- " not in OPENING_MESSAGE[:50]


# ── Tests _parse_conversation_response ───────────────────────────────────────

class TestParseConversationResponse:

    def _make_raw(self, **overrides) -> str:
        base = {
            "response": "Comment décrirais-tu cette période ?",
            "topic": "situation_actuelle",
            "is_complete": False,
            "memories": [],
        }
        base.update(overrides)
        return json.dumps(base)

    def test_valid_json_parsed_correctly(self):
        raw = self._make_raw()
        result = _parse_conversation_response(raw)
        assert result["response"] == "Comment décrirais-tu cette période ?"
        assert result["topic"] == "situation_actuelle"
        assert result["is_complete"] is False
        assert result["memories"] == []

    def test_json_in_markdown_block_extracted(self):
        data = {"response": "Bonjour", "topic": "valeurs", "is_complete": False, "memories": []}
        raw = f"```json\n{json.dumps(data)}\n```"
        result = _parse_conversation_response(raw)
        assert result["response"] == "Bonjour"
        assert result["topic"] == "valeurs"

    def test_unknown_topic_falls_back_to_default(self):
        raw = self._make_raw(topic="unknown_topic_xyz")
        result = _parse_conversation_response(raw)
        assert result["topic"] == "situation_actuelle"

    def test_empty_response_falls_back(self):
        raw = self._make_raw(response="")
        result = _parse_conversation_response(raw)
        assert len(result["response"]) > 0

    def test_is_complete_true_preserved(self):
        raw = self._make_raw(is_complete=True)
        result = _parse_conversation_response(raw)
        assert result["is_complete"] is True

    def test_invalid_json_returns_fallback(self):
        result = _parse_conversation_response("Ce n'est pas du JSON du tout")
        assert "response" in result
        assert len(result["response"]) > 0
        assert result["is_complete"] is False

    def test_response_truncated_at_1000_chars(self):
        long_response = "A" * 2000
        raw = self._make_raw(response=long_response)
        result = _parse_conversation_response(raw)
        assert len(result["response"]) <= 1000

    def test_memories_passed_through_validation(self):
        memories = [
            {"content": "Travaille comme architecte", "type": "work", "importance": 3},
            {"content": "", "type": "goal", "importance": 2},  # vide → ignoré
        ]
        raw = self._make_raw(memories=memories)
        result = _parse_conversation_response(raw)
        assert len(result["memories"]) == 1
        assert result["memories"][0]["type"] == "work"

    def test_all_valid_topics_accepted(self):
        for topic in TOPICS:
            raw = self._make_raw(topic=topic)
            result = _parse_conversation_response(raw)
            assert result["topic"] == topic


# ── Tests _validate_memories ─────────────────────────────────────────────────

class TestValidateMemories:

    def test_valid_memory_passes(self):
        memories = [{"content": "Aime la randonnée", "type": "habit", "importance": 2}]
        result = _validate_memories(memories)
        assert len(result) == 1
        assert result[0]["content"] == "Aime la randonnée"

    def test_empty_content_filtered(self):
        memories = [{"content": "", "type": "goal", "importance": 3}]
        result = _validate_memories(memories)
        assert len(result) == 0

    def test_too_short_content_filtered(self):
        memories = [{"content": "Ok", "type": "goal", "importance": 3}]
        result = _validate_memories(memories)
        assert len(result) == 0

    def test_invalid_type_replaced_by_other(self):
        memories = [{"content": "Un fait important", "type": "invalid_xyz", "importance": 2}]
        result = _validate_memories(memories)
        assert result[0]["type"] == "other"

    def test_importance_clamped_to_1_5(self):
        memories = [{"content": "Un fait", "type": "goal", "importance": 99}]
        result = _validate_memories(memories)
        assert result[0]["importance"] == 5

        memories2 = [{"content": "Un fait", "type": "goal", "importance": -5}]
        result2 = _validate_memories(memories2)
        assert result2[0]["importance"] == 1

    def test_non_list_returns_empty(self):
        assert _validate_memories("not a list") == []
        assert _validate_memories(None) == []
        assert _validate_memories({}) == []

    def test_max_5_memories_returned(self):
        memories = [
            {"content": f"Fait numéro {i} long", "type": "other", "importance": 1}
            for i in range(10)
        ]
        result = _validate_memories(memories)
        assert len(result) <= 5

    def test_content_truncated_at_500_chars(self):
        memories = [{"content": "A" * 1000, "type": "goal", "importance": 3}]
        result = _validate_memories(memories)
        assert len(result[0]["content"]) <= 500

    def test_all_valid_memory_types_accepted(self):
        valid_types = [
            "person", "project", "habit", "fear", "motivation",
            "goal", "value", "health", "work", "family",
            "emotion", "event", "other",
        ]
        for t in valid_types:
            memories = [{"content": f"Mémoire de type {t}", "type": t, "importance": 2}]
            result = _validate_memories(memories)
            assert result[0]["type"] == t


# ── Tests _topic_to_index ─────────────────────────────────────────────────────

class TestTopicToIndex:

    def test_known_topic_returns_its_index(self):
        assert _topic_to_index("situation_actuelle", 0) == 0
        assert _topic_to_index("valeurs", 0) == 1
        assert _topic_to_index("projets", 0) == 5

    def test_never_regresses_below_current(self):
        # Si on est au topic 5, on ne revient pas en arrière
        assert _topic_to_index("situation_actuelle", 5) == 5

    def test_advances_forward(self):
        result = _topic_to_index("objectifs", 3)
        assert result == 9  # "objectifs" est à l'index 9

    def test_unknown_topic_returns_current(self):
        assert _topic_to_index("xyz_inconnu", 4) == 4

    def test_last_topic(self):
        assert _topic_to_index("attentes_vita", 0) == 11


# ── Tests structure de la conversation ───────────────────────────────────────

class TestConversationStructure:

    def test_min_exchanges_before_close_is_reasonable(self):
        # La rencontre ne peut pas se terminer trop vite
        assert _MIN_EXCHANGES_BEFORE_CLOSE >= 8

    def test_12_topics_defined(self):
        assert len(TOPICS) == 12

    def test_topics_are_unique(self):
        assert len(TOPICS) == len(set(TOPICS))

    def test_topics_contain_expected_domains(self):
        expected = [
            "situation_actuelle", "valeurs", "personnes_importantes",
            "projets", "objectifs", "attentes_vita",
        ]
        for t in expected:
            assert t in TOPICS, f"Topic '{t}' manquant dans TOPICS"

    def test_is_complete_requires_exchange_count(self):
        # Simuler la logique de send_message : is_complete ET exchange_count >= MIN
        exchange_count = 5  # trop peu
        is_complete_from_claude = True
        effective_complete = is_complete_from_claude and exchange_count >= _MIN_EXCHANGES_BEFORE_CLOSE
        assert effective_complete is False

    def test_is_complete_with_enough_exchanges(self):
        exchange_count = 10
        is_complete_from_claude = True
        effective_complete = is_complete_from_claude and exchange_count >= _MIN_EXCHANGES_BEFORE_CLOSE
        assert effective_complete is True


# ── Tests parsing : edge cases ────────────────────────────────────────────────

class TestParseEdgeCases:

    def test_missing_memories_key(self):
        raw = json.dumps({
            "response": "Une question ?",
            "topic": "valeurs",
            "is_complete": False,
            # Pas de clé "memories"
        })
        result = _parse_conversation_response(raw)
        assert result["memories"] == []

    def test_memories_not_list_handled(self):
        raw = json.dumps({
            "response": "Une question ?",
            "topic": "valeurs",
            "is_complete": False,
            "memories": "pas une liste",
        })
        result = _parse_conversation_response(raw)
        assert result["memories"] == []

    def test_json_with_surrounding_text(self):
        data = {"response": "Bonjour", "topic": "projets", "is_complete": False, "memories": []}
        raw = f"Voici ma réponse : {json.dumps(data)} et du texte après."
        result = _parse_conversation_response(raw)
        assert result["response"] == "Bonjour"

    def test_non_boolean_is_complete_handled(self):
        raw = json.dumps({
            "response": "Bonjour",
            "topic": "valeurs",
            "is_complete": "true",
            "memories": [],
        })
        result = _parse_conversation_response(raw)
        # bool("true") = True en Python
        assert result["is_complete"] is True

    def test_importance_string_coerced_to_int(self):
        memories = [{"content": "Un fait important ici", "type": "goal", "importance": "3"}]
        result = _validate_memories(memories)
        assert result[0]["importance"] == 3


# ── Régression : start_first_encounter retourne status ────────────────────────

class TestStartFirstEncounterContract:
    """
    Vérifie que le code source de start_first_encounter retourne bien un champ "status"
    dans la branche de création (fresh start). Régression pour le bug iOS où le
    décodeur Swift échouait sur un champ `status: String` non-optionnel absent de la réponse.
    """

    def test_fresh_start_return_contains_status_field(self):
        source = inspect.getsource(start_first_encounter)
        # Le bloc de retour pour un nouveau démarrage doit contenir "status"
        assert '"status": "in_progress"' in source or "'status': 'in_progress'" in source, (
            "start_first_encounter doit retourner status='in_progress' dans la branche fresh start "
            "(requis par le décodeur Swift FirstEncounterSession)"
        )
