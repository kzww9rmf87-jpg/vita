"""
Génération automatique des rapports périodiques via Claude.
Analyse croisée de toutes les données de la période.
"""
import anthropic
import json
import re
from datetime import date, timedelta
from config import get_settings
from db import get_pool


async def generate_weekly_report(user_id: str, period_start: date) -> dict:
    period_end = period_start + timedelta(days=6)
    data = await _load_period_data(user_id, period_start, period_end)
    report = await _generate_with_claude(data, period_start, period_end)
    await _save_report(user_id, "weekly", period_start, period_end, report)
    return report


async def _load_period_data(user_id: str, start: date, end: date) -> dict:
    """
    $1 = user_id, $2 = start, $3 = end, $4 = start - 1 day (poids de début de semaine)
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT
                (SELECT COUNT(*)
                    FROM sleep_entries WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS sleep_days,
                (SELECT AVG(duration_minutes)::NUMERIC(5,1)
                    FROM sleep_entries WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS avg_sleep_min,
                (SELECT AVG(quality_score)::NUMERIC(3,2)
                    FROM sleep_entries WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS avg_sleep_quality,
                (SELECT COUNT(*)
                    FROM activity_sessions WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS activity_sessions,
                (SELECT SUM(duration_minutes)
                    FROM activity_sessions WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS total_activity_min,
                (SELECT AVG(calories)::INT
                    FROM nutrition_daily WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS avg_calories,
                (SELECT AVG(protein_g)::NUMERIC(5,1)
                    FROM nutrition_daily WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS avg_protein,
                (SELECT AVG(adherence_score)::NUMERIC(3,2)
                    FROM nutrition_daily WHERE user_id = $1 AND date BETWEEN $2 AND $3
                ) AS nutrition_adherence,
                (SELECT AVG(energy)::NUMERIC(3,1)
                    FROM daily_checkins WHERE user_id = $1 AND date BETWEEN $2 AND $3 AND type = 'morning'
                ) AS avg_energy,
                (SELECT AVG(mood)::NUMERIC(3,1)
                    FROM daily_checkins WHERE user_id = $1 AND date BETWEEN $2 AND $3 AND type = 'morning'
                ) AS avg_mood,
                (SELECT AVG(stress)::NUMERIC(3,1)
                    FROM daily_checkins WHERE user_id = $1 AND date BETWEEN $2 AND $3 AND type = 'morning'
                ) AS avg_stress,
                (SELECT weight_kg
                    FROM user_snapshots WHERE user_id = $1 AND date <= $3
                    ORDER BY date DESC LIMIT 1
                ) AS weight_end,
                (SELECT weight_kg
                    FROM user_snapshots WHERE user_id = $1 AND date <= $4
                    ORDER BY date DESC LIMIT 1
                ) AS weight_start
        """, user_id, start, end, start - timedelta(days=1))

        stats = dict(row) if row else {}

        pattern_rows = await conn.fetch("""
            SELECT description_user, confidence, direction
            FROM user_patterns WHERE user_id = $1 AND active = true
            ORDER BY confidence DESC LIMIT 5
        """, user_id)
        stats["patterns"] = [dict(r) for r in pattern_rows]

    return stats


async def _generate_with_claude(data: dict, start: date, end: date) -> dict:
    settings = get_settings()
    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

    prompt = f"""Tu es un expert en santé et performance. Génère un rapport hebdomadaire de santé en JSON.

Données de la semaine du {start} au {end} :
{json.dumps(data, default=str, indent=2, ensure_ascii=False)}

Génère un rapport JSON avec exactement cette structure :
{{
  "summary": "résumé en 2 phrases",
  "highlights": ["point positif 1", "point positif 2"],
  "risks": ["risque 1 si applicable"],
  "sleep_analysis": "analyse du sommeil en 1-2 phrases",
  "activity_analysis": "analyse de l'activité en 1-2 phrases",
  "nutrition_analysis": "analyse de la nutrition en 1-2 phrases",
  "mental_analysis": "analyse mentale en 1-2 phrases",
  "next_week_focus": "UN objectif prioritaire pour la semaine prochaine",
  "score": {{
    "overall": 0-100,
    "sleep": 0-100,
    "activity": 0-100,
    "nutrition": 0-100,
    "mental": 0-100
  }}
}}

Règles : bienveillant, factuel, actionnable, jamais de culpabilisation."""

    response = await client.messages.create(
        model=settings.model_analysis,
        max_tokens=1500,
        messages=[{"role": "user", "content": prompt}],
    )

    text = response.content[0].text
    json_match = re.search(r'\{.*\}', text, re.DOTALL)
    if json_match:
        return json.loads(json_match.group())

    return {"summary": text, "error": "json_parse_failed"}


async def _save_report(user_id: str, period_type: str, start: date, end: date, content: dict) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("""
            INSERT INTO periodic_reports
              (user_id, period_type, period_start, period_end, content, summary)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT DO NOTHING
        """,
            user_id,
            period_type,
            start,
            end,
            json.dumps(content),
            content.get("summary", ""),
        )
