"""
DiscoveryEngine — Moteur de découverte conversationnel générique.

Stateless : la session complète (exchanges, status, synthesis, proposals)
est transmise à chaque appel par le backend.

Domaine 'sport' implémenté en premier ; extensible à nutrition, sommeil, etc.
via sport_context.py (ou futur nutrition_context.py, sleep_context.py…).
"""
from __future__ import annotations

import json
import logging
import re

import anthropic

from .models import (
    ActivityProposal,
    DiscoverySynthesis,
    DiscoveryExchange,
    DiscoveryMessageInput,
    DiscoveryMessageOutput,
    DiscoveryReactInput,
    DiscoveryReactOutput,
    DiscoveryStartInput,
    DiscoveryStartOutput,
)
from . import sport_context as sport

logger = logging.getLogger(__name__)

_CLIENT = anthropic.Anthropic()
_MODEL  = "claude-haiku-4-5-20251001"

# Nombre minimum d'échanges utilisateur avant de pouvoir reformuler
_MIN_USER_EXCHANGES = 5


def _domain_opening(domain: str) -> str:
    if domain == "sport":
        return sport.OPENING_MESSAGE
    raise ValueError(f"Domaine inconnu : {domain}")


def _discovery_system(domain: str) -> str:
    if domain == "sport":
        return sport.SPORT_DISCOVERY_SYSTEM
    raise ValueError(f"Domaine inconnu : {domain}")


def _reformulation_system(domain: str) -> str:
    if domain == "sport":
        return sport.SPORT_REFORMULATION_SYSTEM
    raise ValueError(f"Domaine inconnu : {domain}")


def _proposal_system(domain: str) -> str:
    if domain == "sport":
        return sport.SPORT_PROPOSAL_SYSTEM
    raise ValueError(f"Domaine inconnu : {domain}")


def _react_system(domain: str, accepted: list[str], refused: list[str], proposals: list[ActivityProposal]) -> str:
    if domain == "sport":
        proposals_text = ", ".join(p.name for p in proposals) if proposals else "aucune"
        template = sport.SPORT_REACT_SYSTEM
        return (
            template
            .replace("{accepted}", ", ".join(accepted) if accepted else "aucune")
            .replace("{refused}",  ", ".join(refused)  if refused  else "aucune")
            .replace("{proposals}", proposals_text)
        )
    raise ValueError(f"Domaine inconnu : {domain}")


def _build_messages(exchanges: list[DiscoveryExchange]) -> list[dict]:
    """Convertit l'historique en format messages Claude."""
    msgs = []
    for ex in exchanges:
        role = "assistant" if ex.role == "vita" else "user"
        msgs.append({"role": role, "content": ex.content})
    return msgs


def _parse_json(text: str) -> dict:
    """Extrait le JSON d'une réponse Claude, tolère du texte autour."""
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        return json.loads(match.group())
    raise ValueError(f"Aucun JSON trouvé dans : {text[:200]}")


# ── Fallbacks locaux ───────────────────────────────────────────────────────────

def _fallback_message(status: str, user_count: int) -> DiscoveryMessageOutput:
    """Réponse locale quand Claude est indisponible."""
    if status == "discovering" and user_count < _MIN_USER_EXCHANGES:
        return DiscoveryMessageOutput(
            vita_response=(
                "Je t'entends. Peux-tu me dire un peu plus — "
                "est-ce qu'il y a un type de mouvement qui t'attire, même vaguement ?"
            ),
            new_status="discovering",
        )
    # Si on a assez d'échanges, on reformule avec ce qu'on a
    return DiscoveryMessageOutput(
        vita_response=(
            "Merci pour ce que tu as partagé. "
            "J'ai l'impression d'avoir une bonne idée de ton rapport à l'activité physique. "
            "Est-ce que j'ai bien compris ?"
        ),
        new_status="reformulating",
        synthesis=DiscoverySynthesis(
            rapport_au_sport="à préciser",
            resume_valide=(
                "Tu m'as partagé des éléments sur ton rapport à l'activité physique. "
                "Est-ce que j'ai bien compris ?"
            ),
        ),
    )


