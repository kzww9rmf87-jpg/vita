/**
 * Routes Daily Insight Engine.
 *
 * GET  /daily-insight/:date  — retourne l'insight du jour depuis la DB
 * POST /daily-insight/generate — déclenche la génération via l'ai-engine (idempotent)
 *
 * Le contenu brut (journal, check-in notes) ne transite jamais jusqu'au client.
 * Seule la synthèse interprétative produite par l'IA est exposée.
 *
 * Formats de date acceptés : YYYY-MM-DD
 * Date absente → aujourd'hui (UTC)
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { queryOne } from '../db.js'
import { requestDailyInsight, AIEngineError } from '../ai-client.js'

const DateParamSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
})

const GenerateBodySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
})

// Constantes SQL — colonnes explicites, pas de SELECT *
const SELECT_INSIGHT = `
  SELECT id::text     AS id,
         user_id::text AS user_id,
         date::text   AS date,
         climate,
         summary,
         drivers,
         reflection,
         question,
         created_at::text AS created_at
  FROM daily_insights
  WHERE user_id = $1 AND date = $2::date
`

interface InsightRow {
  id: string
  user_id: string
  date: string
  climate: string
  summary: string
  drivers: string[]
  reflection: string
  question: string
  created_at: string
}

function todayUTC(): string {
  return new Date().toISOString().split('T')[0]!
}

export const dailyInsightRoutes: FastifyPluginAsync = async (app) => {

  // GET /daily-insight/:date
  // Retourne l'insight stocké en DB pour la date donnée.
  // Retourne { available: false } si aucun insight n'a été généré.
  // Errors: 400 si format de date invalide
  // Auth: JWT requis
  app.get('/:date', async (req, reply) => {
    const parsed = DateParamSchema.safeParse(req.params)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const row = await queryOne<InsightRow>(SELECT_INSIGHT, [userId, parsed.data.date])
    if (!row) return reply.send({ available: false })
    return reply.send({ available: true, ...row })
  })

  // POST /daily-insight/generate
  // Demande à l'ai-engine de générer l'insight (idempotent).
  // Body optionnel: { date?: "YYYY-MM-DD" } — défaut : aujourd'hui
  // Erreur ai-engine → loguée, { available: false } retourné (pas de 500)
  // Auth: JWT requis
  app.post('/generate', async (req, reply) => {
    const parsed = GenerateBodySchema.safeParse(req.body ?? {})
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const targetDate = parsed.data.date ?? todayUTC()

    try {
      await requestDailyInsight(userId, targetDate)
    } catch (err) {
      if (err instanceof AIEngineError) {
        app.log.warn({ err, userId, targetDate }, 'AI engine unavailable for daily insight generation')
      } else {
        app.log.error({ err, userId, targetDate }, 'Unexpected error generating daily insight')
      }
    }

    const row = await queryOne<InsightRow>(SELECT_INSIGHT, [userId, targetDate])
    if (!row) return reply.send({ available: false })
    return reply.send({ available: true, ...row })
  })
}
