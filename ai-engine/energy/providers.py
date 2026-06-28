"""
Interfaces (protocoles) pour les providers de données d'énergie.

Un provider est une source de données : saisie manuelle, Apple Health,
Oura Ring, Garmin, etc. Les agents ne savent pas d'où viennent les données —
ils consomment uniquement les modèles de `energy.models`.

Ce module définit le contrat. Les implémentations sont dans :
  - healthkit_provider.py  (Apple Health — Sprint 8)
  - manual_provider.py     (saisie via data-service — actif dès Sprint 7)
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import date as DateType
from typing import Optional

from energy.models import (
    SleepEntry, ActivitySession, NutritionDaily, Meal,
    EnergyContext,
)


class SleepProvider(ABC):
    """
    Interface pour un provider de données de sommeil.
    Toutes les implémentations doivent retourner des objets SleepEntry.
    """

    @abstractmethod
    async def get_entry(self, user_id: str, date: DateType) -> Optional[SleepEntry]:
        """Retourne l'entrée de sommeil pour une date donnée, ou None."""
        ...

    @abstractmethod
    async def get_history(
        self, user_id: str, days: int = 30
    ) -> list[SleepEntry]:
        """Retourne l'historique de sommeil sur N jours."""
        ...


class ActivityProvider(ABC):
    """Interface pour un provider de données d'activité physique."""

    @abstractmethod
    async def get_sessions(
        self, user_id: str, days: int = 30
    ) -> list[ActivitySession]:
        """Retourne les sessions d'activité sur N jours."""
        ...

    @abstractmethod
    async def get_session(
        self, user_id: str, session_id: str
    ) -> Optional[ActivitySession]:
        """Retourne une session précise par son ID."""
        ...


class NutritionProvider(ABC):
    """Interface pour un provider de données de nutrition."""

    @abstractmethod
    async def get_daily(
        self, user_id: str, date: DateType
    ) -> Optional[NutritionDaily]:
        """Retourne les totaux nutritionnels d'une journée."""
        ...

    @abstractmethod
    async def get_history(
        self, user_id: str, days: int = 30
    ) -> list[NutritionDaily]:
        """Retourne l'historique nutritionnel sur N jours."""
        ...

    @abstractmethod
    async def get_meals(
        self, user_id: str, date: DateType
    ) -> list[Meal]:
        """Retourne les repas d'une journée."""
        ...


class EnergyDataProvider(ABC):
    """
    Provider composite — agrège sleep, activity, nutrition.
    C'est l'interface principale utilisée par les agents IA.
    """

    @property
    @abstractmethod
    def sleep(self) -> SleepProvider:
        """Sous-provider sommeil."""
        ...

    @property
    @abstractmethod
    def activity(self) -> ActivityProvider:
        """Sous-provider activité."""
        ...

    @property
    @abstractmethod
    def nutrition(self) -> NutritionProvider:
        """Sous-provider nutrition."""
        ...

    async def build_energy_context(
        self,
        user_id: str,
        reference_date: DateType,
        sleep_days: int = 7,
        activity_days: int = 7,
        nutrition_days: int = 7,
    ) -> EnergyContext:
        """
        Construit l'EnergyContext en interrogeant les trois sous-providers.
        Méthode concrète — les sous-classes n'ont pas besoin de la redéfinir.
        """
        sleep_history   = await self.sleep.get_history(user_id, sleep_days)
        activity_week   = await self.activity.get_sessions(user_id, activity_days)
        nutrition_week  = await self.nutrition.get_history(user_id, nutrition_days)
        nutrition_today = await self.nutrition.get_daily(user_id, reference_date)
        meals_today     = await self.nutrition.get_meals(user_id, reference_date)

        sleep_last = next(
            (e for e in sleep_history if e.date == reference_date), None
        )

        return EnergyContext(
            sleep_last_night=sleep_last,
            sleep_week=sleep_history,
            activity_week=activity_week,
            nutrition_today=nutrition_today,
            nutrition_week=nutrition_week,
            meals_today=meals_today,
        )
