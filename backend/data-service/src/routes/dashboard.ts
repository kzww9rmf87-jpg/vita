import type { FastifyPluginAsync } from 'fastify'
import { query, queryOne } from '../db.js'

export const dashboardRoutes: FastifyPluginAsync = async (app) => {

  // Vue consolidée de la semaine courante
  app.get('/week', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const [sleep, activity, nutrition, checkin, recommendation] = await Promise.all([
      queryOne(
        `SELECT
           AVG(duration_minutes)::FLOAT8 AS avg_duration,
           AVG(quality_score)::FLOAT8    AS avg_quality,
           COUNT(*)::INT                 AS days_logged
         FROM sleep_entries
         WHERE user_id = $1 AND date >= CURRENT_DATE - 7`,
        [userId]
      ),
      queryOne(
        `SELECT
           COUNT(*)::INT             AS sessions,
           SUM(duration_minutes)::INT AS total_minutes,
           AVG(rpe)::FLOAT8          AS avg_rpe
         FROM activity_sessions
         WHERE user_id = $1 AND date >= CURRENT_DATE - 7`,
        [userId]
      ),
      queryOne(
        `SELECT
           AVG(calories)::INT           AS avg_calories,
           AVG(protein_g)::FLOAT8       AS avg_protein,
           AVG(adherence_score)::FLOAT8 AS avg_adherence
         FROM nutrition_daily
         WHERE user_id = $1 AND date >= CURRENT_DATE - 7`,
        [userId]
      ),
      queryOne(
        `SELECT
           AVG(energy)::FLOAT8          AS avg_energy,
           AVG(mood)::FLOAT8            AS avg_mood,
           AVG(stress)::FLOAT8          AS avg_stress,
           COUNT(DISTINCT date)::INT    AS checkin_days
         FROM daily_checkins
         WHERE user_id = $1 AND date >= CURRENT_DATE - 7 AND type = 'morning'`,
        [userId]
      ),
      queryOne(
        `SELECT content, action_type, actions_json AS actions, created_at
         FROM ai_recommendations
         WHERE user_id = $1 AND date = CURRENT_DATE AND dismissed = false
         ORDER BY created_at DESC LIMIT 1`,
        [userId]
      ),
    ])

    return reply.send({
      date: new Date().toISOString().split('T')[0],
      sleep,
      activity,
      nutrition,
      checkin,
      recommendation,
    })
  })

  // Données pour les graphiques de tendances
  app.get('/trends', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }
    const n = Math.min(90, Math.max(7, parseInt(days)))

    const [sleepTrend, weightTrend, energyTrend, activityTrend] = await Promise.all([
      query(
        `SELECT date, duration_minutes, quality_score
         FROM sleep_entries WHERE user_id = $1 AND date >= CURRENT_DATE - $2
         ORDER BY date ASC`,
        [userId, n]
      ),
      query(
        `SELECT date, weight_kg FROM user_snapshots
         WHERE user_id = $1 AND date >= CURRENT_DATE - $2 AND weight_kg IS NOT NULL
         ORDER BY date ASC`,
        [userId, n]
      ),
      query(
        `SELECT date, energy, mood, stress
         FROM daily_checkins
         WHERE user_id = $1 AND date >= CURRENT_DATE - $2 AND type = 'morning'
         ORDER BY date ASC`,
        [userId, n]
      ),
      query(
        `SELECT date, SUM(duration_minutes) AS minutes, COUNT(*) AS sessions
         FROM activity_sessions
         WHERE user_id = $1 AND date >= CURRENT_DATE - $2
         GROUP BY date ORDER BY date ASC`,
        [userId, n]
      ),
    ])

    return reply.send({ sleepTrend, weightTrend, energyTrend, activityTrend })
  })

  // Recommandation du jour — fallback REST pour les clients sans SSE
  // ou pour récupérer la recommandation après un redémarrage de l'app.
  app.get('/recommendation', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const recommendation = await queryOne<{
      content: string
      action_type: string | null
      agent_source: string
      actions: string[] | null
      created_at: string
    }>(
      `SELECT content, action_type, agent_source, actions_json AS actions, created_at
       FROM ai_recommendations
       WHERE user_id = $1 AND date = CURRENT_DATE AND dismissed = false
       ORDER BY created_at DESC LIMIT 1`,
      [userId]
    )

    if (!recommendation) {
      return reply.send({ ready: false })
    }

    return reply.send({
      ready: true,
      content: recommendation.content,
      actionType: recommendation.action_type,
      agentSource: recommendation.agent_source,
      actions: recommendation.actions ?? [],
      createdAt: recommendation.created_at,
    })
  })

  // Patterns détectés par l'IA
  app.get('/patterns', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const patterns = await query(
      `SELECT pattern_type, description_user AS description, confidence, direction, first_detected_at
       FROM user_patterns
       WHERE user_id = $1 AND active = true AND shown_to_user = false
       ORDER BY confidence DESC LIMIT 5`,
      [userId]
    )

    if (patterns.length > 0) {
      await query(
        `UPDATE user_patterns SET shown_to_user = true
         WHERE user_id = $1 AND active = true AND shown_to_user = false`,
        [userId]
      )
    }

    return reply.send(patterns)
  })
}

