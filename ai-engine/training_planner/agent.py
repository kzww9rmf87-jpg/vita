"""
TrainingPlannerAgent — algorithme local + raffinement optionnel par Claude.

Architecture miroir du MealPlannerAgent :
  1. Planification locale (déterministe, toujours disponible)
  2. Si conditions remplies → Claude ajuste les notes et la rationale uniquement
  3. Fallback complet sur le local si Claude échoue
"""
from __future__ import annotations
import json
import logging
from typing import Any

import anthropic

from config import get_settings
from .models import (
    TrainingPlannerInput, TrainingWeekPlan, PlannedSession, SessionType,
)
from .planner import plan_locally, build_rationale

log = logging.getLogger(__name__)
settings = get_settings()


class TrainingPlannerAgent:

    async def plan(self, inp: TrainingPlannerInput) -> TrainingWeekPlan:
        """Point d'entrée principal — retourne toujours un résultat."""
        sessions  = plan_locally(inp)
        rationale = build_rationale(inp.sport_profile, sessions)

        if not self._should_call_claude(inp, sessions):
            return TrainingWeekPlan(sessions=sessions, rationale=rationale, used_claude=False)

        try:
            refined = await self._refine_with_claude(inp, sessions, rationale)
            return refined
        except Exception as exc:
            log.warning("Claude unavailable for training planner (%s) — using local plan", exc)
            return TrainingWeekPlan(sessions=sessions, rationale=rationale, used_claude=False)

    # ── Conditions d'appel Claude ──────────────────────────────────────────────

    def _should_call_claude(self, inp: TrainingPlannerInput, sessions: list[PlannedSession]) -> bool:
        """Claude intervient seulement quand il peut apporter une vraie valeur."""
        if not sessions:
            return False
        # Au moins 2 types de séances différents (plan varié)
        types = {s.session_type for s in sessions}
        if len(types) < 2:
            return False
        # Des contraintes spécifiques à intégrer dans les notes
        has_constraints = bool(inp.pain_areas or inp.equipment or inp.sport_profile.context)
        return has_constraints

    # ── Raffinement Claude ────────────────────────────────────────────────────

    async def _refine_with_claude(
        self,
        inp: TrainingPlannerInput,
        sessions: list[PlannedSession],
        rationale: str,
    ) -> TrainingWeekPlan:
        """
        Claude ajuste les notes et la rationale uniquement.
        Il ne modifie jamais les jours, durées ou types de séances.
        """
        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        prompt = self._build_prompt(inp, sessions, rationale)
        msg = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            messages=[{"role": "user", "content": prompt}],
        )

        raw = msg.content[0].text.strip()
        return self._parse_claude_response(raw, sessions) or TrainingWeekPlan(
            sessions=sessions, rationale=rationale, used_claude=False
        )

    def _build_prompt(
        self,
        inp: TrainingPlannerInput,
        sessions: list[PlannedSession],
        rationale: str,
    ) -> str:
        profile = inp.sport_profile
        sessions_json = json.dumps(
            [s.model_dump(mode="json") for s in sessions],
            ensure_ascii=False, indent=2,
        )
        constraints: list[str] = []
        if inp.pain_areas:
            constraints.append(f"Zones sensibles : {', '.join(inp.pain_areas)}")
        if inp.equipment:
            constraints.append(f"Équipement disponible : {', '.join(inp.equipment)}")
        if profile.context:
            constraints.append(f"Contexte : {profile.context}")

        return f"""Tu es un préparateur physique bienveillant qui travaille avec VITA.

Voici le plan d'entraînement généré automatiquement :
{sessions_json}

Niveau : {profile.fitness_level}
Contraintes utilisateur :
{chr(10).join(f'- {c}' for c in constraints) if constraints else '- Aucune'}

Rationale initiale : {rationale}

Ta mission :
1. Améliore les notes de chaque séance pour tenir compte des contraintes.
2. Réécris la rationale de manière chaleureuse et non-culpabilisante.
3. NE modifie PAS les jours, durées ou types de séances.
4. Aucun jugement sur l'utilisateur.

Réponds en JSON strict :
{{
  "sessions": [
    {{
      "day_of_week": <int>,
      "activity_name": "<str>",
      "session_type": "<str>",
      "duration_min": <int>,
      "notes": "<str ou null>",
      "sort_order": <int>
    }}
  ],
  "rationale": "<str>"
}}"""

    def _parse_claude_response(
        self, raw: str, fallback_sessions: list[PlannedSession]
    ) -> TrainingWeekPlan | None:
        try:
            # Extraire le JSON du texte
            start = raw.find("{")
            end   = raw.rfind("}") + 1
            if start == -1 or end == 0:
                return None
            data: dict[str, Any] = json.loads(raw[start:end])

            sessions_data: list[dict] = data.get("sessions", [])
            if len(sessions_data) != len(fallback_sessions):
                log.warning("Claude returned wrong session count — discarding")
                return None

            # Valider et construire les sessions
            sessions: list[PlannedSession] = []
            for i, (orig, refined) in enumerate(zip(fallback_sessions, sessions_data)):
                # Ignorer toute tentative de modifier jour/durée/type
                sessions.append(PlannedSession(
                    day_of_week   = orig.day_of_week,
                    activity_name = orig.activity_name,
                    session_type  = orig.session_type,
                    duration_min  = orig.duration_min,
                    notes         = refined.get("notes") or orig.notes,
                    sort_order    = orig.sort_order,
                ))

            rationale: str = data.get("rationale") or ""
            if not rationale.strip():
                return None

            return TrainingWeekPlan(sessions=sessions, rationale=rationale, used_claude=True)

        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            log.warning("Failed to parse Claude training plan response: %s", exc)
            return None
