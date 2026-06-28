"""
Memory Consolidation — extrait et consolide les mémoires longue durée.

Appelé après chaque interaction (journal, chat, check-in).

Flux :
  1. Claude extrait les mémoires candidates du texte (JSON structuré)
  2. Pour chaque candidat :
     a. find_similar() — cherche les doublons existants
     b. Doublon exact (Jaccard ≥ 0.85) → touch() + renforcement importance
     c. Doublon partiel (0.3–0.85) → merge() avec nouveau résumé Claude
     d. Pas de doublon → save()
  3. Mémoires avec confidence < 0.2 → delete()

Résilience : jamais d'exception levée vers l'appelant (fire-and-forget safe).
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import anthropic

from config import get_settings
from .models import LongMemory, MemoryType, MemorySource
from .postgres_provider import PostgresMemoryProvider

logger = logging.getLogger(__name__)
settings = get_settings()
_client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

_provider = PostgresMemoryProvider()

_EXTRACT_SYSTEM = """Tu es un extracteur de mémoires pour VITA, une IA de bien-être.

À partir d'un texte (journal, conversation ou check-in), extrait les informations
qui permettront à VITA de mieux connaître l'utilisateur sur le long terme.

Règles d'extraction :
— N'extrait que ce qui est factuel et stable (pas les humeurs éphémères).
— Une mémoire = une seule information, formulée en une phrase concise à la 3e personne.
  ex: "Travaille comme graphiste freelance depuis 3 ans"
  ex: "A une relation difficile avec son père"
  ex: "A pour objectif de courir un semi-marathon"
— N'invente rien. Si une information est ambiguë, baisse la confidence.
— importance : 1=anecdotique, 3=normal, 5=fondamental pour comprendre la personne.
— confidence : 0.0–1.0 (baisse si déduit, lève si affirmé explicitement).

Types disponibles :
  person, project, habit, fear, motivation, goal, value, health, work, family, emotion, event, other

Si rien de mémorable n'est présent, retourne un tableau vide.

Retourne UNIQUEMENT un JSON valide, sans markdown :
[
  {
    "type": "goal",
    "summary": "...",
    "importance": 3,
    "confidence": 0.9
  }
]"""


async def consolidate_from_interaction(
    user_id: str,
    text: str,
    source: MemorySource,
    source_id: Optional[str] = None,
) -> None:
    """
    Analyse `text` et consolide les mémoires longue durée pour `user_id`.
    Fonction fire-and-forget : toutes les erreurs sont loguées, jamais relancées.
    """
    try:
        candidates = await _extract_candidates(text)
        if not candidates:
            return

        for candidate in candidates:
            await _consolidate_one(user_id, candidate, source, source_id)

    except Exception:
        logger.exception("consolidate_from_interaction failed for user %s", user_id)


async def _extract_candidates(text: str) -> list[dict]:
    """Appelle Claude pour extraire les mémoires candidates."""
    try:
        response = await _client.messages.create(
            model=settings.model_fast,
            max_tokens=800,
            system=_EXTRACT_SYSTEM,
            messages=[{"role": "user", "content": text[:4000]}],
        )
        raw = response.content[0].text.strip()
        return json.loads(raw)
    except (json.JSONDecodeError, IndexError):
        logger.warning("Memory extraction: invalid JSON from Claude")
        return []
    except Exception:
        logger.exception("Memory extraction failed")
        return []


async def _consolidate_one(
    user_id: str,
    candidate: dict,
    source: MemorySource,
    source_id: Optional[str],
) -> None:
    """Consolide une mémoire candidate dans la DB."""
    try:
        memory_type = MemoryType(candidate.get("type", "other"))
    except ValueError:
        memory_type = MemoryType.OTHER

    summary    = str(candidate.get("summary", "")).strip()
    importance = int(candidate.get("importance", 3))
    confidence = float(candidate.get("confidence", 0.8))

    if not summary:
        return

    importance = max(1, min(5, importance))
    confidence = max(0.0, min(1.0, confidence))

    # Cherche les doublons
    similars = await _provider.find_similar(user_id, summary, threshold=0.3)

    if not similars:
        # Nouvelle mémoire
        new_mem = LongMemory(
            user_id=user_id,
            type=memory_type,
            summary=summary,
            importance=importance,
            confidence=confidence,
            source=source,
            source_id=source_id,
        )
        try:
            await _provider.save(new_mem)
        except ValueError:
            # Doublon unique index — cas de concurrence
            logger.debug("Duplicate memory skipped (unique constraint) for user %s", user_id)
        return

    # Doublon le plus proche
    best = max(similars, key=lambda m: _jaccard_score(summary, m.summary))
    similarity = _jaccard_score(summary, best.summary)

    if similarity >= 0.85:
        # Doublon quasi-exact : renforcer la mémoire existante
        new_importance = min(5, best.importance + 1)
        new_confidence = min(1.0, (best.confidence + confidence) / 2 + 0.05)
        await _provider.update_importance(best.id, new_importance, new_confidence)
        await _provider.touch(best.id)
        return

    # Doublon partiel (0.3–0.85) : enrichir le résumé existant sans supprimer
    # merge() n'est pas utilisé ici car il supprime drop_id — on n'a qu'une seule entrée à modifier.
    merged = await _merge_summaries(best.summary, summary)
    merged_importance = max(best.importance, importance)
    merged_confidence = max(best.confidence, confidence)
    await _provider.update_summary(best.id, merged)
    await _provider.update_importance(best.id, merged_importance, merged_confidence)
    await _provider.touch(best.id)


async def _merge_summaries(existing: str, new: str) -> str:
    """Demande à Claude de fusionner deux résumés similaires."""
    try:
        response = await _client.messages.create(
            model=settings.model_fast,
            max_tokens=100,
            messages=[{
                "role": "user",
                "content": (
                    f"Fusionne ces deux descriptions du même fait en une seule phrase concise "
                    f"à la 3e personne, sans perdre d'information importante :\n"
                    f"1. {existing}\n"
                    f"2. {new}\n\n"
                    f"Réponds uniquement avec la phrase fusionnée, sans guillemets."
                ),
            }],
        )
        return response.content[0].text.strip() or existing
    except Exception:
        return existing


def _jaccard_score(a: str, b: str) -> float:
    import re
    def tokens(t: str) -> set[str]:
        return set(re.sub(r"[^\w\s]", "", t.lower()).split())
    ta, tb = tokens(a), tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)
