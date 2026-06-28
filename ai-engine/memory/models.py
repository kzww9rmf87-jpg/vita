"""
Modèles de données pour le Long Term Memory Engine.

LongMemory — une mémoire IA typée, extraite d'une interaction.
MemoryType  — enum des catégories sémantiques.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional
from enum import Enum


class MemoryType(str, Enum):
    PERSON     = "person"
    PROJECT    = "project"
    HABIT      = "habit"
    FEAR       = "fear"
    MOTIVATION = "motivation"
    GOAL       = "goal"
    VALUE      = "value"
    HEALTH     = "health"
    WORK       = "work"
    FAMILY     = "family"
    EMOTION    = "emotion"
    EVENT      = "event"
    OTHER      = "other"


class MemorySource(str, Enum):
    JOURNAL  = "journal"
    CHAT     = "chat"
    CHECKIN  = "checkin"
    EXPLICIT = "explicit"


@dataclass
class LongMemory:
    """Représente une mémoire longue durée de VITA sur un utilisateur."""

    user_id:    str
    type:       MemoryType
    summary:    str
    importance: int        = 3   # 1–5
    confidence: float      = 0.8 # 0.0–1.0
    source:     MemorySource = MemorySource.CHAT
    source_id:  Optional[str] = None
    embedding:  Optional[str] = None  # JSON array sérialisé, placeholder Pinecone

    # Champs peuplés après persistance
    id:         Optional[str]      = None
    last_seen:  Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    def __post_init__(self) -> None:
        if not 1 <= self.importance <= 5:
            raise ValueError(f"importance must be 1–5, got {self.importance}")
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError(f"confidence must be 0.0–1.0, got {self.confidence}")
        if not self.summary.strip():
            raise ValueError("summary must not be empty")
        if isinstance(self.type, str):
            self.type = MemoryType(self.type)
        if isinstance(self.source, str):
            self.source = MemorySource(self.source)


@dataclass
class Reflection:
    """Réflexion hebdomadaire générée par VITA."""

    user_id:      str
    content:      str
    period_start: str   # YYYY-MM-DD
    period_end:   str   # YYYY-MM-DD
    themes:       list[str] = field(default_factory=list)
    question:     Optional[str] = None
    id:           Optional[str] = None
    created_at:   Optional[datetime] = None
