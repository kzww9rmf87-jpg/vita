"""
SportDiscovererAgent — propose des options d'activité adaptées à l'utilisateur.

Rôle : ne pas imposer un plan d'emblée, mais d'abord comprendre ce qui semble
accessible, agréable et réaliste pour cette personne.

Architecture :
  1. Algorithme local (déterministe) → sélectionne un pool d'options candidates
  2. Claude (optionnel) → personnalise le "why" et le "first_step"
  3. Fallback complet sur le local si Claude est indisponible

Contraintes absolues :
  — Jamais de promesse de perte de poids
  — Jamais de diagnostic médical
  — Jamais de jugement sur la sédentarité passée
  — Si reprise après longue sédentarité ou appréhension élevée : mention douce
    de consulter un médecin si douleurs importantes
  — Toujours progressif
"""
from __future__ import annotations
import json
import logging

import anthropic

from config import get_settings
from .models import (
    SportDiscoverInput, SportDiscoverResult, ActivityOption,
)

log = logging.getLogger(__name__)
settings = get_settings()

# ── Catalogue local d'options ─────────────────────────────────────────────────
# Toutes les options disponibles, filtrées selon le profil.

_ALL_OPTIONS: list[ActivityOption] = [
    ActivityOption(
        name="Marche",
        why=(
            "La marche est la porte d'entrée la plus naturelle vers une activité régulière. "
            "Aucun matériel, aucun niveau requis — et les bienfaits se font sentir dès 20 minutes."
        ),
        constraint_level="tres_faible",
        first_step="Une sortie de 15 min dans ton quartier, au rythme qui te convient.",
        suggested_frequency="3 fois par semaine, 15-20 min pour commencer",
        session_type="walk",
    ),
    ActivityOption(
        name="Natation",
        why=(
            "La natation sollicite tout le corps sans impact sur les articulations. "
            "Elle convient à toutes les morphologies et à tous les niveaux."
        ),
        constraint_level="faible",
        first_step="30 min à la piscine, en alternant nage tranquille et repos — sans chrono.",
        suggested_frequency="2 fois par semaine",
        session_type="cardio",
    ),
    ActivityOption(
        name="Pilates",
        why=(
            "Le Pilates renforce en douceur les muscles profonds et améliore la posture. "
            "Idéal pour reprendre confiance dans son corps, sans effort intense."
        ),
        constraint_level="faible",
        first_step="Un cours débutant de 45 min — beaucoup de studios proposent un premier cours d'essai.",
        suggested_frequency="2 fois par semaine",
        session_type="mobility",
    ),
    ActivityOption(
        name="Mobilité",
        why=(
            "La mobilité articulaire améliore l'aisance dans les gestes du quotidien "
            "et prépare le corps à d'autres activités. Accessible à tous dès le premier jour."
        ),
        constraint_level="tres_faible",
        first_step="10-15 min de mouvements doux le matin — il existe de nombreuses vidéos gratuites.",
        suggested_frequency="4 à 5 fois par semaine, 10-15 min",
        session_type="mobility",
    ),
    ActivityOption(
        name="Vélo tranquille",
        why=(
            "Le vélo (ville, piste cyclable ou appartement) est progressif et sans impact. "
            "Tu choisis le rythme, tu t'arrêtes quand tu veux."
        ),
        constraint_level="faible",
        first_step="Un trajet de 20 min en ville ou un cours vélo doux en salle.",
        suggested_frequency="2 à 3 fois par semaine",
        session_type="cardio",
    ),
    ActivityOption(
        name="Renforcement léger",
        why=(
            "Quelques exercices simples au poids du corps — squats, gainage, pompes adaptées — "
            "renforcent sans nécessiter de matériel ni d'abonnement."
        ),
        constraint_level="faible",
        first_step="15-20 min chez soi avec 3 exercices simples, 2 séries chacun.",
        suggested_frequency="2 fois par semaine",
        session_type="strength",
    ),
    ActivityOption(
        name="Yoga doux",
        why=(
            "Le yoga doux combine respiration, étirements et renforcement léger. "
            "Particulièrement adapté si tu cherches à gérer le stress en même temps que de bouger."
        ),
        constraint_level="faible",
        first_step="Un cours yoga débutant de 45-60 min, en studio ou en ligne.",
        suggested_frequency="2 fois par semaine",
        session_type="mobility",
    ),
    ActivityOption(
        name="Course à pied",
        why=(
            "La course peut démarrer très doucement — interval run/walk pour les débutants. "
            "Pratiquable partout, sans contrainte d'horaire."
        ),
        constraint_level="modere",
        first_step="20 min en alternant 1 min de course et 2 min de marche — sans forcer.",
        suggested_frequency="2 à 3 fois par semaine",
        session_type="cardio",
    ),
    ActivityOption(
        name="Musculation",
        why=(
            "La musculation renforce progressivement les muscles et améliore la composition corporelle. "
            "En salle, un coach peut te guider dès la première séance."
        ),
        constraint_level="modere",
        first_step="Une séance découverte en salle de sport avec un conseiller.",
        suggested_frequency="2 à 3 fois par semaine",
        session_type="strength",
    ),
    ActivityOption(
        name="HIIT",
        why=(
            "Le HIIT (entraînement par intervalles) est efficace en peu de temps. "
            "Il convient mieux si tu as déjà une base d'activité physique."
        ),
        constraint_level="eleve",
        first_step="Un cours HIIT débutant de 20-30 min, avec pauses régulières.",
        suggested_frequency="2 fois par semaine",
        session_type="cardio",
    ),
]

