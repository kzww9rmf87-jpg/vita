"""
Daily Insight Engine — synthèse quotidienne interprétative de VITA.

VITA n'attribue pas de score. VITA interprète ce qui s'est passé.
Jamais de jugement. Jamais de culpabilisation. Toujours une compréhension.

Idempotence : si un insight existe déjà pour ce jour, il est retourné sans régénération.
"""
import json
import logging
import re
from datetime import date, timedelta
from typing import Optional

import anthropic
from pydantic import BaseModel

from config import get_settings
from db import get_pool

logger = logging.getLogger(__name__)
settings = get_settings()

# ── Ensemble limité des climates possibles ────────────────────────────────────
# L'IA choisit dans cet ensemble — jamais en dehors.
VALID_CLIMATES = frozenset({
    "CALM", "CONSTRUCTIVE", "DEMANDING", "RECOVERY",
    "UNCERTAIN", "ENERGIZED", "REFLECTIVE", "TRANSITION", "BALANCED",
})

# Fallback si l'IA renvoie un climat inconnu
_CLIMATE_FALLBACK = "BALANCED"

# ── Prompt système ────────────────────────────────────────────────────────────
# Le prompt est une déclaration de valeurs : pas de score, toujours du vécu.
DAILY_INSIGHT_SYSTEM_PROMPT = """Tu es VITA, un Témoin Bienveillant.

Ta mission ici est de produire la synthèse d'une journée pour un être humain.

RÈGLES ABSOLUES :
- Jamais de score, de note, de pourcentage, de rang, de comparaison.
- Jamais de jugement moral (bon/mauvais, réussi/échoué, bien/mal).
- Jamais de prescription ("tu devrais", "il faudrait", "pense à").
- Toujours descriptif : tu décris ce qui s'est passé, ce qui a été vécu.
- La journée n'est jamais "bonne" ni "mauvaise" — elle a un caractère, une texture.
- Tu parles du vécu, pas de la performance.

CLIMAT — choisis exactement l'un de ces 9 mots en majuscules :
CALM, CONSTRUCTIVE, DEMANDING, RECOVERY, UNCERTAIN, ENERGIZED, REFLECTIVE, TRANSITION, BALANCED

RÉSUMÉ — une seule phrase, maximum 35 mots.
Commence directement par le contenu. Ne commence pas par "Aujourd'hui" ni par le prénom.
Exemple : "Une journée qui a demandé beaucoup d'énergie tout en permettant d'avancer sur ce qui compte."

FACTEURS (drivers) — liste de 2 à 5 mots ou courtes expressions.
Choisis parmi : Travail, Projet personnel, Sommeil, Activité physique, Relations, Émotions,
Nutrition, Routine, Santé, Récupération, Stress, Créativité, Famille, Apprentissage.
Tu peux adapter si le contexte l'exige.

RÉFLEXION — paragraphe de 80 à 120 mots maximum.
Toujours descriptif, jamais prescriptif.
Décris ce que tu observes dans les données : les tensions, les ressources mobilisées,
les fils conducteurs de la journée. Tu peux faire des liens entre les différentes dimensions.

QUESTION — une seule question ouverte, maximum 25 mots.
Elle invite à la réflexion, pas à l'action. Elle ne culpabilise pas.
Exemple : "Qu'est-ce qui t'a permis de tenir le rythme malgré cette fatigue ?"

Réponds UNIQUEMENT avec un objet JSON valide, sans markdown, sans commentaire :
{
  "climate": "MOT_EN_MAJUSCULES",
  "summary": "...",
  "drivers": ["...", "..."],
  "reflection": "...",
  "question": "..."
}"""


# ── Modèle de sortie ──────────────────────────────────────────────────────────

class DailyInsight(BaseModel):
    id: str
    user_id: str
    date: str
    climate: str
    summary: str
    drivers: list[str]
    reflection: str
    question: str
    created_at: str


# ── Fonctions internes ────────────────────────────────────────────────────────

def _is_valid_climate(value: str) -> bool:
    return value.upper() in VALID_CLIMATES


