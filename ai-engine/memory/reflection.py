"""
Reflection Engine — génération de réflexions hebdomadaires.

Génère une réflexion pour une semaine donnée si elle n'existe pas encore.
Appelé idéalement chaque lundi matin (décision du scheduler externe).

Contraintes de la réflexion :
  — 300 mots maximum
  — Connecte les événements de la semaine aux mémoires longue durée
  — Identifie un schéma ou une évolution perçue
  — Pose une question profonde et ouverte (jamais rhétorique, jamais culpabilisante)
  — Jamais de prescription ("tu devrais"), jamais de minimisation
  — Ton : présence bienveillante, pas de coaching

Stockage : vita_reflections (une par utilisateur par semaine)
"""
from __future__ import annotations

import json
import logging
from datetime import date, timedelta
from typing import Optional

import anthropic

from config import get_settings
from db import get_pool
from .models import Reflection
from .postgres_provider import PostgresMemoryProvider

logger = logging.getLogger(__name__)
settings = get_settings()
_client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
_provider = PostgresMemoryProvider()

_REFLECTION_SYSTEM = """Tu es VITA — un Témoin Bienveillant qui génère une réflexion hebdomadaire.

Tu reçois :
  - Les entrées de journal de la semaine (résumés anonymisés)
  - Les mémoires importantes de cette personne
  - La période couverte

Ta réflexion doit :
  1. Nommer ce qui a traversé la semaine sans dramatiser ni minimiser.
  2. Connecter un événement de la semaine à quelque chose de plus profond (une valeur, une peur, un objectif).
  3. Identifier doucement un schéma ou une évolution visible.
  4. Terminer par une question ouverte et profonde — jamais rhétorique, jamais culpabilisante.

Contraintes absolues :
  — Maximum 300 mots.
  — Jamais de liste à puces ou de titres.
  — Jamais de "tu devrais", "essaie de", "il faut".
  — Jamais de "c'est normal", "ça va aller", "tout le monde".
  — Écrire à la 2e personne (tu/te).

Réponds avec un JSON unique, sans markdown :
{
  "content": "...",
  "themes": ["thème1", "thème2"],
  "question": "..."
}"""


async def generate_weekly_reflection(
    user_id: str,
    week_start: Optional[date] = None,
) -> Optional[Reflection]:
    """
    Génère la réflexion hebdomadaire pour `user_id`.

    `week_start` : lundi de la semaine. Si None, prend le lundi de la semaine courante.

    Retourne None si :
      - Une réflexion existe déjà pour cette semaine
      - Pas assez de données (< 2 entrées de journal ou check-ins)
      - Erreur API

    Ne lève jamais d'exception vers l'appelant.
    """
    try:
        if week_start is None:
            today = date.today()
            week_start = today - timedelta(days=today.weekday())
        week_end = week_start + timedelta(days=6)

        # Vérifie si déjà générée
        pool = await get_pool()
        async with pool.acquire() as conn:
            existing = await conn.fetchval(
                "SELECT id FROM vita_reflections WHERE user_id = $1 AND period_start = $2",
                user_id, week_start,
            )
            if existing:
                return None

            # Récupère les résumés de journal de la semaine (jamais le contenu brut)
            journal_rows = await conn.fetch(
                """
                SELECT mood_label, emotional_tone, themes, created_at::date AS day
                FROM journal_entries
                WHERE user_id = $1
                  AND created_at::date BETWEEN $2 AND $3
                ORDER BY created_at
                """,
                user_id, week_start, week_end,
            )

            # Récupère les check-ins
            checkin_rows = await conn.fetch(
                """
                SELECT type, energy, mood, stress, date
                FROM daily_checkins
                WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ORDER BY date, type
                """,
                user_id, week_start, week_end,
            )

        # Seuil minimum : au moins 2 données (journal ou check-in)
        if len(journal_rows) + len(checkin_rows) < 2:
            return None

        # Mémoires longue durée importantes
        memories = await _provider.get_by_user(user_id, limit=10, min_importance=3)

        # Construit le contexte pour Claude
        context = _build_context(
            week_start, week_end, list(journal_rows), list(checkin_rows), memories
        )

        # Génère la réflexion
        response = await _client.messages.create(
            model=settings.model_analysis,
            max_tokens=900,  # 300 mots ≈ 450 tokens + JSON wrapper + marge
            system=_REFLECTION_SYSTEM,
            messages=[{"role": "user", "content": context}],
        )

        raw = response.content[0].text.strip()
        parsed = json.loads(raw)

        content  = str(parsed.get("content", "")).strip()
        themes   = parsed.get("themes", [])
        question = parsed.get("question")

        if not content:
            return None

        # Persiste dans vita_reflections
        pool = await get_pool()
        async with pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                INSERT INTO vita_reflections (user_id, content, period_start, period_end, themes, question)
                VALUES ($1, $2, $3, $4, $5::jsonb, $6)
                ON CONFLICT (user_id, period_start) DO NOTHING
                RETURNING id, created_at
                """,
                user_id,
                content,
                week_start,
                week_end,
                json.dumps(themes),
                question,
            )

        if not row:
            return None  # Race condition — déjà inséré

        return Reflection(
            id=str(row["id"]),
            user_id=user_id,
            content=content,
            period_start=str(week_start),
            period_end=str(week_end),
            themes=themes,
            question=question,
            created_at=row["created_at"],
        )

    except Exception:
        logger.exception("generate_weekly_reflection failed for user %s", user_id)
        return None


def _build_context(week_start, week_end, journal_rows, checkin_rows, memories) -> str:
    lines = [
        f"Période : du {week_start} au {week_end}",
        "",
        "Entrées de journal de la semaine :",
    ]

    if journal_rows:
        for row in journal_rows:
            mood   = row["mood_label"] or "non défini"
            tone   = row["emotional_tone"] or ""
            themes = ", ".join(row["themes"] or [])
            lines.append(f"  - {row['day']} : {mood}{' / ' + tone if tone else ''}{' [' + themes + ']' if themes else ''}")
    else:
        lines.append("  (aucune entrée de journal cette semaine)")

    lines.append("")
    lines.append("Check-ins :")

    if checkin_rows:
        for row in checkin_rows:
            t      = "matin" if row["type"] == "morning" else "soir"
            energy = row["energy"] or "?"
            mood   = row["mood"] or "?"
            lines.append(f"  - {row['date']} {t} : énergie {energy}/5, humeur {mood}")
    else:
        lines.append("  (aucun check-in cette semaine)")

    if memories:
        lines.append("")
        lines.append("Ce que VITA sait de cet utilisateur :")
        for mem in memories:
            lines.append(f"  • [{mem.type.value}] {mem.summary}")

    return "\n".join(lines)
