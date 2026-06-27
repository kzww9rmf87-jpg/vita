// Route POST /chat — proxy vers l'ai-engine.
//
// Ce handler est intentionnellement mince : il valide l'input,
// transmet à l'ai-engine, et propage la réponse ou l'erreur.
// Toute la logique de conversation est dans l'ai-engine.
//
// Contrat iOS → data-service :
//   Body : { message: string, conversation_id?: string }
//   Response : { conversation_id: string, response: string, tokens_used?: number }
//   (L'iOS décode en camelCase via JSONDecoder.vita.keyDecodingStrategy = .convertFromSnakeCase)

import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { sendChatMessage, AIEngineError } from '../ai-client.js'

const ChatSchema = z.object({
  message: z.string().min(1).max(2000),
  conversationId: z.string().uuid().optional(),
})

export const chatRoutes: FastifyPluginAsync = async (app) => {

  // POST /chat
  // Body : ChatSchema
  // Returns : { conversation_id, response, tokens_used }
  // Errors : 400 validation, 429 rate limit ai-engine, 502/504 ai-engine unreachable
  app.post('/', async (req, reply) => {
    const result = ChatSchema.safeParse(req.body)
    if (!result.success) {
      return reply.status(400).send({
        error: 'VALIDATION_ERROR',
        details: result.error.flatten(),
      })
    }

    const userId = (req.user as { sub: string }).sub
    const { message, conversationId } = result.data

    try {
      const aiResponse = await sendChatMessage(userId, message, conversationId)
      return reply.send(aiResponse)
    } catch (err) {
      if (err instanceof AIEngineError) {
        // Propage le code HTTP de l'ai-engine avec le code métier
        const status = err.status === 401 ? 503 : err.status
        return reply.status(status).send({ error: err.code })
      }
      app.log.error({ err, userId }, 'Unexpected error in POST /chat')
      return reply.status(500).send({ error: 'INTERNAL_ERROR' })
    }
  })
}
