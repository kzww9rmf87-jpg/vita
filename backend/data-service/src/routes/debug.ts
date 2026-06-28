/**
 * Routes de débogage — JAMAIS enregistrées en production.
 *
 * L'enregistrement conditionnel dans index.ts garantit que ces routes
 * sont absentes des builds production (NODE_ENV === 'production').
 *
 * GET /debug/memories — liste les 100 dernières mémoires longue durée
 *   de l'utilisateur authentifié, avec tous les champs techniques.
 *   Réservé à la bêta et au développement.
 */
import type { FastifyPluginAsync } from 'fastify'
import { query } from '../db.js'

interface MemoryDebugRow {
  id: string
  type: string
  source: string
  importance: number
  confidence: number
  last_seen: Date
  created_at: Date
  updated_at: Date
  summary: string
}

export const debugRoutes: FastifyPluginAsync = async (app) => {

  // GET /debug/memories
  // Auth : JWT requis (hook global)
  // Limit : 100 max — immuable, pas de pagination intentionnelle
  app.get('/memories', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const memories = await query<MemoryDebugRow>(
      `SELECT id, type, source,
              importance::INT      AS importance,
              confidence::FLOAT8   AS confidence,
              last_seen,
              created_at,
              updated_at,
              summary
       FROM vita_long_memories
       WHERE user_id = $1
       ORDER BY last_seen DESC
       LIMIT 100`,
      [userId]
    )

    return reply.send({ memories, count: memories.length })
  })
}
