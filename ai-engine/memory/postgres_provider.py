"""
Implémentation PostgreSQL de MemoryProvider.

Retrieval hybride sans vecteurs :
  - Importance  (1–5)   → poids 0.4
  - Fraîcheur            → poids 0.3  (décroissance exponentielle, τ = 90 jours)
  - Similarité keyword   → poids 0.3  (Jaccard sur tokens normalisés)

Quand Pinecone sera connecté, la similarité keyword sera remplacée par
une similarité cosinus sur embeddings — sans changer l'interface.
"""
from __future__ import annotations

import math
import re
from datetime import datetime, timezone
from typing import Optional

import asyncpg

from db import get_pool
from .models import LongMemory, MemoryType, MemorySource
from .provider import MemoryProvider


def _jaccard(a: str, b: str) -> float:
    """Similarité de Jaccard sur mots normalisés (minuscule, sans ponctuation)."""
    def tokens(text: str) -> set[str]:
        return set(re.sub(r"[^\w\s]", "", text.lower()).split())
    ta, tb = tokens(a), tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def _freshness(last_seen: Optional[datetime], tau_days: float = 90.0) -> float:
    """Score de fraîcheur exponentiel entre 0 et 1 (1 = vu aujourd'hui)."""
    if last_seen is None:
        return 0.5
    now = datetime.now(timezone.utc)
    if last_seen.tzinfo is None:
        last_seen = last_seen.replace(tzinfo=timezone.utc)
    days = (now - last_seen).total_seconds() / 86400
    return math.exp(-days / tau_days)


def _row_to_memory(row: dict) -> LongMemory:
    m = LongMemory(
        user_id=str(row["user_id"]),
        type=MemoryType(row["type"]),
        summary=row["summary"],
        importance=int(row["importance"]),
        confidence=float(row["confidence"]),
        source=MemorySource(row["source"]),
        source_id=str(row["source_id"]) if row.get("source_id") else None,
        embedding=row.get("embedding"),
    )
    m.id = str(row["id"])
    m.last_seen = row.get("last_seen")
    m.created_at = row.get("created_at")
    m.updated_at = row.get("updated_at")
    return m


class PostgresMemoryProvider(MemoryProvider):

    async def save(self, memory: LongMemory) -> str:
        pool = await get_pool()
        async with pool.acquire() as conn:
            try:
                row = await conn.fetchrow(
                    """
                    INSERT INTO vita_long_memories
                        (user_id, type, summary, importance, confidence, source, source_id, embedding)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    RETURNING id
                    """,
                    memory.user_id,
                    memory.type.value,
                    memory.summary,
                    memory.importance,
                    memory.confidence,
                    memory.source.value,
                    memory.source_id,
                    memory.embedding,
                )
            except asyncpg.UniqueViolationError as exc:
                raise ValueError(
                    f"Memory already exists for user {memory.user_id}: {memory.summary[:80]}"
                ) from exc
        return str(row["id"])

    async def update_summary(self, memory_id: str, summary: str) -> None:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                "UPDATE vita_long_memories SET summary = $1, updated_at = NOW() WHERE id = $2",
                summary, memory_id,
            )

    async def update_importance(
        self, memory_id: str, importance: int, confidence: float
    ) -> None:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE vita_long_memories
                SET importance = $1, confidence = $2, updated_at = NOW()
                WHERE id = $3
                """,
                importance, confidence, memory_id,
            )

    async def touch(self, memory_id: str) -> None:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                "UPDATE vita_long_memories SET last_seen = NOW(), updated_at = NOW() WHERE id = $1",
                memory_id,
            )

    async def merge(
        self, keep_id: str, drop_id: str, merged_summary: str, importance: int
    ) -> None:
        if keep_id == drop_id:
            raise ValueError(f"merge() called with keep_id == drop_id ({keep_id}): would delete the memory to keep")
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute(
                    """
                    UPDATE vita_long_memories
                    SET summary = $1, importance = $2, last_seen = NOW(), updated_at = NOW()
                    WHERE id = $3
                    """,
                    merged_summary, importance, keep_id,
                )
                await conn.execute(
                    "DELETE FROM vita_long_memories WHERE id = $1", drop_id
                )

    async def delete(self, memory_id: str) -> None:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                "DELETE FROM vita_long_memories WHERE id = $1", memory_id
            )

    async def get_by_user(
        self, user_id: str, limit: int = 50, min_importance: int = 1
    ) -> list[LongMemory]:
        pool = await get_pool()
        async with pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT id, user_id, type, summary, importance, confidence,
                       source, source_id, embedding, last_seen, created_at, updated_at
                FROM vita_long_memories
                WHERE user_id = $1 AND importance >= $2
                ORDER BY importance DESC, last_seen DESC
                LIMIT $3
                """,
                user_id, min_importance, limit,
            )
        return [_row_to_memory(dict(r)) for r in rows]

    async def get_by_type(
        self, user_id: str, memory_type: str, limit: int = 20
    ) -> list[LongMemory]:
        pool = await get_pool()
        async with pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT id, user_id, type, summary, importance, confidence,
                       source, source_id, embedding, last_seen, created_at, updated_at
                FROM vita_long_memories
                WHERE user_id = $1 AND type = $2
                ORDER BY importance DESC, last_seen DESC
                LIMIT $3
                """,
                user_id, memory_type, limit,
            )
        return [_row_to_memory(dict(r)) for r in rows]

    async def retrieve_for_context(
        self,
        user_id: str,
        query: str,
        limit: int = 15,
    ) -> list[LongMemory]:
        # Charge les candidats (importance ≥ 2, max 80 pour éviter N+1)
        candidates = await self.get_by_user(user_id, limit=80, min_importance=2)

        scored: list[tuple[float, LongMemory]] = []
        for mem in candidates:
            imp_score  = (mem.importance - 1) / 4          # 0.0 – 1.0
            fresh      = _freshness(mem.last_seen)
            sim        = _jaccard(query, mem.summary)
            score      = imp_score * 0.4 + fresh * 0.3 + sim * 0.3
            scored.append((score, mem))

        scored.sort(key=lambda t: t[0], reverse=True)
        return [m for _, m in scored[:limit]]

    async def find_similar(
        self, user_id: str, summary: str, threshold: float = 0.3
    ) -> list[LongMemory]:
        candidates = await self.get_by_user(user_id, limit=200)
        return [
            m for m in candidates
            if _jaccard(summary, m.summary) >= threshold
        ]
