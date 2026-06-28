"""
HealthKit Provider — abstraction Apple Health.

Ce module définit le contrat pour l'intégration Apple Health.
L'implémentation réelle sera réalisée en Sprint 8.

Architecture :
  HealthKitProvider  implémente EnergyDataProvider
  HealthKitSleepProvider  implémente SleepProvider
  HealthKitActivityProvider  implémente ActivityProvider
  HealthKitNutritionProvider  implémente NutritionProvider

Les données HealthKit arrivent via un webhook iOS → data-service → DB.
Ce provider les lit depuis la DB avec source='apple_health'.
"""
from __future__ import annotations

from datetime import date as DateType
from typing import Optional

from energy.models import (
    SleepEntry, ActivitySession, NutritionDaily, Meal,
)
from energy.providers import (
    SleepProvider, ActivityProvider, NutritionProvider, EnergyDataProvider,
)


# ── Permissions HealthKit requises ────────────────────────────────────────────
# Ces constantes documentent ce que Sprint 8 devra demander à iOS.

HEALTHKIT_READ_PERMISSIONS: tuple[str, ...] = (
    "HKQuantityTypeIdentifierHeartRate",
    "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
    "HKQuantityTypeIdentifierRestingHeartRate",
    "HKQuantityTypeIdentifierActiveEnergyBurned",
    "HKQuantityTypeIdentifierBasalEnergyBurned",
    "HKQuantityTypeIdentifierStepCount",
    "HKQuantityTypeIdentifierDistanceWalkingRunning",
    "HKQuantityTypeIdentifierDistanceCycling",
    "HKCategoryTypeIdentifierSleepAnalysis",
    "HKQuantityTypeIdentifierDietaryEnergyConsumed",
    "HKQuantityTypeIdentifierDietaryProtein",
    "HKQuantityTypeIdentifierDietaryCarbohydrates",
    "HKQuantityTypeIdentifierDietaryFatTotal",
    "HKQuantityTypeIdentifierDietaryFiber",
    "HKQuantityTypeIdentifierDietaryWater",
    "HKWorkoutTypeIdentifier",
)

HEALTHKIT_WRITE_PERMISSIONS: tuple[str, ...] = ()  # VITA ne modifie jamais HealthKit


# ── Stubs (Sprint 8 les implémentera) ─────────────────────────────────────────

class HealthKitSleepProvider(SleepProvider):
    """
    Provider sommeil Apple Health.
    Sprint 7 : stub — lève NotImplementedError.
    Sprint 8 : lit les entrées HKCategoryTypeIdentifierSleepAnalysis depuis la DB.
    """

    async def get_entry(self, user_id: str, date: DateType) -> Optional[SleepEntry]:
        raise NotImplementedError("HealthKit sleep provider disponible en Sprint 8")

    async def get_history(self, user_id: str, days: int = 30) -> list[SleepEntry]:
        raise NotImplementedError("HealthKit sleep provider disponible en Sprint 8")


class HealthKitActivityProvider(ActivityProvider):
    """
    Provider activité Apple Health.
    Sprint 7 : stub — lève NotImplementedError.
    Sprint 8 : lit HKWorkoutTypeIdentifier et steps depuis la DB.
    """

    async def get_sessions(self, user_id: str, days: int = 30) -> list[ActivitySession]:
        raise NotImplementedError("HealthKit activity provider disponible en Sprint 8")

    async def get_session(self, user_id: str, session_id: str) -> Optional[ActivitySession]:
        raise NotImplementedError("HealthKit activity provider disponible en Sprint 8")


class HealthKitNutritionProvider(NutritionProvider):
    """
    Provider nutrition Apple Health.
    Sprint 7 : stub — lève NotImplementedError.
    Sprint 8 : lit les macros depuis HKQuantityType.
    """

    async def get_daily(self, user_id: str, date: DateType) -> Optional[NutritionDaily]:
        raise NotImplementedError("HealthKit nutrition provider disponible en Sprint 8")

    async def get_history(self, user_id: str, days: int = 30) -> list[NutritionDaily]:
        raise NotImplementedError("HealthKit nutrition provider disponible en Sprint 8")

    async def get_meals(self, user_id: str, date: DateType) -> list[Meal]:
        raise NotImplementedError("HealthKit nutrition provider disponible en Sprint 8")


class HealthKitProvider(EnergyDataProvider):
    """
    Provider composite Apple Health.

    Sprint 7 : stubs uniquement.
    Sprint 8 : connecte HealthKit via le webhook iOS.

    Usage prévu (Sprint 8) :
        provider = HealthKitProvider()
        context = await provider.build_energy_context(user_id, today)
    """

    def __init__(self) -> None:
        self._sleep      = HealthKitSleepProvider()
        self._activity   = HealthKitActivityProvider()
        self._nutrition  = HealthKitNutritionProvider()

    @property
    def sleep(self) -> HealthKitSleepProvider:
        return self._sleep

    @property
    def activity(self) -> HealthKitActivityProvider:
        return self._activity

    @property
    def nutrition(self) -> HealthKitNutritionProvider:
        return self._nutrition

    @classmethod
    def is_available(cls) -> bool:
        """Retourne False jusqu'à Sprint 8."""
        return False
