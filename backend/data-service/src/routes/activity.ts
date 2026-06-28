import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

const ExerciseSetSchema = z.object({
  exerciseName: z.string().min(1).max(100),
  muscleGroups: z.array(z.string()).optional(),
  setNumber: z.number().int().min(1),
  reps: z.number().int().min(0).optional(),
  weightKg: z.number().min(0).max(1000).optional(),
  durationSec: z.number().int().min(0).optional(),
  restSec: z.number().int().min(0).optional(),
  tempo: z.string().max(20).optional(),
  tutSec: z.number().int().min(0).optional(),
  rpe: z.number().int().min(1).max(10).optional(),
  notes: z.string().max(500).optional(),
})

const ActivitySessionSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startedAt: z.string().datetime().optional(),
  endedAt: z.string().datetime().optional(),
  activityName: z.string().min(1).max(100),
  durationMinutes: z.number().int().min(0).max(600).optional(),
  caloriesBurned: z.number().int().min(0).optional(),
  hrAvgBpm: z.number().int().min(30).max(250).optional(),
  hrMaxBpm: z.number().int().min(30).max(250).optional(),
  rpe: z.number().int().min(1).max(10).optional(),
  distanceMeters: z.number().int().min(0).optional(),
  steps: z.number().int().min(0).optional(),
  notes: z.string().max(1000).optional(),
  planned: z.boolean().default(false),
  source: z.string().default('manual'),
  sets: z.array(ExerciseSetSchema).optional(),
})

export const activityRoutes: FastifyPluginAsync = async (app) => {

  app.post('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = ActivitySessionSchema.parse(req.body)

    const rows_session = await query<{ id: string }>(
      `INSERT INTO activity_sessions
         (user_id, date, started_at, ended_at, activity_name, duration_minutes,
          calories_burned, hr_avg_bpm, hr_max_bpm, rpe, distance_meters,
          steps, notes, planned, completed, source)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,true,$15)
       RETURNING id`,
      [
        userId, body.date,
        body.startedAt ?? null, body.endedAt ?? null,
        body.activityName, body.durationMinutes ?? null,
        body.caloriesBurned ?? null, body.hrAvgBpm ?? null,
        body.hrMaxBpm ?? null, body.rpe ?? null,
        body.distanceMeters ?? null, body.steps ?? null,
        body.notes ?? null, body.planned, body.source,
      ]
    )

    if (body.sets && body.sets.length > 0) {
      for (const set of body.sets) {
        await query(
          `INSERT INTO exercise_sets
             (session_id, exercise_name, muscle_groups, set_number, reps, weight_kg,
              duration_sec, rest_sec, tempo, tut_sec, rpe, notes)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
          [
            rows_session[0]!.id, set.exerciseName, set.muscleGroups ?? [],
            set.setNumber, set.reps ?? null, set.weightKg ?? null,
            set.durationSec ?? null, set.restSec ?? null,
            set.tempo ?? null, set.tutSec ?? null,
            set.rpe ?? null, set.notes ?? null,
          ]
        )
      }
    }

    return reply.status(201).send({ id: rows_session[0]!.id })
  })

  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }

    const sessions = await query(
      `SELECT id, date, activity_name, duration_minutes, calories_burned,
              hr_avg_bpm, rpe, distance_meters, steps, source
       FROM activity_sessions
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC`,
      [userId, parseInt(days)]
    )
    return reply.send(sessions)
  })

  app.get('/session/:id/sets', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const session = await queryOne(
      `SELECT id FROM activity_sessions WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!session) return reply.status(404).send({ error: 'NOT_FOUND' })

    const sets = await query(
      `SELECT exercise_name, set_number, reps, weight_kg, rpe, tut_sec, notes
       FROM exercise_sets WHERE session_id = $1
       ORDER BY exercise_name, set_number`,
      [id]
    )
    return reply.send(sets)
  })

  app.get('/progression/:exercise', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { exercise } = req.params as { exercise: string }

    const rows = await query(
      `SELECT
         act.date,
         MAX(es.weight_kg) AS max_weight,
         SUM(es.reps * es.weight_kg) AS total_volume,
         AVG(es.rpe) AS avg_rpe
       FROM exercise_sets es
       JOIN activity_sessions act ON act.id = es.session_id
       WHERE act.user_id = $1
         AND LOWER(es.exercise_name) = LOWER($2)
         AND act.date >= CURRENT_DATE - 90
       GROUP BY act.date
       ORDER BY act.date ASC`,
      [userId, exercise]
    )
    return reply.send(rows)
  })

  app.get('/weekly-volume', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const rows = await query(
      `SELECT
         DATE_TRUNC('week', date) AS week,
         SUM(duration_minutes) AS total_minutes,
         COUNT(*) AS sessions,
         SUM(calories_burned) AS total_calories,
         AVG(rpe) AS avg_rpe
       FROM activity_sessions
       WHERE user_id = $1 AND date >= CURRENT_DATE - 90
       GROUP BY week
       ORDER BY week ASC`,
      [userId]
    )
    return reply.send(rows)
  })
}

