"""
Interface abstraite MemoryProvider.

Permet de swapper PostgreSQL contre Pinecone, Weaviate, ou un système
hybride sans modifier les modules consommateurs (long_memory, retrieval,
consolidation). Le code applicatif ne dépend jamais directement de la
couche de stockage.

Implémentations disponibles :
  - PostgresMemoryProvider  (memory/postgres_provider.py)  — utilisée maintenant
  - [future] PineconeMemoryProvider                        — quand les crédits sont là
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from .models import LongMemory


class MemoryProvider(ABC):
    """Contrat de stockage pour les mémoires longue durée de VITA."""

    # ── Écriture ─────────────────────────────────────────────────────────────

    @abstractmethod
    async def save(self, memory: LongMemory) -> str:
        """Persiste une mémoire. Retourne l'id généré.

        Si une mémoire avec le même (user_id, summary[:200]) existe déjà,
        l'implémentation doit lever ValueError pour forcer un merge() explicite.
        """

    @abstractmethod
    async def update_importance(
        self, memory_id: str, importance: int, confidence: float
    ) -> None:
        """Met à jour importance + confidence après consolidation."""

    @abstractmethod
    async def update_summary(self, memory_id: str, summary: str) -> None:
        """Met à jour le résumé d'une mémoire après fusion partielle."""

    @abstractmethod
    async def touch(self, memory_id: str) -> None:
        """Met à jour last_seen = NOW() — appelé quand la mémoire redevient saillante."""

    @abstractmethod
    async def merge(
        self, keep_id: str, drop_id: str, merged_summary: str, importance: int
    ) -> None:
        """Fusionne drop_id dans keep_id avec un nouveau résumé. Supprime drop_id."""

    @abstractmethod
    async def delete(self, memory_id: str) -> None:
        """Supprime une mémoire (utilisée quand confidence tombe < 0.2)."""

    # ── Lecture ───────────────────────────────────────────────────────────────

    @abstractmethod
    async def get_by_user(
        self, user_id: str, limit: int = 50, min_importance: int = 1
    ) -> list[LongMemory]:
        """Retourne toutes les mémoires actives, triées importance DESC + last_seen DESC."""

    @abstractmethod
    async def get_by_type(
        self, user_id: str, memory_type: str, limit: int = 20
    ) -> list[LongMemory]:
        """Filtre par type sémantique."""

    @abstractmethod
    async def retrieve_for_context(
        self,
        user_id: str,
        query: str,
        limit: int = 15,
    ) -> list[LongMemory]:
        """
        Retrieval hybride pour injection dans le contexte AI.

        Score combiné : importance × 0.4 + fraîcheur × 0.3 + similarité × 0.3
        Retourne max `limit` mémoires, triées par score décroissant.
        """

    @abstractmethod
    async def find_similar(
        self, user_id: str, summary: str, threshold: float = 0.3
    ) -> list[LongMemory]:
        """
        Trouve les mémoires proches du résumé donné (similarité keyword).
        Utilisé par la consolidation pour détecter les doublons avant insert.
        """