async def _build_context_block(
    conn,
    user_id: str,
    insight_date: date,
) -> str:
    """
    Agrège les données disponibles du jour pour alimenter le prompt.
    Jamais de contenu brut de journal — uniquement les thèmes et tonalités.
    """
    lines: list[str] = []

    # ── Check-ins du jour
    checkins = await conn.fetch(
        """
        SELECT type, energy, mood, stress, notes
        FROM daily_checkins
        WHERE user_id = $1 AND date = $2
        ORDER BY type
        """,
        user_id, insight_date,
    )
    if checkins:
        lines.append("=== CHECK-INS DU JOUR ===")
        for c in checkins:
            label = "Matin" if c["type"] == "morning" else "Soir"
            parts = [f"{label} :"]
            if c["energy"] is not None:
                parts.append(f"énergie {c['energy']}/5")
            if c["mood"] is not None:
                parts.append(f"humeur {c['mood']}/5")
            if c["stress"] is not None:
                parts.append(f"stress {c['stress']}/5")
            lines.append(" · ".join(parts))
            # Les notes sont du contenu brut — on les inclut car c'est le propre vécu
            # de l'utilisateur qu'il a volontairement partagé avec VITA ce matin-là.
            if c["notes"]:
                lines.append(f"  Note : {c['notes'][:200]}")

    # ── Sommeil (nuit précédant ce jour)
    sleep = await conn.fetchrow(
        """
        SELECT duration_minutes, quality_score, energy_on_wake
        FROM sleep_entries
        WHERE user_id = $1 AND date = $2
        LIMIT 1
        """,
        user_id, insight_date,
    )
    if sleep:
        lines.append("=== SOMMEIL ===")
        parts = []
        if sleep["duration_minutes"] is not None:
            h = sleep["duration_minutes"] / 60
            parts.append(f"{h:.1f}h")
        if sleep["quality_score"] is not None:
            parts.append(f"qualité {sleep['quality_score']}/5")
        if sleep["energy_on_wake"] is not None:
            parts.append(f"réveil énergie {sleep['energy_on_wake']}/5")
        if parts:
            lines.append(" · ".join(parts))

    # ── Activité physique du jour
    activities = await conn.fetch(
        """
        SELECT activity_name, duration_minutes, rpe
        FROM activity_sessions
        WHERE user_id = $1 AND date = $2
        ORDER BY started_at NULLS LAST
        """,
        user_id, insight_date,
    )
    if activities:
        lines.append("=== ACTIVITÉ PHYSIQUE ===")
        for a in activities:
            parts = [a["activity_name"] or "Séance"]
            if a["duration_minutes"] is not None:
                parts.append(f"{a['duration_minutes']} min")
            if a["rpe"] is not None:
                parts.append(f"RPE {a['rpe']}/10")
            lines.append(" · ".join(parts))

    # ── Journal du jour — uniquement thèmes et tonalité (pas le contenu brut)
    journal = await conn.fetch(
        """
        SELECT mood_label, emotional_tone, themes, intensity
        FROM journal_entries
        WHERE user_id = $1 AND created_at::date = $2 AND is_private = false
        ORDER BY created_at
        """,
        user_id, insight_date,
    )
    if journal:
        lines.append("=== JOURNAL (thèmes uniquement) ===")
        for j in journal:
            parts = []
            if j["mood_label"]:
                parts.append(f"humeur : {j['mood_label']}")
            if j["emotional_tone"]:
                parts.append(f"tonalité : {j['emotional_tone']}")
            if j["themes"]:
                themes = j["themes"] if isinstance(j["themes"], list) else []
                if themes:
                    parts.append(f"thèmes : {', '.join(themes[:4])}")
            if j["intensity"] is not None:
                parts.append(f"intensité {j['intensity']}/5")
            if parts:
                lines.append(" · ".join(parts))

    # ── Mémoires longue durée actives (contexte de fond)
    memories = await conn.fetch(
        """
        SELECT type, summary, importance
        FROM vita_long_memories
        WHERE user_id = $1 AND importance >= 3
        ORDER BY importance DESC, last_seen DESC
        LIMIT 5
        """,
        user_id,
    )
    if memories:
        lines.append("=== CONTEXTE (mémoires actives) ===")
        for m in memories:
            stars = "★" * int(m["importance"])
            lines.append(f"({m['type']}, {stars}) {m['summary'][:100]}")

    # ── Réflexion de la semaine précédente (si disponible)
    prev_week = insight_date - timedelta(days=7)
    prev_reflection = await conn.fetchrow(
        """
        SELECT content
        FROM vita_reflections
        WHERE user_id = $1 AND period_start <= $2 AND period_end >= $2
        ORDER BY created_at DESC
        LIMIT 1
        """,
        user_id, prev_week,
    )
    if prev_reflection:
        lines.append("=== RÉFLEXION RÉCENTE ===")
        lines.append(prev_reflection["content"][:300])

    if not lines:
        return "(aucune donnée disponible pour ce jour)"

    return "\n".join(lines)


