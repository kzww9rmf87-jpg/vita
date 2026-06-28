"""
Life Story — détection automatique d'événements de vie majeurs.

Un événement de vie est différent d'une mémoire longue durée :
  - Mémoire : ce que la personne EST (valeur, peur, objectif, habitude)
  - Événement : ce qui lui EST ARRIVÉ (deuil, nouveau travail, naissance, voyage)

Les événements sont stockés dans vita_long_memories avec type='event'.

Déduplication : find_similar() est appelé avant save() pour éviter les doublons
avec ce que consolidate_from_interaction() aurait déjà créé sur le même texte.

Détectés à partir du journal, du chat, des check-ins.
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

_LIFE_EVENT_SYSTEM = """Tu détectes les événements de vie majeurs dans un texte.

Un événement de vie majeur est un fait daté, non répétable, qui change la trajectoire
d'une personne : nouveau travail, rupture, naissance, deuil, déménagement, maladie grave,
voyage marquant, objectif atteint, rechute, guérison, diplôme, mariage, divorce.

Ne détecte PAS :
— Les humeurs ou états émotionnels (c'est pour la mémoire émotionnelle)
— Les habitudes ou objectifs (c'est pour vita_long_memories type goal/habit)
— Les événements bénins ou anecdotiques

Format de réponse — JSON uniquement, sans markdown :
[
  {
    "summary": "A obtenu un poste de directeur artistique chez une agence parisienne",
    "importance": 5
  }
]

Si aucun événement majeur n'est détectable, retourne [].
"""


async def detect_life_events(
    user_id: str,
    text: str,
    source: MemorySource,
    source_id: Optional[str] = None,
) -> None:
    """
    Détecte les événements de vie majeurs dans `text` et les persiste.
    Fire-and-forget : les erreurs sont loguées, jamais relancées.
    """
    try:
        events = await _extract_events(text)
        for event in events:
            summary    = str(event.get("summary", "")).strip()
            importance = max(1, min(5, int(event.get("importance", 4))))
            if not summary:
                continue
            mem = LongMemory(
                user_id=user_id,
                type=MemoryType.EVENT,
                summary=summary,
                importance=importance,
                confidence=0.85,
                source=source,
                source_id=source_id,
            )
            # Vérifie les doublons sémantiques (consolidation peut avoir créé type=event sur le même texte)
            similars = await _provider.find_similar(user_id, summary, threshold=0.3)
            if similars:
                logger.debug("Life event skipped — similar memory exists: %s", summary[:60])
                continue
            try:
                await _provider.save(mem)
            except ValueError:
                # Doublon exact via contrainte DB unique (race condition)
                logger.debug("Life event already recorded: %s", summary[:60])
    except Exception:
        logger.exception("detect_life_events failed for user %s", user_id)


async def _extract_events(text: str) -> list[dict]:
    try:
        response = await _client.messages.create(
            model=settings.model_fast,
            max_tokens=400,
            system=_LIFE_EVENT_SYSTEM,
            messages=[{"role": "user", "content": text[:4000]}],
        )
        return json.loads(response.content[0].text.strip())
    except (json.JSONDecodeError, IndexError):
        return []
    except Exception:
        logger.exception("Life event extraction API call failed")
        return []