def _fallback_react(accepted: list[str]) -> DiscoveryReactOutput:
    if accepted:
        return DiscoveryReactOutput(
            vita_response=f"Super, j'ai noté que tu es intéressé par : {', '.join(accepted)}. C'est un bon point de départ.",
            is_complete=True,
        )
    return DiscoveryReactOutput(
        vita_response="Pas de problème. Prenons le temps de trouver ce qui te conviendra le mieux.",
        new_proposals=[
            ActivityProposal(
                name="Marche",
                why_it_fits="La marche est une activité accessible à tous, sans contrainte de matériel.",
                first_step="Une sortie de 20 minutes dans ton quartier, au moment qui te convient.",
                frequency="2 à 3 fois par semaine",
                constraint_level="tres_faible",
            )
        ],
        is_complete=False,
    )


# ── API principale ─────────────────────────────────────────────────────────────

class DiscoveryEngine:

    def start(self, inp: DiscoveryStartInput) -> DiscoveryStartOutput:
        """Retourne le message d'ouverture. Pas d'appel Claude nécessaire ici."""
        return DiscoveryStartOutput(
            vita_opening=_domain_opening(inp.domain),
            already_started=False,
        )

    def message(self, inp: DiscoveryMessageInput) -> DiscoveryMessageOutput:
        """
        Traite un message utilisateur et retourne la réponse VITA.

        Selon l'état courant (status) et le nombre d'échanges :
        - discovering  → continue l'entretien OU déclenche reformulation
        - reformulating → génère synthesis + texte de reformulation
        - proposing    → génère des propositions d'activités (après validation synthesis)
        """
        user_exchange_count = sum(1 for ex in inp.exchanges if ex.role == "user")

        try:
            if inp.status == "proposing":
                return self._generate_proposals(inp)
            elif inp.status == "reformulating":
                return self._generate_reformulation(inp)
            else:
                return self._continue_discovery(inp, user_exchange_count)
        except Exception as exc:
            logger.warning("Claude indisponible dans message() : %s", exc)
            return _fallback_message(inp.status, user_exchange_count)

    def react(self, inp: DiscoveryReactInput) -> DiscoveryReactOutput:
        """
        Traite la réaction de l'utilisateur aux propositions d'activités.
        Génère soit de nouvelles propositions, soit un message de clôture.
        """
        try:
            return self._handle_reaction(inp)
        except Exception as exc:
            logger.warning("Claude indisponible dans react() : %s", exc)
            return _fallback_react(inp.accepted_names)

    # ── Méthodes privées ───────────────────────────────────────────────────────

    def _continue_discovery(self, inp: DiscoveryMessageInput, user_count: int) -> DiscoveryMessageOutput:
        """Phase discovering → génère la prochaine question ou déclenche reformulation."""
        system = _discovery_system(inp.domain)

        # Historique complet : tous les échanges passés + le nouveau message utilisateur
        history = _build_messages(inp.exchanges)
        history.append({"role": "user", "content": inp.user_message})

        response = _CLIENT.messages.create(
            model=_MODEL,
            max_tokens=600,
            system=system,
            messages=history,
        )
        raw = response.content[0].text.strip()

        try:
            data = _parse_json(raw)
        except (ValueError, json.JSONDecodeError) as exc:
            logger.warning("Parse JSON discovering failed : %s — raw: %s", exc, raw[:200])
            return DiscoveryMessageOutput(vita_response=raw, new_status="discovering")

        vita_response = data.get("vita_response", raw)
        new_status    = data.get("new_status", "discovering")
        ready         = data.get("ready_to_reformulate", False)

        # Sécurité : ne pas reformuler si pas assez d'échanges
        if ready and user_count < _MIN_USER_EXCHANGES:
            new_status = "discovering"

        return DiscoveryMessageOutput(vita_response=vita_response, new_status=new_status)

    def _generate_reformulation(self, inp: DiscoveryMessageInput) -> DiscoveryMessageOutput:
        """Phase reformulating → synthèse + texte de reformulation."""
        system = _reformulation_system(inp.domain)

        # On inclut le dernier message utilisateur dans l'historique
        history = _build_messages(inp.exchanges)
        history.append({"role": "user", "content": inp.user_message})

        response = _CLIENT.messages.create(
            model=_MODEL,
            max_tokens=1200,
            system=system,
            messages=history,
        )
        raw = response.content[0].text.strip()

        try:
            data     = _parse_json(raw)
            synth    = DiscoverySynthesis(**data["synthesis"])
            vita_res = data.get("vita_response", raw)
        except (ValueError, json.JSONDecodeError, KeyError) as exc:
            logger.warning("Parse JSON reformulation failed : %s", exc)
            synth    = DiscoverySynthesis(resume_valide=raw)
            vita_res = raw

        return DiscoveryMessageOutput(
            vita_response=vita_res,
            new_status="reformulating",
            synthesis=synth,
        )

    def _generate_proposals(self, inp: DiscoveryMessageInput) -> DiscoveryMessageOutput:
        """Phase proposing → génère les propositions d'activités."""
        system = _proposal_system(inp.domain)

        history = _build_messages(inp.exchanges)
        history.append({"role": "user", "content": inp.user_message})

        response = _CLIENT.messages.create(
            model=_MODEL,
            max_tokens=1500,
            system=system,
            messages=history,
        )
        raw = response.content[0].text.strip()

        try:
            data      = _parse_json(raw)
            proposals = [ActivityProposal(**p) for p in data.get("proposals", [])]
            vita_res  = data.get("vita_response", raw)
        except (ValueError, json.JSONDecodeError, KeyError) as exc:
            logger.warning("Parse JSON proposals failed : %s", exc)
            proposals = []
            vita_res  = raw

        return DiscoveryMessageOutput(
            vita_response=vita_res,
            new_status="proposing",
            proposals=proposals,
        )

    def _handle_reaction(self, inp: DiscoveryReactInput) -> DiscoveryReactOutput:
        """Traite accept/refus des propositions et génère la suite."""
        system = _react_system(
            inp.domain,
            inp.accepted_names,
            inp.refused_names,
            inp.proposals,
        )

        # Contexte minimal : synthesis si disponible
        context_parts = []
        if inp.synthesis and inp.synthesis.resume_valide:
            context_parts.append(f"Synthèse de l'entretien : {inp.synthesis.resume_valide}")

        if inp.accepted_names:
            context_parts.append(f"L'utilisateur accepte : {', '.join(inp.accepted_names)}")
        if inp.refused_names:
            context_parts.append(f"L'utilisateur refuse : {', '.join(inp.refused_names)}")

        user_turn = "\n".join(context_parts) or "L'utilisateur réagit aux propositions."

        response = _CLIENT.messages.create(
            model=_MODEL,
            max_tokens=900,
            system=system,
            messages=[{"role": "user", "content": user_turn}],
        )
        raw = response.content[0].text.strip()

        try:
            data         = _parse_json(raw)
            vita_res     = data.get("vita_response", raw)
            new_status   = data.get("new_status", "proposing")
            is_complete  = data.get("is_complete", False) or new_status == "completed"
            new_proposals = [ActivityProposal(**p) for p in data.get("new_proposals", [])]
        except (ValueError, json.JSONDecodeError, KeyError) as exc:
            logger.warning("Parse JSON react failed : %s", exc)
            vita_res      = raw
            is_complete   = bool(inp.accepted_names)
            new_proposals = []

        return DiscoveryReactOutput(
            vita_response=vita_res,
            new_proposals=new_proposals,
            is_complete=is_complete,
        )
