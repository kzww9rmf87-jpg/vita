"""
Orchestrateur VITA — LangGraph

Graphe de traitement :
  load_context → [sport, sleep, nutrition, mental, health] (parallèle)
              → synthesis → save → return

Règle LangGraph : chaque nœud retourne un dict contenant uniquement
les clés qu'il modifie. Retourner l'état complet en parallèle provoque
une collision sur les clés non modifiées (ex: user_context).
"""
import json
from datetime import date

from langgraph.graph import StateGraph, END

from models import OrchestratorState, UserContext, AgentSignal
from agents import sport_agent, sleep_agent, nutrition_agent, mental_agent, health_agent
from agents import synthesis_agent
from db import get_pool, get_redis
from config import get_settings

settings = get_settings()


# ─── Noeuds du graphe ─────────────────────────────────────────────────────────

async def load_context(state: OrchestratorState) -> dict:
    """Charge toutes les données depuis la DB ou le cache. Seul nœud à écrire user_context."""
    user_id = state.user_context.user_id
    today = state.user_context.date

    cache = await get_redis()
    cache_key = f"vita:context:{user_id}:{today}"
    cached = await cache.get(cache_key)
    if cached:
        ctx_data = json.loads(cached)
        return {"user_context": UserContext(**ctx_data)}

    pool = await get_pool()
    async with pool.acquire() as conn:
        sleep_row = await conn.fetchrow(
            """SELECT duration_minutes, quality_score, awakenings,
                      energy_on_wake, hrv_ms, rhr_bpm
               FROM sleep_entries WHERE user_id = $1 AND date = $2""",
            user_id, today
        )
        sleep = dict(sleep_row) if sleep_row else {}

        activity_rows = await conn.fetch(
            """SELECT date::text, activity_name, duration_minutes,
                      calories_burned, rpe, started_at::text, hr_avg_bpm
               FROM activity_sessions
               WHERE user_id = $1 AND date >= $2::date - INTERVAL '14 days'
               ORDER BY date DESC""",
            user_id, today
        )
        activity_week = [dict(r) for r in activity_rows]

        nutrition_rows = await conn.fetch(
            """SELECT date::text, calories, protein_g, carbs_g, fat_g,
                      water_ml, alcohol_g, fiber_g, quality_score, adherence_score
               FROM nutrition_daily
               WHERE user_id = $1 AND date >= $2::date - INTERVAL '7 days'
               ORDER BY date DESC""",
            user_id, today
        )
        nutrition_week = [dict(r) for r in nutrition_rows]

        checkin_row = await conn.fetchrow(
            """SELECT energy, mood, stress, motivation,
                      pain_areas, pain_intensity, special_event
               FROM daily_checkins
               WHERE user_id = $1 AND date = $2 AND type = 'morning'""",
            user_id, today
        )
        checkin = dict(checkin_row) if checkin_row else {}

        profile_row = await conn.fetchrow(
            """SELECT up.primary_goal, up.activity_level, up.first_name,
                      us.weight_kg, us.baseline_energy, us.baseline_sleep_hours
               FROM user_profiles up
               LEFT JOIN user_snapshots us ON us.user_id = up.user_id
               WHERE up.user_id = $1
               ORDER BY us.date DESC NULLS LAST LIMIT 1""",
            user_id
        )
        profile = dict(profile_row) if profile_row else {}

        pattern_rows = await conn.fetch(
            """SELECT pattern_type, description_user, confidence, direction
               FROM user_patterns WHERE user_id = $1 AND active = true
               ORDER BY confidence DESC LIMIT 10""",
            user_id
        )
        patterns = [dict(r) for r in pattern_rows]

    user_context = UserContext(
        user_id=user_id,
        date=today,
        sleep=sleep or None,
        activity_week=activity_week,
        nutrition_week=nutrition_week,
        checkin_morning=checkin or None,
        patterns=patterns,
        profile=profile,
    )

    await cache.setex(cache_key, 600, user_context.model_dump_json())

    return {"user_context": user_context}


# Les agents spécialisés retournent uniquement leur propre clé de signal.
# user_context est lu en entrée mais jamais réécrit ici.

def run_sport_agent(state: OrchestratorState) -> dict:
    return {"sport_signal": sport_agent.analyze(state.user_context)}


def run_sleep_agent(state: OrchestratorState) -> dict:
    return {"sleep_signal": sleep_agent.analyze(state.user_context)}


def run_nutrition_agent(state: OrchestratorState) -> dict:
    return {"nutrition_signal": nutrition_agent.analyze(state.user_context)}


def run_mental_agent(state: OrchestratorState) -> dict:
    return {"mental_signal": mental_agent.analyze(state.user_context)}


def run_health_agent(state: OrchestratorState) -> dict:
    return {"health_signal": health_agent.analyze(state.user_context)}


async def run_synthesis(state: OrchestratorState) -> dict:
    """Fusionne tous les signaux et génère l'observation unique."""
    all_signals: list[AgentSignal] = [
        s for s in [
            state.sport_signal,
            state.sleep_signal,
            state.nutrition_signal,
            state.mental_signal,
            state.health_signal,
        ] if s is not None
    ]

    reco = await synthesis_agent.synthesize(all_signals, state.user_context)
    return {"final_recommendation": reco}


async def save_recommendation(state: OrchestratorState) -> dict:
    """Persiste l'observation en base. Ne modifie pas l'état."""
    reco = state.final_recommendation
    if not reco:
        return {}

    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute(
            """INSERT INTO ai_recommendations
                 (user_id, date, agent_source, content, content_short,
                  action_type, priority, reasoning, context_json)
               VALUES ($1, $2, $3, $4, $5, $6, 1, $7, $8)
               ON CONFLICT DO NOTHING""",
            state.user_context.user_id,
            state.user_context.date,
            reco.agent_source,
            reco.content,
            reco.content_short,
            reco.action_type,
            json.dumps(reco.reasoning),
            json.dumps({"confidence": reco.confidence}),
        )

    return {}


# ─── Construction du graphe LangGraph ─────────────────────────────────────────

def build_graph():
    graph = StateGraph(OrchestratorState)

    graph.add_node("load_context", load_context)
    graph.add_node("sport",        run_sport_agent)
    graph.add_node("sleep",        run_sleep_agent)
    graph.add_node("nutrition",    run_nutrition_agent)
    graph.add_node("mental",       run_mental_agent)
    graph.add_node("health",       run_health_agent)
    graph.add_node("synthesis",    run_synthesis)
    graph.add_node("save",         save_recommendation)

    graph.set_entry_point("load_context")

    for agent_node in ["sport", "sleep", "nutrition", "mental", "health"]:
        graph.add_edge("load_context", agent_node)
        graph.add_edge(agent_node, "synthesis")

    graph.add_edge("synthesis", "save")
    graph.add_edge("save", END)

    return graph.compile()


_graph = build_graph()


async def generate_daily_recommendation(
    user_id: str,
    for_date: date | None = None,
) -> dict:
    target_date = for_date or date.today()

    initial_state = OrchestratorState(
        user_context=UserContext(user_id=user_id, date=target_date)
    )

    result = await _graph.ainvoke(initial_state)

    # ainvoke retourne l'état final : OrchestratorState ou dict selon la version LangGraph
    if hasattr(result, "final_recommendation"):
        reco = result.final_recommendation
    else:
        reco = result.get("final_recommendation")

    if not reco:
        return {"error": "no_recommendation"}

    return {
        "content":       reco.content,
        "content_short": reco.content_short,
        "action_type":   reco.action_type,
        "agent_source":  reco.agent_source,
        "confidence":    reco.confidence,
    }