def _parse_ai_response(raw: str) -> dict:
    """
    Parse la réponse JSON de Claude. Valide et corrige le climate si nécessaire.
    Lève ValueError si le JSON est invalide ou les champs obligatoires absents.
    """
    # Extraire le JSON même si Claude a ajouté du texte autour
    match = re.search(r'\{.*\}', raw, re.DOTALL)
    if not match:
        raise ValueError(f"Pas de JSON trouvé dans la réponse: {raw[:200]}")

    data = json.loads(match.group())

    required = ("climate", "summary", "drivers", "reflection", "question")
    missing = [k for k in required if k not in data]
    if missing:
        raise ValueError(f"Champs manquants dans la réponse: {missing}")

    # Normaliser le climate — fallback si inconnu
    climate = str(data["climate"]).upper().strip()
    if not _is_valid_climate(climate):
        logger.warning("[daily_insight] Climate inconnu '%s' → fallback %s", climate, _CLIMATE_FALLBACK)
        climate = _CLIMATE_FALLBACK
    data["climate"] = climate

    # S'assurer que drivers est une liste non vide
    drivers = data.get("drivers", [])
    if not isinstance(drivers, list) or len(drivers) == 0:
        data["drivers"] = ["Vécu du jour"]

    # Tronquer pour respecter les contraintes de contenu
    # (le prompt demande max 35/120/25 mots, mais on protège la DB)
    data["summary"]    = str(data["summary"])[:400]
    data["reflection"] = str(data["reflection"])[:1000]
    data["question"]   = str(data["question"])[:300]

    return data


# ── API publique ──────────────────────────────────────────────────────────────

async def generate_daily_insight(
    user_id: str,
    insight_date: Optional[date] = None,
) -> DailyInsight | None:
    """
    Génère (ou retourne) l'insight quotidien pour user_id à insight_date.

    Idempotent : si un insight existe déjà pour ce jour, il est retourné sans appel Claude.
    Retourne None si aucune donnée n'est disponible pour ce jour.
    """
    if insight_date is None:
        insight_date = date.today()

    pool = await get_pool()
    async with pool.acquire() as conn:

        # ── Idempotence : retourner l'existant si disponible
        existing = await conn.fetchrow(
            """
            SELECT id::text, user_id::text, date::text, climate,
                   summary, drivers, reflection, question, created_at::text
            FROM daily_insights
            WHERE user_id = $1 AND date = $2
            """,
            user_id, insight_date,
        )
        if existing:
            return DailyInsight(
                id=existing["id"],
                user_id=existing["user_id"],
                date=existing["date"],
                climate=existing["climate"],
                summary=existing["summary"],
                drivers=list(existing["drivers"]),
                reflection=existing["reflection"],
                question=existing["question"],
                created_at=existing["created_at"],
            )

        # ── Construire le contexte
        context_block = await _build_context_block(conn, user_id, insight_date)

        if context_block == "(aucune donnée disponible pour ce jour)":
            logger.info("[daily_insight] Aucune donnée pour %s le %s", user_id, insight_date)
            return None

        # ── Appel Claude Sonnet
        client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

        user_message = (
            f"Date : {insight_date.isoformat()}\n\n"
            f"Données disponibles :\n{context_block}\n\n"
            "Génère la synthèse de cette journée."
        )

        try:
            response = client.messages.create(
                model=settings.model_analysis,
                max_tokens=600,
                system=DAILY_INSIGHT_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_message}],
            )
            raw = response.content[0].text
        except Exception as exc:
            logger.error("[daily_insight] Erreur Claude pour %s: %s", user_id, exc)
            raise

        # ── Parser la réponse
        try:
            parsed = _parse_ai_response(raw)
        except (ValueError, json.JSONDecodeError) as exc:
            logger.error("[daily_insight] Parse error pour %s: %s\nRaw: %s", user_id, exc, raw[:300])
            raise

        # ── Persister en DB
        row = await conn.fetchrow(
            """
            INSERT INTO daily_insights
                (user_id, date, climate, summary, drivers, reflection, question)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (user_id, date) DO UPDATE
              SET climate    = EXCLUDED.climate,
                  summary    = EXCLUDED.summary,
                  drivers    = EXCLUDED.drivers,
                  reflection = EXCLUDED.reflection,
                  question   = EXCLUDED.question,
                  updated_at = NOW()
            RETURNING id::text, user_id::text, date::text,
                      climate, summary, drivers, reflection, question, created_at::text
            """,
            user_id,
            insight_date,
            parsed["climate"],
            parsed["summary"],
            parsed["drivers"],
            parsed["reflection"],
            parsed["question"],
        )

        return DailyInsight(
            id=row["id"],
            user_id=row["user_id"],
            date=row["date"],
            climate=row["climate"],
            summary=row["summary"],
            drivers=list(row["drivers"]),
            reflection=row["reflection"],
            question=row["question"],
            created_at=row["created_at"],
        )
