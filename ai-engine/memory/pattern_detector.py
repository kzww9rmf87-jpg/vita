"""
Détecteur de patterns — analyse statistique des corrélations
entre variables de santé sur les données longitudinales.

Exemples de patterns détectés :
- "Tu dors moins quand tu t'entraînes après 20h"
- "Tes performances baissent après 3 jours de stress élevé"
- "Ta motivation est plus haute les jours où tu dors > 7h"
"""
from scipy import stats
import numpy as np
from db import get_pool


async def detect_patterns(user_id: str) -> list[dict]:
    """Lance toutes les analyses de corrélations et sauvegarde les nouveaux patterns."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT
                s.date,
                s.duration_minutes    AS sleep_min,
                s.quality_score       AS sleep_quality,
                nd.calories,
                nd.protein_g,
                nd.alcohol_g,
                dc.energy,
                dc.mood,
                dc.stress,
                dc.motivation,
                act.sessions,
                act.avg_rpe,
                act.late_sessions
            FROM generate_series(CURRENT_DATE - 90, CURRENT_DATE, '1 day') AS d(date)
            LEFT JOIN sleep_entries s
                ON s.user_id = $1 AND s.date = d.date
            LEFT JOIN nutrition_daily nd
                ON nd.user_id = $1 AND nd.date = d.date
            LEFT JOIN daily_checkins dc
                ON dc.user_id = $1 AND dc.date = d.date AND dc.type = 'morning'
            LEFT JOIN (
                SELECT date,
                       COUNT(*)                                                      AS sessions,
                       AVG(rpe)                                                      AS avg_rpe,
                       COUNT(*) FILTER (WHERE EXTRACT(HOUR FROM started_at) >= 20)  AS late_sessions
                FROM activity_sessions WHERE user_id = $1
                GROUP BY date
            ) act ON act.date = d.date
            ORDER BY d.date ASC
        """, user_id)

        if len(rows) < 30:
            return []

        data = {
            "sleep_min":    [float(r["sleep_min"])    if r["sleep_min"]    else None for r in rows],
            "sleep_quality":[float(r["sleep_quality"]) if r["sleep_quality"] else None for r in rows],
            "energy":       [float(r["energy"])        if r["energy"]        else None for r in rows],
            "stress":       [float(r["stress"])        if r["stress"]        else None for r in rows],
            "motivation":   [float(r["motivation"])    if r["motivation"]    else None for r in rows],
            "alcohol_g":    [float(r["alcohol_g"])     if r["alcohol_g"]     else 0.0  for r in rows],
            "late_sessions":[float(r["late_sessions"]) if r["late_sessions"] else 0.0  for r in rows],
            "protein_g":    [float(r["protein_g"])     if r["protein_g"]     else None for r in rows],
        }

        found_patterns = []

        async with conn.transaction():
            # Pattern : entraînement tardif → sommeil dégradé
            p = _correlate(
                x=data["late_sessions"], y=data["sleep_quality"],
                pattern_type="late_training_vs_sleep",
                description_user="Tu dors moins bien les nuits où tu t'entraînes après 20h.",
                direction_if_negative=True,
            )
            if p:
                found_patterns.append(p)
                await _save_pattern(conn, user_id, p)

            # Pattern : alcool → énergie J+1 dégradée
            p = _correlate(
                x=data["alcohol_g"][:-1], y=data["energy"][1:],
                pattern_type="alcohol_vs_next_day_energy",
                description_user="Le lendemain d'une consommation d'alcool, ton énergie est plus basse.",
                direction_if_negative=True,
            )
            if p:
                found_patterns.append(p)
                await _save_pattern(conn, user_id, p)

            # Pattern : stress élevé → motivation basse J+1
            p = _correlate(
                x=data["stress"][:-1], y=data["motivation"][1:],
                pattern_type="stress_vs_motivation",
                description_user="Les jours de fort stress, ta motivation est plus basse le lendemain.",
                direction_if_negative=True,
            )
            if p:
                found_patterns.append(p)
                await _save_pattern(conn, user_id, p)

            # Pattern : bonne nuit → bonne énergie
            p = _correlate(
                x=data["sleep_min"], y=data["energy"],
                pattern_type="sleep_duration_vs_energy",
                description_user="Quand tu dors plus longtemps, ton énergie matinale est significativement meilleure.",
                direction_if_negative=False,
            )
            if p:
                found_patterns.append(p)
                await _save_pattern(conn, user_id, p)

    return found_patterns


def _correlate(
    x: list,
    y: list,
    pattern_type: str,
    description_user: str,
    direction_if_negative: bool,
    min_r: float = 0.25,
    min_p: float = 0.05,
) -> dict | None:
    """
    Calcule la corrélation de Pearson entre deux séries.
    Ne conserve que les paires où les deux valeurs sont non-nulles.
    """
    pairs = [(xi, yi) for xi, yi in zip(x, y) if xi is not None and yi is not None]
    if len(pairs) < 20:
        return None

    xs = np.array([p[0] for p in pairs])
    ys = np.array([p[1] for p in pairs])

    r, p_value = stats.pearsonr(xs, ys)

    if p_value > min_p or abs(r) < min_r:
        return None

    direction = "negative" if r < 0 else "positive"
    expected_direction = "negative" if direction_if_negative else "positive"

    if direction != expected_direction:
        return None

    return {
        "pattern_type":    pattern_type,
        "description":     f"r={r:.2f}, p={p_value:.3f}",
        "description_user": description_user,
        "confidence":      min(0.95, abs(r) * (1 - p_value)),
        "effect_size":     round(abs(r), 3),
        "direction":       direction,
        "variables":       [pattern_type.split("_vs_")[0], pattern_type.split("_vs_")[-1]],
    }


async def _save_pattern(conn, user_id: str, pattern: dict) -> None:
    await conn.execute("""
        INSERT INTO user_patterns
          (user_id, pattern_type, description, description_user, variables,
           confidence, effect_size, direction)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT DO NOTHING
    """,
        user_id,
        pattern["pattern_type"],
        pattern["description"],
        pattern["description_user"],
        pattern["variables"],
        pattern["confidence"],
        pattern["effect_size"],
        pattern["direction"],
    )
