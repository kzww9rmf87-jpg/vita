/**
 * Première Rencontre — routes data-service.
 *
 * La Première Rencontre est une conversation naturelle et profonde entre VITA
 * et l'utilisateur, pilotée par l'AI Engine. Ce n'est pas un onboarding.
 *
 * Routes :
 *   GET  /first-encounter/session    → état courant de la session
 *   POST /first-encounter/start      → démarre la conversation
 *   POST /first-encounter/message    → envoie un message utilisateur
 *   POST /first-encounter/correct    → corrige le portrait
 *
 * Auth : JWT obligatoire (hook global de index.ts).
 * Erreurs AI Engine : gracieuses — jamais de 500 propagé à l'iOS.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import {
  getFirstEncounterSession,
  startFirstEncounter,
  sendFirstEncounterMessage,
  correctFirstEncounterPortrait,
  AIEngineError,
} from '../ai-client.js'

const MessageBodySchema = z.object({
  content: z.string().min(1, 'content ne peut pas être vide').max(2000),
})

const CorrectionBodySchema = z.object({
  correction: z.string().min(1, 'correction ne peut pas être vide').max(2000),
})

export const firstEncounterRoutes: FastifyPluginAsync = async (app) => {

  // GET /first-encounter/session
  // Retourne l'état courant : not_started | in_progress (+ exchanges) | completed (+ portrait)
  // Auth: JWT requis
  app.get('/session', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    try {
      const state = await getFirstEncounterSession(userId)
      return reply.send(state)
    } catch (err) {
      if (err instanceof AIEngineError) {
        req.log.warn({ userId, err }, 'first-encounter session fetch failed')
        return reply.send({ status: 'not_started' })
      }
      throw err
    }
  })

  // POST /first-encounter/start
  // Démarre la Première Rencontre et retourne le message d'ouverture de VITA.
  // Idempotent : si déjà démarrée, retourne l'état courant.
  // Auth: JWT requis
  app.post('/start', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    try {
      const result = await startFirstEncounter(userId)
      return reply.status(201).send(result)
    } catch (err) {
      if (err instanceof AIEngineError) {
        req.log.warn({ userId, err }, 'first-encounter start failed')
        return reply.status(503).send({ error: 'SERVICE_UNAVAILABLE' })
      }
      throw err
    }
  })

  // POST /first-encounter/message
  // Body: { content: string }
  // Retourne: { vita_response, topic, exchange_number, is_complete, portrait? }
  // Auth: JWT requis
  app.post('/message', async (req, reply) => {
    const parsed = MessageBodySchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({
        error: 'VALIDATION_ERROR',
        details: parsed.error.flatten(),
      })
    }

    const userId = (req.user as { sub: string }).sub
    const { content } = parsed.data

    try {
      const result = await sendFirstEncounterMessage(userId, content)
      return reply.send(result)
    } catch (err) {
      if (err instanceof AIEngineError) {
        req.log.warn({ userId, err }, 'first-encounter message failed')
        return reply.status(503).send({ error: 'SERVICE_UNAVAILABLE' })
      }
      throw err
    }
  })

  // POST /first-encounter/correct
  // Body: { correction: string }
  // Retourne: { portrait: string }
  // Auth: JWT requis
  app.post('/correct', async (req, reply) => {
    const parsed = CorrectionBodySchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({
        error: 'VALIDATION_ERROR',
        details: parsed.error.flatten(),
      })
    }

    const userId = (req.user as { sub: string }).sub
    const { correction } = parsed.data

    try {
      const result = await correctFirstEncounterPortrait(userId, correction)
      return reply.send(result)
    } catch (err) {
      if (err instanceof AIEngineError) {
        req.log.warn({ userId, err }, 'first-encounter correction failed')
        return reply.status(503).send({ error: 'SERVICE_UNAVAILABLE' })
      }
      throw err
    }
  })
}
