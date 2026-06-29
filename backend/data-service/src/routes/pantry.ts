import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

const PantryItemSchema = z.object({
  ingredient_name: z.string().min(1).max(200),
  notes:           z.string().max(500).optional(),
})

export const pantryRoutes: FastifyPluginAsync = async (app) => {

  // GET / — Liste les items du garde-manger
  app.get('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const items = await query(
      `SELECT id, ingredient_name, notes, created_at
       FROM pantry_items WHERE user_id = $1 ORDER BY ingredient_name`,
      [userId]
    )
    return reply.send(items)
  })

  // POST / — Ajouter un ingrédient au garde-manger (ignore doublon silencieusement)
  app.post('/', async (req, reply) => {
    const parsed = PantryItemSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    const row = await queryOne<{ id: string }>(
      `INSERT INTO pantry_items (user_id, ingredient_name, notes)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, LOWER(ingredient_name)) DO UPDATE SET
         notes = EXCLUDED.notes
       RETURNING id`,
      [userId, body.ingredient_name.trim(), body.notes ?? null]
    )
    return reply.status(201).send({ id: row!.id })
  })

  // DELETE /:id
  app.delete('/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const item = await queryOne(
      `SELECT id FROM pantry_items WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!item) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM pantry_items WHERE id = $1`, [id])
    return reply.status(204).send()
  })
}
