"""
Gestionnaire de mémoire durable de VITA.

Deux responsabilités :
  1. extract_and_store(user_id) — analyse les données des 7 derniers jours
     et génère des mémoires rule-based depuis les sources structurées
     (check-ins, sommeil, activité, nutrition, patterns détectés).
     Appelé après chaque check-in matinal.

  2. load_memories(user_id, limit) — charge les mémoires actives
     pour les injecter dans le contexte chat ou recommandation.

Pas de dépendance à Claude ici : tout est rule-based.
La couche Claude-based (extraction depuis les conversations) sera ajoutée
quand les crédits Anthropic seront disponibles.
"""
import logging
from datetime import date, timedelta
from db import get_pool

logger = logging.getLogger(__name__)


# ── Extraction rule-based ─────────────────────────────────────────────────────

async def extract_and_store(user_id: str) -> int:
    """
    Analyse les 7 derniers jours et persiste les observations pertinentes
    dans vita_memories. Retourne le nombre de nouvelles mémoires créées.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        memories = []
        memories += await _extract_checkin_memories(conn, user_id)
        memories += await _extract_sleep_memories(conn, user_id)
        memories += await _extract_activity_memories(conn, user_id)
        memories += await _extract_nutrition_memories(conn, user_id)
        memories += await _extract_pattern_memories(conn, user_id)

        created = 0
        for m in memories:
            result = await conn.execute(
                """
                INSERT INTO vita_memories (user_id, content, category, source, importance)
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (user_id, content) DO NOTHING
                """,
                user_id, m["content"], m["category"], m["source"], m["importance"],
            )
            # asyncpg retourne "INSERT 0 N" — N=1 si inséré, 0 si conflit
            if result.endswith("1"):
                created += 1

        if created > 0:
            logger.info("[memory] %d nouvelle(s) mémoire(s) pour user %s", created, user_id)

        return created


async def _extract_checkin_memories(conn, user_id: str) -> list[dict]:
    """Observations basées sur les check-ins matinaux des 7 derniers jours."""
    rows = await conn.fetch(
        """
        SELECT date, energy, mood, stress
        FROM daily_checkins
        WHERE user_id = $1 AND date >= CURRENT_DATE - 7 AND type = 'morning'
        ORDER BY date DESC
        """,
        user_id,
    )
    if not rows:
        return []

    memories = []
    energies = [r["energy"] for r in rows if r["energy"] is not None]
    moods    = [r["mood"]   for r in rows if r["mood"]   is not None]
    stresses = [r["stress"] for r in rows if r["stress"] is not None]

    if energies:
        avg_energy = sum(energies) / len(energies)
        if avg_energy <= 2.0:
            memories.append({
                "content": f"Énergie très basse en moyenne cette semaine ({avg_energy:.1f}/5)",
                "category": "health", "source": "checkin", "importance": 3,
            })
        elif avg_energy >= 4.0:
            memories.append({
                "content": f"Excellente énergie cette semaine ({avg_energy:.1f}/5)",
                "category": "emotion", "source": "checkin", "importance": 2,
            })

        # Dégradation progressive
        if len(energies) >= 3 and all(energies[i] > energies[i+1] for i in range(min(2, len(energies)-1))):
            memories.append({
                "content": "Énergie en baisse progressive sur les 3 derniers jours",
                "category": "health", "source": "checkin", "importance": 3,
            })

    if stresses:
        avg_stress = sum(stresses) / len(stresses)
        if avg_stress >= 4.0:
            memories.append({
                "content": f"Niveau de stress élevé cette semaine ({avg_stress:.1f}/5)",
                "category": "emotion", "source": "checkin", "importance": 3,
            })

    # Régularité des check-ins
    if len(rows) >= 5:
        memories.append({
            "content": f"Check-in régulier : {len(rows)} jours enregistrés cette semaine",
            "category": "achievement", "source": "checkin", "importance": 1,
        })

    return memories


async def _extract_sleep_memories(conn, user_id: str) -> list[dict]:
    """Observations sur le sommeil des 7 derniers jours."""
    rows = await conn.fetch(
        """
        SELECT date, duration_minutes, quality_score
        FROM sleep_entries
        WHERE user_id = $1 AND date >= CURRENT_DATE - 7
        ORDER BY date DESC
        """,
        user_id,
    )
    if not rows:
        return []

    memories = []
    durations = [r["duration_minutes"] for r in rows if r["duration_minutes"] is not None]
    qualities  = [r["quality_score"]   for r in rows if r["quality_score"]   is not None]

    if durations:
        avg_min = sum(durations) / len(durations)
        avg_h   = avg_min / 60
        if avg_h < 6.5:
            memories.append({
                "content": f"Nuits courtes cette semaine ({avg_h:.1f}h en moyenne)",
                "category": "health", "source": "sleep", "importance": 3,
            })
        elif avg_h >= 7.5:
            memories.append({
                "content": f"Sommeil suffisant cette semaine ({avg_h:.1f}h en moyenne)",
                "category": "health", "source": "sleep", "importance": 2,
            })

        # Dégradation sur les 3 dernières nuits
        last_3 = durations[:3]
        if len(last_3) == 3 and all(last_3[i] > last_3[i+1] for i in range(2)):
            memories.append({
                "content": "Durée de sommeil en baisse sur les 3 dernières nuits",
                "category": "health", "source": "sleep", "importance": 3,
            })

    if qualities:
        avg_q = sum(qualities) / len(qualities)
        if avg_q <= 2.0:
            memories.append({
                "content": f"Qualité de sommeil faible cette semaine ({avg_q:.1f}/5)",
                "category": "health", "source": "sleep", "importance": 3,
            })

    return memories


async def _extract_activity_memories(conn, user_id: str) -> list[dict]:
    """Observations sur l'activité physique des 7 derniers jours."""
    rows = await conn.fetch(
        """
        SELECT date, activity_name, duration_minutes, rpe, calories_burned
        FROM activity_sessions
        WHERE user_id = $1 AND date >= CURRENT_DATE - 7
        ORDER BY date DESC
        """,
        user_id,
    )
    memories = []
    n = len(rows)

    if n == 0:
        # Absence d'activité notable
        has_recent = await conn.fetchval(
            "SELECT COUNT(*) FROM activity_sessions WHERE user_id=$1 AND date >= CURRENT_DATE - 30",
            user_id,
        )
        if has_recent and has_recent > 0:
            memories.append({
                "content": "Aucune séance enregistrée cette semaine (inactif vs habitude)",
                "category": "health", "source": "activity", "importance": 2,
            })
        return memories

    memories.append({
        "content": f"{n} séance(s) d'entraînement cette semaine",
        "category": "achievement" if n >= 4 else "event",
        "source": "activity",
        "importance": 2 if n >= 3 else 1,
    })

    # Effort intense
    high_rpe = [r for r in rows if r["rpe"] is not None and r["rpe"] >= 8]
    if high_rpe:
        memories.append({
            "content": f"{len(high_rpe)} séance(s) à haute intensité (RPE ≥ 8) cette semaine",
            "category": "health", "source": "activity", "importance": 2,
        })

    # Types d'activités pratiquées
    types = list({r["activity_name"] for r in rows if r["activity_name"]})
    if types:
        memories.append({
            "content": f"Activités pratiquées : {', '.join(types[:3])}",
            "category": "preference", "source": "activity", "importance": 1,
        })

    return memories


