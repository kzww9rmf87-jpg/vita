/**
 * Routes réflexion hebdomadaire.
 *
 * GET  /reflection/weekly — réflexion de la semaine courante (depuis DB)
 * POST /reflection/weekly — déclenche la génération via l'ai-engine,
 *                           puis retourne ce qui est en DB (idempotent)
 *
 * Le contenu sensible (journal brut) ne transite jamais ici.
 * Seul le texte de réflexion produit par l'IA est exposé au client.
 */
import type { FastifyPluginAsync } from 'fastify'
import { queryOne } from '../db.js'
import { requestWeeklyReflection, AIEngineError } from '../ai-client.js'

// Lundi de la semaine courante au format YYYY-MM-DD (UTC)
function currentWeekStart(): string {
  const now = new Date()
  const day = now.getUTCDay() // 0 = dimanche
  const diff = day === 0 ? -6 : 1 - day
  const monday = new Date(now)
  monday.setUTCDate(now.getUTCDate() + diff)
  return monday.toISOString().split('T')[0]!
}

interface ReflectionRow {
  id: string
  content: string
  period_start: string
  period_end: string
  themes: string[]
  question: string | null
  created_at: string
}

function rowToPayload(row: ReflectionRow) {
  return {
    available: true,
    id: row.id,
    content: row.content,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    themes: row.themes ?? [],
    question: row.question,
    createdAt: row.created_at,
  }
}

const SELECT_REFLECTION = `
  SELECT id, content,
         period_start::TEXT AS period_start,
         period_end::TEXT   AS period_end,
         themes,
         question,
         created_at
  FROM vita_reflections
  WHERE user_id = $1 AND period_start = $2::DATE
`

export const reflectionRoutes: FastifyPluginAsync = async (app) => {

  // GET /reflection/weekly
  // Lit la réflexion de la semaine courante directement depuis vita_reflections.
  // Retourne { available: false } si aucune n'a encore été générée.
  app.get('/weekly', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const weekStart = currentWeekStart()

    const row = await queryOne<ReflectionRow>(SELECT_REFLECTION, [userId, weekStart])
    if (!row) return reply.send({ available: false })
    return reply.send(rowToPayload(row))
  })

  // POST /reflection/weekly
  // Demande à l'ai-engine de générer la réflexion si elle n'existe pas encore.
  // Idempotent : si elle existe déjà, l'ai-engine retourne null et on lit la DB.
  // Erreur ai-engine → loguée, on retourne { available: false } plutôt que 500.
  app.post('/weekly', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const weekStart = currentWeekStart()

    try {
      await requestWeeklyReflection(userId, weekStart)
    } catch (err) {
      if (err instanceof AIEngineError) {
        app.log.warn({ err, userId }, 'AI engine unavailable for weekly reflection generation')
      } else {
        app.log.error({ err, userId }, 'Unexpected error generating weekly reflection')
      }
    }

    const row = await queryOne<ReflectionRow>(SELECT_REFLECTION, [userId, weekStart])
    if (!row) return reply.send({ available: false })
    return reply.send(rowToPayload(row))
  })
}
