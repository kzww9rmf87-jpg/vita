"""
Tests — DiscoveryEngine (Sprint 12.3).

Couvre :
  - start() : message d'ouverture sport
  - message() : phase discovering, reformulating, proposing
  - react() : acceptation, refus partiel, clôture
  - Fallbacks locaux si Claude indisponible
  - Sécurité : ne reformule pas avant MIN_USER_EXCHANGES
"""
import pytest
from unittest.mock import patch, MagicMock

from discovery.engine import DiscoveryEngine, _MIN_USER_EXCHANGES
from discovery.models import (
    ActivityProposal,
    DiscoveryExchange,
    DiscoveryMessageInput,
    DiscoveryMessageOutput,
    DiscoveryReactInput,
    DiscoveryReactOutput,
    DiscoveryStartInput,
    DiscoverySynthesis,
)


def make_exchanges(count: int, force_reformulate: bool = False) -> list[DiscoveryExchange]:
    """Génère un historique d'échanges fictifs (alternés vita/user)."""
    exchanges = []
    for i in range(count):
        exchanges.append(DiscoveryExchange(role="vita",  content=f"Question VITA {i+1}"))
        exchanges.append(DiscoveryExchange(role="user",  content=f"Réponse utilisateur {i+1}"))
    return exchanges


class TestDiscoveryEngineStart:

    def test_start_returns_opening_message(self):
        engine = DiscoveryEngine()
        result = engine.start(DiscoveryStartInput(user_id="u1", domain="sport"))
        assert result.vita_opening
        assert len(result.vita_opening) > 20
        assert result.already_started is False

    def test_start_sport_opening_is_non_judgmental(self):
        engine = DiscoveryEngine()
        result = engine.start(DiscoveryStartInput(user_id="u1", domain="sport"))
        opening_lower = result.vita_opening.lower()
        # Ne doit pas commencer par du jugement ou de l'injonction
        assert "tu dois" not in opening_lower
        assert "il faut" not in opening_lower
        assert "poids" not in opening_lower
        assert "calories" not in opening_lower

    def test_start_unknown_domain_raises(self):
        engine = DiscoveryEngine()
        with pytest.raises(ValueError, match="inconnu"):
            engine.start(DiscoveryStartInput(user_id="u1", domain="crypto"))


class TestDiscoveryEngineMessage:

    def _make_input(self, exchanges: list[DiscoveryExchange], status: str = "discovering") -> DiscoveryMessageInput:
        return DiscoveryMessageInput(
            user_id="u1",
            domain="sport",
            exchanges=exchanges,
            user_message="Je suis sédentaire depuis deux ans.",
            status=status,
        )

    def test_discovering_fallback_when_claude_unavailable(self):
        engine = DiscoveryEngine()
        with patch.object(engine, "_continue_discovery", side_effect=Exception("Claude down")):
            inp = self._make_input(make_exchanges(2))
            result = engine.message(inp)
        assert result.vita_response
        assert result.new_status in ("discovering", "reformulating")

    def test_cannot_reformulate_before_min_exchanges(self):
        """Claude veut reformuler trop tôt — le moteur doit bloquer."""
        engine = DiscoveryEngine()

        # Simule Claude qui demande la reformulation trop tôt (2 échanges seulement)
        claude_mock = MagicMock()
        claude_mock.content = [MagicMock(text='{"vita_response": "Je crois avoir compris.", "new_status": "reformulating", "ready_to_reformulate": true}')]

        with patch("discovery.engine._CLIENT") as mock_client:
            mock_client.messages.create.return_value = claude_mock
            inp = self._make_input(make_exchanges(2))  # seulement 2 échanges utilisateur
            result = engine._continue_discovery(inp, 2)

        # Doit rester en discovering malgré la demande de Claude
        assert result.new_status == "discovering"

    def test_can_reformulate_after_min_exchanges(self):
        """Avec assez d'échanges, Claude peut déclencher la reformulation."""
        engine = DiscoveryEngine()

        claude_mock = MagicMock()
        claude_mock.content = [MagicMock(text='{"vita_response": "Je crois avoir compris.", "new_status": "reformulating", "ready_to_reformulate": true}')]

        with patch("discovery.engine._CLIENT") as mock_client:
            mock_client.messages.create.return_value = claude_mock
            inp = self._make_input(make_exchanges(_MIN_USER_EXCHANGES))
            result = engine._continue_discovery(inp, _MIN_USER_EXCHANGES)

        assert result.new_status == "reformulating"

    def test_reformulation_fallback_returns_synthesis(self):
        """Fallback en reformulation doit toujours retourner une synthesis."""
        engine = DiscoveryEngine()
        with patch.object(engine, "_generate_reformulation", side_effect=Exception("Claude down")):
            inp = self._make_input(make_exchanges(5), status="reformulating")
            result = engine.message(inp)
        assert result.vita_response
        assert result.new_status in ("reformulating", "discovering")

    def test_malformed_json_discovery_falls_back_gracefully(self):
        """Si Claude retourne du texte non-JSON en phase discovering → fallback gracieux."""
        engine = DiscoveryEngine()

        claude_mock = MagicMock()
        claude_mock.content = [MagicMock(text="Bonjour, tu m'as dit que tu aimais nager. C'est intéressant ?")]

        with patch("discovery.engine._CLIENT") as mock_client:
            mock_client.messages.create.return_value = claude_mock
            inp = self._make_input(make_exchanges(2))
            result = engine._continue_discovery(inp, 2)

        # Récupère quand même quelque chose
        assert result.vita_response
        assert result.new_status == "discovering"

    def test_proposals_generated_in_proposing_phase(self):
        """Phase proposing → doit retourner des proposals."""
        engine = DiscoveryEngine()

        proposals_json = '''
        {
          "vita_response": "Je te propose deux activités.",
          "new_status": "proposing",
          "proposals": [
            {
              "name": "Randonnée",
              "why_it_fits": "Tu aimes la nature.",
              "first_step": "Une sortie de 2h.",
              "frequency": "1 fois/semaine",
              "constraint_level": "faible"
            }
          ]
        }
        '''
        claude_mock = MagicMock()
        claude_mock.content = [MagicMock(text=proposals_json)]

        with patch("discovery.engine._CLIENT") as mock_client:
            mock_client.messages.create.return_value = claude_mock
            inp = self._make_input(make_exchanges(5), status="proposing")
            result = engine._generate_proposals(inp)

        assert len(result.proposals) == 1
        assert result.proposals[0].name == "Randonnée"
        assert result.new_status == "proposing"


