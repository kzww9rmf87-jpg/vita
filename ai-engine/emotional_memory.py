"""
Mémoire émotionnelle — met à jour les thèmes récurrents de l'utilisateur
après chaque entrée de journal.

La mémoire émotionnelle est un résumé évolutif par thème : chaque fois qu'un
thème apparaît dans une entrée, on met à jour sa valence et son résumé.

Ce module ne fait jamais appel à l'API Anthropic — il est purement local,
rapide, et ne risque pas de bloquer la sauvegarde du journal.
"""
import logging
from typing import Optional
from db import get_pool

logger = logging.getLogger(__name__)


async def update_emotional_memories(
    user_id: str,
    themes: list[str],
    valence: float,
    entry_summary: Optional[str] = None,
) -> None:
    """
    Met à jour (ou crée) les mémoires émotionnelles pour les thèmes détectés.

    Pour chaque thème :
    - Si une mémoire existe : moyenne pondérée de la valence, +1 recurrence, update du résumé
    - Sinon : création avec les valeurs initiales

    Ne lève jamais — les erreurs sont loggées et ignorées pour ne pas bloquer
    la sauvegarde du journal.
    """
    if not themes:
        return

    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            for theme in themes:
                await _upsert_theme(conn, user_id, theme, valence, entry_summary)
    except Exception as exc:
        logger.error(
            "[EMOTIONAL_MEMORY] Failed to update memories user_id=%s: %s",
            user_id, exc
        )


async def _upsert_theme(conn, user_id: str, theme: str, valence: float, summary: Optional[str]) -> None:
    existing = await conn.fetchrow(
        "SELECT id, valence, recurrence_count FROM emotional_memories "
        "WHERE user_id = $1 AND theme = $2",
        user_id, theme
    )

    if existing:
        # Moyenne pondérée : anciennes données ont plus de poids (0.7/0.3)
        # pour éviter qu'une seule entrée renverse une tendance longue
        new_valence = existing["valence"] * 0.7 + valence * 0.3 if existing["valence"] is not None else valence
        new_count = existing["recurrence_count"] + 1

        await conn.execute(
            """UPDATE emotional_memories
               SET valence = $1,
                   recurrence_count = $2,
                   last_seen_at = NOW(),
                   summary = COALESCE($3, summary),
                   updated_at = NOW()
               WHERE user_id = $4 AND theme = $5""",
            round(new_valence, 3), new_count, summary, user_id, theme
        )
    else:
        await conn.execute(
            """INSERT INTO emotional_memories
               (user_id, theme, summary, valence, recurrence_count, last_seen_at, confidence)
               VALUES ($1, $2, $3, $4, 1, NOW(), 0.4)""",
            user_id, theme, summary, round(valence, 3)
        )


async def load_emotional_context(user_id: str, limit: int = 5) -> list[dict]:
    """
    Charge les thèmes émotionnels les plus récents pour enrichir le contexte journal.
    """
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            rows = await conn.fetch(
                """SELECT theme, summary, valence, recurrence_count
                   FROM emotional_memories
                   WHERE user_id = $1
                   ORDER BY last_seen_at DESC LIMIT $2""",
                user_id, limit
            )
            return [dict(r) for r in rows]
    except Exception as exc:
        logger.error("[EMOTIONAL_MEMORY] Failed to load context user_id=%s: %s", user_id, exc)
        return []