# Mapping nom → option (recherche case-insensitive)
_OPTION_BY_NAME: dict[str, ActivityOption] = {
    o.name.lower(): o for o in _ALL_OPTIONS
}

# Options douces pour les profils sédentaires / niveau d'appréhension élevé
_GENTLE_NAMES = {"marche", "mobilité", "pilates", "vélo tranquille", "yoga doux"}


class SportDiscovererAgent:

    async def discover(self, inp: SportDiscoverInput) -> SportDiscoverResult:
        """Point d'entrée principal — retourne toujours un résultat."""
        local_options = _local_select(inp)

        try:
            refined = await self._personalize_with_claude(inp, local_options)
            return SportDiscoverResult(
                options=refined,
                discovery_question="Laquelle te semble la plus réaliste pour commencer ?",
                used_claude=True,
            )
        except Exception as exc:
            log.warning("Claude unavailable for discover (%s) — using local options", exc)
            return SportDiscoverResult(
                options=local_options,
                discovery_question="Laquelle te semble la plus réaliste pour commencer ?",
                used_claude=False,
            )

    # ── Personnalisation Claude ────────────────────────────────────────────────

    async def _personalize_with_claude(
        self,
        inp: SportDiscoverInput,
        local_options: list[ActivityOption],
    ) -> list[ActivityOption]:
        """
        Claude réécrit le "why" et le "first_step" de chaque option
        pour tenir compte du profil spécifique de l'utilisateur.
        Il ne change jamais le name, constraint_level, session_type.
        """
        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        prompt = self._build_prompt(inp, local_options)
        msg = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1500,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = msg.content[0].text.strip()
        parsed = self._parse_claude_response(raw, local_options)
        return parsed if parsed else local_options

    def _build_prompt(
        self,
        inp: SportDiscoverInput,
        local_options: list[ActivityOption],
    ) -> str:
        options_json = json.dumps(
            [o.model_dump(mode="json") for o in local_options],
            ensure_ascii=False, indent=2,
        )

        motivation_labels = {
            "bouger_un_peu":         "Bouger un peu, se sentir moins sédentaire",
            "reprendre_confiance":   "Reprendre confiance dans son corps",
            "ameliorer_energie":     "Améliorer son énergie au quotidien",
            "perdre_poids":          "Perdre du poids",
            "preparer_sport":        "Se préparer pour un sport ou une compétition",
        }
        apprehension_labels = {
            "aucune":   "aucune appréhension",
            "legere":   "légère appréhension",
            "moderee":  "appréhension modérée",
            "elevee":   "appréhension importante",
        }

        context_parts: list[str] = [
            f"- Niveau déclaré : {inp.fitness_level}",
        ]
        if inp.motivation:
            context_parts.append(f"- Objectif : {motivation_labels.get(inp.motivation, inp.motivation)}")
        if inp.preferred_context:
            labels = {"seul": "seul(e)", "groupe": "en groupe", "dehors": "dehors",
                      "maison": "à la maison", "salle": "en salle"}
            ctx = ", ".join(labels.get(c, c) for c in inp.preferred_context)
            context_parts.append(f"- Contexte préféré : {ctx}")
        context_parts.append(
            f"- Niveau d'appréhension : {apprehension_labels.get(inp.apprehension_level, inp.apprehension_level)}"
        )
        if inp.realistic_time_min:
            context_parts.append(f"- Temps réaliste disponible : {inp.realistic_time_min} min par séance")
        if inp.context:
            context_parts.append(f"- Contexte personnel : {inp.context}")

        medical_mention = ""
        if inp.apprehension_level in ("moderee", "elevee") or inp.fitness_level == "beginner":
            medical_mention = (
                "\n— Si tu as des douleurs importantes ou une longue période sans activité, "
                "consulter un médecin avant de démarrer peut être utile. Mentionne-le de manière "
                "douce dans un seul 'first_step' si pertinent — pas dans tous."
            )

        return f"""Tu es VITA, assistant bienveillant. Ta mission : personnaliser des options
d'activité pour aider l'utilisateur à trouver ce qui lui convient vraiment.

CONTEXTE UTILISATEUR
{chr(10).join(context_parts)}

OPTIONS SÉLECTIONNÉES (à personnaliser, pas à remplacer) :
{options_json}

RÈGLES ABSOLUES
— Jamais de promesse de perte de poids (pas de "tu vas maigrir", "tu vas perdre")
— Jamais de diagnostic médical
— Jamais de jugement sur la sédentarité ou le passé
— Le champ "why" doit être chaleureux, motivant et spécifique au profil — 2-3 phrases max
— Le champ "first_step" doit être concret, très simple, immédiatement actionnable
— NE PAS changer : name, constraint_level, suggested_frequency, session_type
— Adapter uniquement : why et first_step{medical_mention}

FORMAT JSON strict — même structure que l'input, exactement {len(local_options)} options :
{{
  "options": [
    {{
      "name": "<identique à l'input>",
      "why": "<réécrit pour ce profil>",
      "constraint_level": "<identique>",
      "first_step": "<réécrit très concrètement>",
      "suggested_frequency": "<identique>",
      "session_type": "<identique>"
    }}
  ]
}}"""

    def _parse_claude_response(
        self,
        raw: str,
        fallback: list[ActivityOption],
    ) -> list[ActivityOption] | None:
        try:
            start = raw.find("{")
            end   = raw.rfind("}") + 1
            if start == -1 or end == 0:
                return None
            data = json.loads(raw[start:end])
            opts_data: list[dict] = data.get("options", [])
            if len(opts_data) != len(fallback):
                log.warning("Claude discover returned wrong option count — using local")
                return None
            result: list[ActivityOption] = []
            for orig, refined in zip(fallback, opts_data):
                result.append(ActivityOption(
                    name=orig.name,
                    why=refined.get("why") or orig.why,
                    constraint_level=orig.constraint_level,
                    first_step=refined.get("first_step") or orig.first_step,
                    suggested_frequency=orig.suggested_frequency,
                    session_type=orig.session_type,
                ))
            return result
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            log.warning("Failed to parse Claude discover response: %s", exc)
            return None


