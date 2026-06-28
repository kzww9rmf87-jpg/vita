/**
 * Activité physique — routes data-service.
 *
 * CRUD complet : sessions, séries d'exercices, historique, édition, suppression.
 * Aucun calcul intelligent — fondation seulement (Sprint 7).
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

// ── Schémas ───────────────────────────────────────────────────────────────────

const ExerciseSetSchema = z.object({
  exerciseName: z.string().min(1).max(100),
  muscleGroups: z.array(z.string().max(50)).max(10).optional(),
  setNumber:    z.number().int().min(1).max(100),
  reps:         z.number().int().min(0).max(1000).optional(),
  weightKg:     z.number().min(0).max(1000).optional(),
  durationSec:  z.number().int().min(0).max(7200).optional(),
  restSec:      z.number().int().min(0).max(600).optional(),
  rpe:          z.number().int().min(1).max(10).optional(),
  notes:        z.string().max(500).optional(),
})

const ActivitySessionSchema = z.object({
  date:            z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startedAt:       z.string().datetime().optional(),
  endedAt:         z.string().datetime().optional(),
  activityName:    z.string().min(1).max(100),
  durationMinutes: z.number().int().min(0).max(600).optional(),
  caloriesBurned:  z.number().int().min(0).max(10000).optional(),
  hrAvgBpm:        z.number().int().min(30).max(250).optional(),
  hrMaxBpm:        z.number().int().min(30).max(250).optional(),
  rpe:             z.number().int().min(1).max(10).optional(),
  distanceMeters:  z.number().int().min(0).max(200000).optional(),
  steps:           z.number().int().min(0).max(100000).optional(),
  notes:           z.string().max(1000).optional(),
  source:          z.string().max(50).default('manual'),
  sets:            z.array(ExerciseSetSchema).max(200).optional(),
})

const ActivityPatchSchema = ActivitySessionSchema.partial().omit({ date: true, sets: true })

// ── Routes ────────────────────────────────────────────────────────────────────

export const activityRoutes: FastifyPluginAsync = async (app) => {

  // POST / — Créer une session d'activité
  app.post('/', async (req, reply) => {
    const parsed = ActivitySessionSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    const row = await queryOne<{ id: string }>(
      `INSERT INTO activity_sessions
         (user_id, date, started_at, ended_at, activity_name, duration_minutes,
          calories_burned, hr_avg_bpm, hr_max_bpm, rpe, distance_meters,
          steps, notes, completed, source)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,true,$14)
       RETURNING id`,
      [
        userId, body.date,
        body.startedAt ?? null, body.endedAt ?? null,
        body.activityName, body.durationMinutes ?? null,
        body.caloriesBurned ?? null, body.hrAvgBpm ?? null,
        body.hrMaxBpm ?? null, body.rpe ?? null,
        body.distanceMeters ?? null, body.steps ?? null,
        body.notes ?? null, body.source,
      ]
    )
    const sessionId = row!.id

    if (body.sets && body.sets.length > 0) {
      for (const set of body.sets) {
        await query(
          `INSERT INTO exercise_sets
             (session_id, exercise_name, muscle_groups, set_number, reps, weight_kg,
              duration_sec, rest_sec, rpe, notes)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
          [
            sessionId, set.exerciseName, set.muscleGroups ?? [],
            set.setNumber, set.reps ?? null, set.weightKg ?? null,
            set.durationSec ?? null, set.restSec ?? null,
            set.rpe ?? null, set.notes ?? null,
          ]
        )
      }
    }

    return reply.status(201).send({ id: sessionId })
  })

  // PATCH /:id — Modifier une session
  app.patch('/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const parsed = ActivityPatchSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }

    const existing = await queryOne(
      `SELECT id FROM activity_sessions WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!existing) return reply.status(404).send({ error: 'NOT_FOUND' })

    const body = parsed.data
    const fields: string[] = []
    const values: unknown[] = [id]
    let idx = 2

    const addField = (col: string, val: unknown) => {
      if (val !== undefined) { fields.push(`${col} = $${idx++}`); values.push(val) }
    }

    addField('activity_name',    body.activityName)
    addField('duration_minutes', body.durationMinutes)
    addField('calories_burned',  body.caloriesBurned)
    addField('hr_avg_bpm',       body.hrAvgBpm)
    addField('hr_max_bpm',       body.hrMaxBpm)
    addField('rpe',              body.rpe)
    addField('distance_meters',  body.distanceMeters)
    addField('steps',            body.steps)
    addField('notes',            body.notes)

    if (fields.length === 0) return reply.status(400).send({ error: 'NO_FIELDS' })

    await query(
      `UPDATE activity_sessions SET ${fields.join(', ')} WHERE id = $1`,
      values
    )
    return reply.status(200).send({ id })
  })

  // DELETE /:id — Supprimer une session (cascade sur exercise_sets)
  app.delete('/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const existing = await queryOne(
      `SELECT id FROM activity_sessions WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!existing) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM activity_sessions WHERE id = $1`, [id])
    return reply.status(204).send()
  })

  // GET /history — Historique des sessions
  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }
    const daysInt = Math.min(365, Math.max(1, parseInt(days) || 30))

    const sessions = await query(
      `SELECT id, date, activity_name, duration_minutes, calories_burned,
              hr_avg_bpm, rpe, distance_meters, steps, source, created_at
       FROM activity_sessions
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC, created_at DESC`,
      [userId, daysInt]
    )
    return reply.send(sessions)
  })

  // GET /session/:id/sets — Séries d'une session
  app.get('/session/:id/sets', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const session = await queryOne(
      `SELECT id FROM activity_sessions WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!session) return reply.status(404).send({ error: 'NOT_FOUND' })

    const sets = await query(
      `SELECT exercise_name, muscle_groups, set_number, reps, weight_kg, rpe, notes
       FROM exercise_sets WHERE session_id = $1
       ORDER BY exercise_name, set_number`,
      [id]
    )
    return reply.send(sets)
  })
}