class TestDiscoveryEngineReact:

    def _make_react_input(
        self,
        accepted: list[str] = None,
        refused: list[str] = None,
    ) -> DiscoveryReactInput:
        proposals = [
            ActivityProposal(
                name="Randonnée",
                why_it_fits="Tu aimes la nature.",
                first_step="Une sortie de 2h.",
                frequency="1 fois/semaine",
                constraint_level="faible",
            ),
            ActivityProposal(
                name="Yoga",
                why_it_fits="Tu cherches du calme.",
                first_step="Un cours en ligne.",
                frequency="2 fois/semaine",
                constraint_level="tres_faible",
            ),
        ]
        return DiscoveryReactInput(
            user_id="u1",
            domain="sport",
            proposals=proposals,
            accepted_names=accepted or [],
            refused_names=refused or [],
        )

    def test_react_fallback_with_accepted(self):
        """Fallback avec activités acceptées → is_complete=True."""
        engine = DiscoveryEngine()
        with patch.object(engine, "_handle_reaction", side_effect=Exception("Claude down")):
            inp = self._make_react_input(accepted=["Randonnée"])
            result = engine.react(inp)
        assert result.is_complete is True
        assert "Randonnée" in result.vita_response

    def test_react_fallback_without_accepted(self):
        """Fallback sans activités acceptées → propose Marche par défaut."""
        engine = DiscoveryEngine()
        with patch.object(engine, "_handle_reaction", side_effect=Exception("Claude down")):
            inp = self._make_react_input(refused=["Randonnée", "Yoga"])
            result = engine.react(inp)
        assert result.is_complete is False
        assert len(result.new_proposals) > 0

    def test_react_complete_when_all_accepted(self):
        """Claude retourne is_complete=True → session terminée."""
        engine = DiscoveryEngine()

        complete_json = '{"vita_response": "Super choix !", "new_status": "completed", "new_proposals": [], "is_complete": true}'
        claude_mock = MagicMock()
        claude_mock.content = [MagicMock(text=complete_json)]

        with patch("discovery.engine._CLIENT") as mock_client:
            mock_client.messages.create.return_value = claude_mock
            inp = self._make_react_input(accepted=["Randonnée", "Yoga"])
            result = engine._handle_reaction(inp)

        assert result.is_complete is True
        assert result.vita_response == "Super choix !"
        assert result.new_proposals == []

    def test_react_new_proposals_on_full_refusal(self):
        """Tout refusé → nouvelles propositions."""
        engine = DiscoveryEngine()

        new_prop_json = '''
        {
          "vita_response": "Pas de problème, essayons autre chose.",
          "new_status": "proposing",
          "new_proposals": [
            {
              "name": "Natation",
              "why_it_fits": "Plus doux pour les articulations.",
              "first_step": "Un essai à la piscine municipale.",
              "frequency": "1 fois/semaine",
              "constraint_level": "faible"
            }
          ],
          "is_complete": false
        }
        '''
        claude_mock = MagicMock()
        claude_mock.content = [MagicMock(text=new_prop_json)]

        with patch("discovery.engine._CLIENT") as mock_client:
            mock_client.messages.create.return_value = claude_mock
            inp = self._make_react_input(refused=["Randonnée", "Yoga"])
            result = engine._handle_reaction(inp)

        assert result.is_complete is False
        assert len(result.new_proposals) == 1
        assert result.new_proposals[0].name == "Natation"
