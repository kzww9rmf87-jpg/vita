import type { FastifyPluginAsync, FastifyBaseLogger } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import { requestRecommendation, AIEngineError } from '../ai-client.js'
import { sendEvent, hasConnection } from '../sse-manager.js'

// Messages émis à l'utilisateur pendant que VITA génère sa recommandation.
// Ils reflètent le raisonnement réel de l'orchestrateur IA.
const THINKING_MESSAGES = [
  'Je relis nos échanges…',
  "J'analyse votre sommeil…",
  'Je compare avec vos habitudes…',
  "Je cherche ce qui aura le plus d'impact aujourd'hui…",
] as const

// Lance la génération de la recommandation en arrière-plan.
// Ne bloque jamais le handler du check-in.
function scheduleRecommendation(userId: string, log: FastifyBaseLogger): void {
  // setImmediate reporte l'exécution après la réponse HTTP — le check-in
  // retourne 201 avant même que cette fonction ne commence.
  setImmediate(() => {
    generateAndPushRecommendation(userId, log).catch((err) => {
      log.error({ err, userId }, 'Unhandled error in recommendation background job')
    })
  })
}

async function generateAndPushRecommendation(
  userId: string,
  log: FastifyBaseLogger
): Promise<void> {
  let messageIndex = 0

  // Émet le premier message immédiatement si une connexion SSE est ouverte
  if (hasConnection(userId)) {
    sendEvent(userId, 'thinking', { message: THINKING_MESSAGES[messageIndex++] })
  }

  // Émet les messages suivants toutes les 2.5s pendant que l'IA travaille
  const thinkingInterval = setInterval(() => {
    if (messageIndex < THINKING_MESSAGES.length) {
      sendEvent(userId, 'thinking', { message: THINKING_MESSAGES[messageIndex++] })
    }
  }, 2_500)

  try {
    const recommendation = await requestRecommendation(userId)
    clearInterval(thinkingInterval)

    // Persiste la recommandation du jour (ON CONFLICT : met à jour si déjà générée)
    await query(
      `INSERT INTO ai_recommendations
         (user_id, date, agent_source, content, action_type, priority)
       VALUES ($1, CURRENT_DATE, $2, $3, $4, 1)
       ON CONFLICT (user_id, date) DO UPDATE SET
         content     = EXCLUDED.content,
         agent_source = EXCLUDED.agent_source,
         action_type = EXCLUDED.action_type`,
      [userId, recommendation.agent_source, recommendation.content, recommendation.action_type ?? null]
    )

    // Pousse la recommandation vers l'iOS via SSE
    sendEvent(userId, 'recommendation', {
      content: recommendation.content,
      actionType: recommendation.action_type,
      agentSource: recommendation.agent_source,
      confidence: recommendation.confidence,
    })

    log.info({ userId, agentSource: recommendation.agent_source }, 'Recommendation generated and pushed')
  } catch (err) {
    clearInterval(thinkingInterval)

    const code = err instanceof AIEngineError ? err.code : 'RECOMMENDATION_FAILED'
    log.error({ err, userId, code }, 'Failed to generate recommendation')

    sendEvent(userId, 'error', { code })
  }
}

const MorningCheckinSchema = z.object({
  energy: z.number().int().min(1).max(5),
  mood: z.number().int().min(1).max(5),
  stress: z.number().int().min(1).max(5),
  painAreas: z.array(z.string()).max(10).optional(),
  painIntensity: z.number().int().min(0).max(10).optional(),
  specialEvent: z.string().max(500).optional(),
  durationSec: z.number().int().min(0).max(300).optional(),
})

const EveningCheckinSchema = z.object({
  energy: z.number().int().min(1).max(5),
  mood: z.number().int().min(1).max(5),
  motivation: z.number().int().min(1).max(5),
  concentration: z.number().int().min(1).max(5).optional(),
  notes: z.string().max(1000).optional(),
  durationSec: z.number().int().min(0).max(300).optional(),
})

export const checkinRoutes: FastifyPluginAsync = async (app) => {

  app.post('/morning', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = MorningCheckinSchema.parse(req.body)
    const today = new Date().toISOString().split('T')[0]

    const existing = await queryOne(
      `SELECT id FROM daily_checkins WHERE user_id = $1 AND date = $2 AND type = 'morning'`,
      [userId, today]
    )
    if (existing) {
      return reply.status(409).send({ error: 'MORNING_CHECKIN_EXISTS' })
    }

    const [checkin] = await query<{ id: string }>(
      `INSERT INTO daily_checkins
         (user_id, date, type, energy, mood, stress, pain_areas, pain_intensity, special_event, duration_sec)
       VALUES ($1, $2, 'morning', $3, $4, $5, $6, $7, $8, $9)
       RETURNING id`,
      [
        userId, today,
        body.energy, body.mood, body.stress,
        body.painAreas ?? [],
        body.painIntensity ?? 0,
        body.specialEvent ?? null,
        body.durationSec ?? null,
      ]
    )

    // Déclenche la génération en arrière-plan — ne bloque pas cette réponse
    scheduleRecommendation(userId, app.log)

    return reply.status(201).send({ id: checkin.id, date: today })
  })

  app.post('/evening', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = EveningCheckinSchema.parse(req.body)
    const today = new Date().toISOString().split('T')[0]

    const [checkin] = await query<{ id: string }>(
      `INSERT INTO daily_checkins
         (user_id, date, type, energy, mood, motivation, concentration, notes, duration_sec)
       VALUES ($1, $2, 'evening', $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      [
        userId, today,
        body.energy, body.mood, body.motivation,
        body.concentration ?? null,
        body.notes ?? null,
        body.durationSec ?? null,
      ]
    )

    return reply.status(201).send({ id: checkin.id, date: today })
  })

  app.get('/today', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const today = new Date().toISOString().split('T')[0]

    const checkins = await query(
      `SELECT type, energy, mood, stress, motivation, pain_areas, completed_at
       FROM daily_checkins
       WHERE user_id = $1 AND date = $2`,
      [userId, today]
    )
    return reply.send({ date: today, checkins })
  })

  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '14' } = req.query as { days?: string }

    const rows = await query(
      `SELECT date, type, energy, mood, stress, motivation, pain_areas
       FROM daily_checkins
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC, type ASC`,
      [userId, parseInt(days)]
    )
    return reply.send(rows)
  })
}

