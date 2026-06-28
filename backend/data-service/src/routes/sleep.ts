/**
 * Sommeil — routes data-service.
 *
 * CRUD complet : création (idempotente par date), historique, latest, édition, suppression.
 * Aucun calcul intelligent — fondation seulement (Sprint 7).
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

const SleepEntrySchema = z.object({
  date:            z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  bedtime:         z.string().datetime().optional(),
  wakeTime:        z.string().datetime().optional(),
  durationMinutes: z.number().int().min(0).max(1440).optional(),
  qualityScore:    z.number().int().min(1).max(5),
  awakenings:      z.number().int().min(0).max(50).optional(),
  energyOnWake:    z.number().int().min(1).max(5).optional(),
  napDurationMin:  z.number().int().min(0).max(180).optional(),
  notes:           z.string().max(1000).optional(),
  source:          z.enum(['manual', 'apple_health', 'google_fit', 'oura', 'whoop', 'garmin', 'polar']).default('manual'),
})

const SleepPatchSchema = SleepEntrySchema.partial().omit({ date: true })

export const sleepRoutes: FastifyPluginAsync = async (app) => {

  // POST / — Créer ou mettre à jour une entrée sommeil (idempotente par date)
  app.post('/', async (req, reply) => {
    const parsed = SleepEntrySchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    let durationMinutes = body.durationMinutes
    if (!durationMinutes && body.bedtime && body.wakeTime) {
      const diff = new Date(body.wakeTime).getTime() - new Date(body.bedtime).getTime()
      durationMinutes = Math.round(diff / 60000)
    }

    const row = await queryOne<{ id: string }>(
      `INSERT INTO sleep_entries
         (user_id, date, bedtime, wake_time, duration_minutes, quality_score,
          awakenings, energy_on_wake, nap_duration_min, notes, source)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (user_id, date) DO UPDATE SET
         bedtime          = EXCLUDED.bedtime,
         wake_time        = EXCLUDED.wake_time,
         duration_minutes = EXCLUDED.duration_minutes,
         quality_score    = EXCLUDED.quality_score,
         awakenings       = EXCLUDED.awakenings,
         energy_on_wake   = EXCLUDED.energy_on_wake,
         nap_duration_min = EXCLUDED.nap_duration_min,
         notes            = EXCLUDED.notes,
         source           = EXCLUDED.source
       RETURNING id`,
      [
        userId, body.date,
        body.bedtime ?? null, body.wakeTime ?? null,
        durationMinutes ?? null, body.qualityScore,
        body.awakenings ?? 0, body.energyOnWake ?? null,
        body.napDurationMin ?? 0, body.notes ?? null,
        body.source,
      ]
    )
    return reply.status(201).send({ id: row!.id })
  })

  // PATCH /:date — Modifier une entrée existante
  app.patch('/:date', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { date } = req.params as { date: string }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return reply.status(400).send({ error: 'INVALID_DATE' })
    }

    const parsed = SleepPatchSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }

    const existing = await queryOne(
      `SELECT id FROM sleep_entries WHERE user_id = $1 AND date = $2`,
      [userId, date]
    )
    if (!existing) return reply.status(404).send({ error: 'NOT_FOUND' })

    const body = parsed.data
    const fields: string[] = []
    const values: unknown[] = [userId, date]
    let idx = 3

    const addField = (col: string, val: unknown) => {
      if (val !== undefined) { fields.push(`${col} = $${idx++}`); values.push(val) }
    }

    addField('bedtime',          body.bedtime)
    addField('wake_time',        body.wakeTime)
    addField('duration_minutes', body.durationMinutes)
    addField('quality_score',    body.qualityScore)
    addField('awakenings',       body.awakenings)
    addField('energy_on_wake',   body.energyOnWake)
    addField('nap_duration_min', body.napDurationMin)
    addField('notes',            body.notes)
    addField('source',           body.source)

    if (fields.length === 0) return reply.status(400).send({ error: 'NO_FIELDS' })

    await query(
      `UPDATE sleep_entries SET ${fields.join(', ')} WHERE user_id = $1 AND date = $2`,
      values
    )
    return reply.status(200).send({ date })
  })

  // DELETE /:date — Supprimer une entrée
  app.delete('/:date', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { date } = req.params as { date: string }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return reply.status(400).send({ error: 'INVALID_DATE' })
    }

    await query(
      `DELETE FROM sleep_entries WHERE user_id = $1 AND date = $2`,
      [userId, date]
    )
    return reply.status(204).send()
  })

  // GET /history — Historique (30 jours par défaut)
  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }
    const daysInt = Math.min(365, Math.max(1, parseInt(days) || 30))

    const entries = await query(
      `SELECT date, bedtime, wake_time, duration_minutes, quality_score,
              awakenings, energy_on_wake, nap_duration_min, notes, source
       FROM sleep_entries
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC`,
      [userId, daysInt]
    )
    return reply.send(entries)
  })

  // GET /latest — Dernière entrée
  app.get('/latest', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const entry = await queryOne(
      `SELECT date, bedtime, wake_time, duration_minutes, quality_score,
              awakenings, energy_on_wake, nap_duration_min, notes, source
       FROM sleep_entries WHERE user_id = $1 ORDER BY date DESC LIMIT 1`,
      [userId]
    )
    return reply.send(entry ?? null)
  })
}
