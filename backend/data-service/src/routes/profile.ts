import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

const ProfileUpdateSchema = z.object({
  firstName: z.string().min(1).max(50).optional(),
  birthYear: z.number().int().min(1920).max(2010).optional(),
  sex: z.enum(['male', 'female', 'other', 'prefer_not']).optional(),
  heightCm: z.number().min(100).max(250).optional(),
  primaryGoal: z.enum(['perform', 'lose_weight', 'recover', 'feel_better']).optional(),
  activityLevel: z.number().int().min(1).max(5).optional(),
  wakeTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  sleepTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  timezone: z.string().optional(),
})

const WeightSchema = z.object({
  weightKg: z.number().min(20).max(300),
  waistCm: z.number().min(30).max(200).optional(),
  bodyFatPct: z.number().min(1).max(70).optional(),
})

export const profileRoutes: FastifyPluginAsync = async (app) => {

  app.get('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const [profile, snapshot] = await Promise.all([
      queryOne(
        `SELECT up.*, u.email
         FROM user_profiles up
         JOIN users u ON u.id = up.user_id
         WHERE up.user_id = $1`,
        [userId]
      ),
      queryOne(
        `SELECT weight_kg, waist_cm, body_fat_pct, date
         FROM user_snapshots WHERE user_id = $1 ORDER BY date DESC LIMIT 1`,
        [userId]
      ),
    ])

    return reply.send({ profile, snapshot })
  })

  app.patch('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = ProfileUpdateSchema.parse(req.body)

    const fields: string[] = []
    const values: unknown[] = []
    let i = 1

    const mapping: Record<string, string> = {
      firstName: 'first_name',
      birthYear: 'birth_year',
      sex: 'sex',
      heightCm: 'height_cm',
      primaryGoal: 'primary_goal',
      activityLevel: 'activity_level',
      wakeTime: 'wake_time',
      sleepTime: 'sleep_time',
      timezone: 'timezone',
    }

    for (const [jsKey, dbCol] of Object.entries(mapping)) {
      if (body[jsKey as keyof typeof body] !== undefined) {
        fields.push(`${dbCol} = $${i++}`)
        values.push(body[jsKey as keyof typeof body])
      }
    }

    if (fields.length === 0) return reply.send({ updated: false })

    values.push(userId)
    await query(
      `UPDATE user_profiles SET ${fields.join(', ')}, updated_at = NOW()
       WHERE user_id = $${i}`,
      values
    )

    return reply.send({ updated: true })
  })

  app.post('/weight', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = WeightSchema.parse(req.body)
    const today = new Date().toISOString().split('T')[0]

    await query(
      `INSERT INTO user_snapshots (user_id, date, weight_kg, waist_cm, body_fat_pct)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id, date) DO UPDATE SET
         weight_kg = EXCLUDED.weight_kg,
         waist_cm = EXCLUDED.waist_cm,
         body_fat_pct = EXCLUDED.body_fat_pct`,
      [userId, today, body.weightKg, body.waistCm ?? null, body.bodyFatPct ?? null]
    )

    return reply.status(201).send({ date: today, weightKg: body.weightKg })
  })

  app.get('/onboarding-complete', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const profile = await queryOne<{ onboarding_done_at: string | null }>(
      `SELECT onboarding_done_at FROM user_profiles WHERE user_id = $1`,
      [userId]
    )
    return reply.send({ complete: !!profile?.onboarding_done_at })
  })

  app.post('/onboarding-complete', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    await query(
      `UPDATE user_profiles SET onboarding_done_at = NOW() WHERE user_id = $1`,
      [userId]
    )
    return reply.send({ success: true })
  })

  app.get('/export', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const [profile, sleep, activity, nutrition, checkins] = await Promise.all([
      queryOne(`SELECT * FROM user_profiles WHERE user_id = $1`, [userId]),
      query(`SELECT * FROM sleep_entries WHERE user_id = $1 ORDER BY date`, [userId]),
      query(`SELECT * FROM activity_sessions WHERE user_id = $1 ORDER BY date`, [userId]),
      query(`SELECT * FROM nutrition_daily WHERE user_id = $1 ORDER BY date`, [userId]),
      query(`SELECT * FROM daily_checkins WHERE user_id = $1 ORDER BY date`, [userId]),
    ])

    reply.header('Content-Disposition', 'attachment; filename="vita-export.json"')
    reply.header('Content-Type', 'application/json')

    return reply.send({
      exportedAt: new Date().toISOString(),
      profile,
      data: { sleep, activity, nutrition, checkins },
    })
  })
}