# ── Algorithme local de sélection ─────────────────────────────────────────────

def _local_select(inp: SportDiscoverInput) -> list[ActivityOption]:
    """
    Sélectionne 3 à 5 options adaptées au profil.
    — Exclut les rejected_activities
    — Pour les niveaux beginner ou appréhension élevée : favorise les options douces
    — Intègre les attractive_activities si elles correspondent à une option connue
    """
    rejected_lower = {r.lower() for r in inp.rejected_activities}

    # Exclure les activités rejetées
    available = [o for o in _ALL_OPTIONS if o.name.lower() not in rejected_lower]

    is_gentle_profile = (
        inp.fitness_level == "beginner"
        or inp.apprehension_level in ("moderee", "elevee")
        or inp.motivation in ("bouger_un_peu", "reprendre_confiance")
    )

    # Construire la liste de priorité
    priority: list[ActivityOption] = []
    rest: list[ActivityOption] = []

    # 1. Activités déclarées attractives (si connues dans le catalogue)
    for name in inp.attractive_activities:
        opt = _OPTION_BY_NAME.get(name.lower())
        if opt and opt.name.lower() not in rejected_lower:
            priority.append(opt)

    # 2. Si profil doux → priorité aux options douces
    if is_gentle_profile:
        for o in available:
            if o.name.lower() in _GENTLE_NAMES and o not in priority:
                priority.append(o)
        for o in available:
            if o.name.lower() not in _GENTLE_NAMES and o not in priority:
                rest.append(o)
    else:
        for o in available:
            if o not in priority:
                rest.append(o)

    # 3. Filtrer par contexte préféré si renseigné
    if inp.preferred_context:
        context_score = _context_score_fn(inp.preferred_context)
        rest.sort(key=context_score, reverse=True)

    combined = priority + rest

    # 4. Limiter à 3-5 options (5 pour les profils doux, 4 sinon)
    n = 5 if is_gentle_profile else 4
    return combined[:n]


def _context_score_fn(preferred_context: list[str]):
    """Retourne une fonction de score pour trier les options selon le contexte."""
    def score(opt: ActivityOption) -> int:
        s = 0
        if "maison" in preferred_context and opt.session_type in ("mobility", "strength"):
            s += 1
        if "dehors" in preferred_context and opt.session_type in ("walk", "cardio"):
            s += 1
        if "salle" in preferred_context and opt.name.lower() in ("musculation", "pilates", "natation", "hiit"):
            s += 1
        return s
    return score