async def _extract_nutrition_memories(conn, user_id: str) -> list[dict]:
    """Observations nutritionnelles des 7 derniers jours."""
    rows = await conn.fetch(
        """
        SELECT date, calories, protein_g, adherence_score
        FROM nutrition_daily
        WHERE user_id = $1 AND date >= CURRENT_DATE - 7
        ORDER BY date DESC
        """,
        user_id,
    )
    if not rows:
        return []

    memories = []
    proteins    = [r["protein_g"]      for r in rows if r["protein_g"]      is not None]
    adherences  = [r["adherence_score"] for r in rows if r["adherence_score"] is not None]

    if proteins:
        avg_prot = sum(proteins) / len(proteins)
        if avg_prot < 100:
            memories.append({
                "content": f"Apport en protéines insuffisant cette semaine ({avg_prot:.0f}g/j en moyenne)",
                "category": "health", "source": "nutrition", "importance": 2,
            })

    if adherences:
        avg_adh = sum(adherences) / len(adherences)
        if avg_adh >= 0.8:
            memories.append({
                "content": f"Bonne régularité alimentaire cette semaine ({avg_adh:.0%} d'adhérence)",
                "category": "achievement", "source": "nutrition", "importance": 2,
            })

    return memories


async def _extract_pattern_memories(conn, user_id: str) -> list[dict]:
    """Convertit les patterns actifs récents en mémoires."""
    rows = await conn.fetch(
        """
        SELECT description_user, confidence, direction
        FROM user_patterns
        WHERE user_id = $1 AND active = true AND confidence >= 0.7
        ORDER BY confidence DESC LIMIT 5
        """,
        user_id,
    )
    memories = []
    for r in rows:
        if r["description_user"]:
            memories.append({
                "content": r["description_user"],
                "category": "pattern",
                "source": "pattern",
                "importance": 3 if r["confidence"] >= 0.85 else 2,
            })
    return memories


# ── Lecture des mémoires ──────────────────────────────────────────────────────

async def load_memories(user_id: str, limit: int = 10) -> list[dict]:
    """
    Charge les mémoires actives d'un utilisateur, triées par importance
    puis par date. Utilisé pour injecter dans le contexte du chat.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT content, category, importance, remembered_at
            FROM vita_memories
            WHERE user_id = $1
              AND active = true
              AND (expires_at IS NULL OR expires_at > NOW())
            ORDER BY importance DESC, remembered_at DESC
            LIMIT $2
            """,
            user_id, limit,
        )
        return [
            {
                "content": r["content"],
                "category": r["category"],
                "importance": r["importance"],
            }
            for r in rows
        ]


async def store_memory(
    user_id: str,
    content: str,
    category: str,
    source: str,
    importance: int = 2,
    source_id: str | None = None,
) -> bool:
    """
    Stocke manuellement une mémoire (ex: depuis une conversation).
    Retourne True si créée, False si déjà existante (conflict silencieux).
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        result = await conn.execute(
            """
            INSERT INTO vita_memories
                (user_id, content, category, source, source_id, importance)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (user_id, content) DO NOTHING
            """,
            user_id, content, category, source, source_id, importance,
        )
        return result.endswith("1")
