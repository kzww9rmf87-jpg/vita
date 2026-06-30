"""
TrainingPlannerAgent — algorithme local + raffinement optionnel par Claude.

Sprint 12.4 : exploite sport_identity (découverte conversationnelle) pour
enrichir les séances avec intensité, objectif, consigne et raison du choix.

Architecture :
  1. Fusion profile + identity → priorités et exclusions
  2. Planification locale (déterministe, toujours disponible)
  3. Claude enrichit les champs narratifs (goal, instruction, why, rationale)
  4. Fallback complet sur le local si Claude échoue
"""
from __future__ import annotations
import json
import logging
from typing import Any

import anthropic

from config import get_settings
from .models import (
    TrainingPlannerInput, TrainingWeekPlan, PlannedSession, SessionType,
    SportIdentityInput,
)
from .planner import plan_locally, build_rationale, _resolve_activities

log = logging.getLogger(__name__)
settings = get_settings()

_INTENSITY_BY_TYPE: dict[SessionType, str] = {
    SessionType.walk:     "douce",
    SessionType.mobility: "douce",
    SessionType.recovery: "douce",
    SessionType.cardio:   "modérée",
    SessionType.strength: "modérée",
    SessionType.combat:   "soutenue",
}


class TrainingPlannerAgent:

    async def plan(self, inp: TrainingPlannerInput) -> TrainingWeekPlan:
        """Point d'entrée principal — retourne toujours un résultat."""
        # Fusionne sport_identity dans le profil (priorités + exclusions)
        merged_inp = _merge_identity(inp)

        sessions  = plan_locally(merged_inp)
        rationale = build_rationale(merged_inp.sport_profile, sessions)

        # Labellise l'intensité localement (pas besoin de Claude)
        for s in sessions:
            s.intensity_label = _INTENSITY_BY_TYPE.get(s.session_type, "modérée")

        if not self._should_call_claude(merged_inp, sessions):
            return TrainingWeekPlan(
                sessions=sessions,
                rationale=rationale,
                used_claude=False,
                used_identity=inp.sport_identity is not None,
            )

        try:
            refined = await self._refine_with_claude(merged_inp, sessions, rationale)
            return refined
        except Exception as exc:
            log.warning("Claude unavailable for training planner (%s) — using local plan", exc)
            return TrainingWeekPlan(
                sessions=sessions,
                rationale=rationale,
                used_claude=False,
                used_identity=inp.sport_identity is not None,
            )

    # ── Conditions d'appel Claude ──────────────────────────────────────────────

    def _should_call_claude(self, inp: TrainingPlannerInput, sessions: list[PlannedSession]) -> bool:
        """Claude intervient quand il peut apporter une vraie valeur narrative."""
        if not sessions:
            return False
        # Si sport_identity disponible → Claude enrichit toujours (narratif ancré)
        if inp.sport_identity is not None:
            return True
        # Sinon : plan varié avec contraintes, comme avant
        types = {s.session_type for s in sessions}
        if len(types) < 2:
            return False
        return bool(inp.pain_areas or inp.equipment or inp.sport_profile.context)

    # ── Raffinement Claude ────────────────────────────────────────────────────

    async def _refine_with_claude(
        self,
        inp: TrainingPlannerInput,
        sessions: list[PlannedSession],
        rationale: str,
    ) -> TrainingWeekPlan:
        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        prompt = self._build_prompt(inp, sessions, rationale)
        msg = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=2000,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = msg.content[0].text.strip()
        result = self._parse_claude_response(raw, sessions)
        if result:
            result.used_identity = inp.sport_identity is not None
            return result
        return TrainingWeekPlan(
            sessions=sessions,
            rationale=rationale,
            used_claude=False,
            used_identity=inp.sport_identity is not None,
        )

    def _build_prompt(
        self,
        inp: TrainingPlannerInput,
        sessions: list[PlannedSession],
        rationale: str,
    ) -> str:
        profile  = inp.sport_profile
        identity = inp.sport_identity

        sessions_json = json.dumps(
            [s.model_dump(mode="json") for s in sessions],
            ensure_ascii=False, indent=2,
        )

        # Contexte profil
        constraints: list[str] = []
        if inp.pain_areas:
            constraints.append(f"Zones sensibles : {', '.join(inp.pain_areas)}")
        if inp.equipment:
            constraints.append(f"Équipement disponible : {', '.join(inp.equipment)}")
        if profile.context:
            constraints.append(f"Contexte : {profile.context}")

        # Contexte identité (ancré dans la conversation de découverte)
        identity_block = ""
        if identity:
            parts: list[str] = []
            if identity.rapport_au_sport:
                parts.append(f"Rapport au sport : {identity.rapport_au_sport}")
            if identity.motivations:
                parts.append(f"Motivations : {', '.join(identity.motivations)}")
            if identity.freins:
                parts.append(f"Freins : {', '.join(identity.freins)}")
            if identity.experiences_positives:
                parts.append(f"Ce qui a fonctionné : {', '.join(identity.experiences_positives)}")
            if identity.personnalite:
                parts.append(f"Profil : {identity.personnalite}")
            if identity.contexte_prefere:
                parts.append(f"Contexte préféré : {', '.join(identity.contexte_prefere)}")
            if identity.contraintes:
                parts.append(f"Contraintes déclarées : {', '.join(identity.contraintes)}")
            if identity.resume_valide:
                parts.append(f"Ce que VITA a compris de lui : « {identity.resume_valide} »")
            identity_block = "\n".join(f"- {p}" for p in parts)

        return f"""Tu es un préparateur physique bienveillant qui travaille avec VITA.

Voici le plan d'entraînement pour cette semaine :
{sessions_json}

Niveau : {profile.fitness_level}
{"Contraintes :" + chr(10) + chr(10).join(f'- {c}' for c in constraints) if constraints else ""}
{"Ce que VITA sait de cette personne (issu de son entretien de découverte) :" + chr(10) + identity_block if identity_block else ""}

Rationale initiale : {rationale}

Ta mission :
1. Pour chaque séance, rédige :
   - session_goal : l'objectif de la séance en 1 phrase bienveillante (ex : "Retrouver le plaisir de bouger sans se forcer")
   - simple_instruction : une consigne concrète et simple (ex : "Marche 20 min à ton rythme — pas de chrono, juste avancer")
   - progression_note : une note de progression douce (ex : "La semaine prochaine, tu pourras ajouter 5 minutes si tu en as envie")
   - why_this_session : pourquoi VITA a choisi cette activité pour cette personne (ancré dans ce qu'elle a confié, pas générique)
   - notes : conseils pratiques éventuels (ou null)
2. Réécris la rationale de manière chaleureuse, personnalisée, non-culpabilisante.
   Si sport_identity disponible : ancre la rationale dans ce que la personne a confié.
3. NE modifie PAS : day_of_week, activity_name, session_type, duration_min, sort_order, intensity_label.
4. Ton : "Je te propose…", "L'idée est…", "Cette séance peut t'aider à…"
5. Jamais "tu dois", jamais de jugement, jamais de promesse de résultat chiffré.
6. Jamais de diagnostic médical, jamais de promesse de perte de poids.

Réponds en JSON strict :
{{
  "sessions": [
    {{
      "day_of_week": <int>,
      "activity_name": "<str>",
      "session_type": "<str>",
      "duration_min": <int>,
      "intensity_label": "<str>",
      "sort_order": <int>,
      "session_goal": "<str>",
      "simple_instruction": "<str>",
      "progression_note": "<str ou null>",
      "why_this_session": "<str>",
      "notes": "<str ou null>"
    }}
  ],
  "rationale": "<str>"
}}"""

    def _parse_claude_response(
        self, raw: str, fallback_sessions: list[PlannedSession]
    ) -> TrainingWeekPlan | None:
        try:
            start = raw.find("{")
            end   = raw.rfind("}") + 1
            if start == -1 or end == 0:
                return None
            data: dict[str, Any] = json.loads(raw[start:end])

            sessions_data: list[dict] = data.get("sessions", [])
            if len(sessions_data) != len(fallback_sessions):
                log.warning("Claude returned wrong session count — discarding")
                return None

            sessions: list[PlannedSession] = []
            for orig, refined in zip(fallback_sessions, sessions_data):
                sessions.append(PlannedSession(
                    # Champs immuables — jamais modifiables par Claude
                    day_of_week        = orig.day_of_week,
                    activity_name      = orig.activity_name,
                    session_type       = orig.session_type,
                    duration_min       = orig.duration_min,
                    sort_order         = orig.sort_order,
                    intensity_label    = orig.intensity_label,
                    # Champs enrichis par Claude
                    session_goal       = refined.get("session_goal")       or None,
                    simple_instruction = refined.get("simple_instruction") or None,
                    progression_note   = refined.get("progression_note")   or None,
                    why_this_session   = refined.get("why_this_session")   or None,
                    notes              = refined.get("notes")              or orig.notes,
                ))

            rationale: str = data.get("rationale") or ""
            if not rationale.strip():
                return None

            return TrainingWeekPlan(sessions=sessions, rationale=rationale, used_claude=True)

        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            log.warning("Failed to parse Claude training plan response: %s", exc)
            return None


# ── Fusion profile + identity ─────────────────────────────────────────────────

def _merge_identity(inp: TrainingPlannerInput) -> TrainingPlannerInput:
    """
    Fusionne sport_identity dans sport_profile.
    - activites_recommandees → attractive_activities (priorité)
    - activites_refusees     → rejected_activities   (exclusion)
    Conserve les préférences du profil formulaire comme fallback.
    """
    if inp.sport_identity is None:
        return inp

    identity = inp.sport_identity
    profile  = inp.sport_profile

    # Les activités de la découverte prennent la priorité sur le formulaire
    merged_attractive = list(dict.fromkeys(
        identity.activites_recommandees + profile.attractive_activities
    ))
    # Union des refus : formulaire + découverte
    merged_rejected = list(dict.fromkeys(
        profile.rejected_activities + identity.activites_refusees
    ))
    # Contexte préféré : fusion si le profil n'en a pas
    merged_context = profile.preferred_context or identity.contexte_prefere

    new_profile = profile.model_copy(update={
        "attractive_activities": merged_attractive,
        "rejected_activities":   merged_rejected,
        "preferred_context":     merged_context,
    })

    return inp.model_copy(update={"sport_profile": new_profile})
