import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

const SleepEntrySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  bedtime: z.string().datetime().optional(),
  wakeTime: z.string().datetime().optional(),
  durationMinutes: z.number().int().min(0).max(1440).optional(),
  qualityScore: z.number().int().min(1).max(5),
  awakenings: z.number().int().min(0).max(50).optional(),
  energyOnWake: z.number().int().min(1).max(5).optional(),
  hrvMs: z.number().min(0).max(200).optional(),
  rhrBpm: z.number().int().min(20).max(120).optional(),
  napDurationMin: z.number().int().min(0).max(180).optional(),
  source: z.enum(['manual', 'apple_health', 'google_fit', 'oura', 'whoop', 'garmin', 'polar']).default('manual'),
})

export const sleepRoutes: FastifyPluginAsync = async (app) => {

  app.post('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = SleepEntrySchema.parse(req.body)

    let durationMinutes = body.durationMinutes
    if (!durationMinutes && body.bedtime && body.wakeTime) {
      const diff = new Date(body.wakeTime).getTime() - new Date(body.bedtime).getTime()
      durationMinutes = Math.round(diff / 60000)
    }

    const rows_entry = await query<{ id: string }>(
      `INSERT INTO sleep_entries
         (user_id, date, bedtime, wake_time, duration_minutes, quality_score,
          awakenings, energy_on_wake, hrv_ms, rhr_bpm, nap_duration_min, source)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT (user_id, date) DO UPDATE SET
         bedtime = EXCLUDED.bedtime,
         wake_time = EXCLUDED.wake_time,
         duration_minutes = EXCLUDED.duration_minutes,
         quality_score = EXCLUDED.quality_score,
         awakenings = EXCLUDED.awakenings,
         energy_on_wake = EXCLUDED.energy_on_wake,
         hrv_ms = EXCLUDED.hrv_ms,
         rhr_bpm = EXCLUDED.rhr_bpm,
         nap_duration_min = EXCLUDED.nap_duration_min,
         source = EXCLUDED.source
       RETURNING id`,
      [
        userId, body.date,
        body.bedtime ?? null, body.wakeTime ?? null,
        durationMinutes ?? null, body.qualityScore,
        body.awakenings ?? 0, body.energyOnWake ?? null,
        body.hrvMs ?? null, body.rhrBpm ?? null,
        body.napDurationMin ?? 0, body.source,
      ]
    )

    return reply.status(201).send({ id: rows_entry[0]!.id })
  })

  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }

    const rows = await query(
      `SELECT date, duration_minutes, quality_score, awakenings, energy_on_wake, hrv_ms, source
       FROM sleep_entries
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC`,
      [userId, parseInt(days)]
    )

    const stats = await queryOne<{
      avg_duration: string
      avg_quality: string
      avg_awakenings: string
      sleep_debt_days: string
    }>(
      `SELECT
         AVG(duration_minutes)::NUMERIC(5,1) AS avg_duration,
         AVG(quality_score)::NUMERIC(3,2) AS avg_quality,
         AVG(awakenings)::NUMERIC(3,1) AS avg_awakenings,
         COUNT(*) FILTER (WHERE duration_minutes < 360) AS sleep_debt_days
       FROM sleep_entries
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT`,
      [userId, parseInt(days)]
    )

    return reply.send({ entries: rows, stats })
  })

  app.get('/latest', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const entry = await queryOne(
      `SELECT * FROM sleep_entries WHERE user_id = $1 ORDER BY date DESC LIMIT 1`,
      [userId]
    )
    return reply.send(entry ?? null)
  })
}
