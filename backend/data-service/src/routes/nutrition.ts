import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

const NutritionDailySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  calories: z.number().int().min(0).max(10000).optional(),
  proteinG: z.number().min(0).max(1000).optional(),
  carbsG: z.number().min(0).max(2000).optional(),
  fatG: z.number().min(0).max(1000).optional(),
  fiberG: z.number().min(0).max(200).optional(),
  waterMl: z.number().int().min(0).max(10000).optional(),
  alcoholG: z.number().min(0).max(500).optional(),
  caffeineMg: z.number().int().min(0).max(3000).optional(),
  sodiumMg: z.number().int().min(0).max(20000).optional(),
  supplements: z.array(z.string()).optional(),
  notes: z.string().max(1000).optional(),
})

export const nutritionRoutes: FastifyPluginAsync = async (app) => {

  app.post('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const body = NutritionDailySchema.parse(req.body)

    const profile = await queryOne<{ weight_kg: number }>(
      `SELECT us.weight_kg FROM user_snapshots us
       WHERE us.user_id = $1 ORDER BY date DESC LIMIT 1`,
      [userId]
    )

    const qualityScore = computeQualityScore(body)
    const adherenceScore = await computeAdherenceScore(userId, body.proteinG, body.calories, profile?.weight_kg)

    await query(
      `INSERT INTO nutrition_daily
         (user_id, date, calories, protein_g, carbs_g, fat_g, fiber_g,
          water_ml, alcohol_g, caffeine_mg, sodium_mg, quality_score,
          adherence_score, supplements, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       ON CONFLICT (user_id, date) DO UPDATE SET
         calories = EXCLUDED.calories,
         protein_g = EXCLUDED.protein_g,
         carbs_g = EXCLUDED.carbs_g,
         fat_g = EXCLUDED.fat_g,
         fiber_g = EXCLUDED.fiber_g,
         water_ml = EXCLUDED.water_ml,
         alcohol_g = EXCLUDED.alcohol_g,
         caffeine_mg = EXCLUDED.caffeine_mg,
         sodium_mg = EXCLUDED.sodium_mg,
         quality_score = EXCLUDED.quality_score,
         adherence_score = EXCLUDED.adherence_score,
         supplements = EXCLUDED.supplements,
         notes = EXCLUDED.notes`,
      [
        userId, body.date,
        body.calories ?? null, body.proteinG ?? null,
        body.carbsG ?? null, body.fatG ?? null,
        body.fiberG ?? null, body.waterMl ?? null,
        body.alcoholG ?? null, body.caffeineMg ?? null,
        body.sodiumMg ?? null, qualityScore, adherenceScore,
        body.supplements ?? [], body.notes ?? null,
      ]
    )

    return reply.status(201).send({ date: body.date, qualityScore, adherenceScore })
  })

  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }

    const rows = await query(
      `SELECT date, calories, protein_g, carbs_g, fat_g, fiber_g,
              water_ml, alcohol_g, caffeine_mg, quality_score, adherence_score
       FROM nutrition_daily
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC`,
      [userId, parseInt(days)]
    )

    const stats = await queryOne(
      `SELECT
         AVG(calories)::INT AS avg_calories,
         AVG(protein_g)::NUMERIC(5,1) AS avg_protein,
         AVG(adherence_score)::NUMERIC(3,2) AS avg_adherence,
         COUNT(*) FILTER (WHERE alcohol_g > 10) AS alcohol_days,
         AVG(water_ml)::INT AS avg_water
       FROM nutrition_daily
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT`,
      [userId, parseInt(days)]
    )

    return reply.send({ entries: rows, stats })
  })
}

function computeQualityScore(data: z.infer<typeof NutritionDailySchema>): number {
  let score = 5.0

  // Bonus fibres
  if ((data.fiberG ?? 0) >= 25) score += 1.5
  else if ((data.fiberG ?? 0) >= 15) score += 0.5

  // Pénalité alcool
  if ((data.alcoholG ?? 0) > 20) score -= 2
  else if ((data.alcoholG ?? 0) > 10) score -= 1

  // Bonus hydratation
  if ((data.waterMl ?? 0) >= 2000) score += 0.5

  // Pénalité sodium excessif
  if ((data.sodiumMg ?? 0) > 3000) score -= 0.5

  // Bonus protéines adéquates
  if ((data.proteinG ?? 0) >= 120) score += 1

  return Math.max(0, Math.min(10, Math.round(score * 10) / 10))
}

async function computeAdherenceScore(
  userId: string,
  proteinG?: number,
  calories?: number,
  weightKg?: number
): Promise<number> {
  const proteinTarget = (weightKg ?? 75) * 1.8
  const calorieTarget = 2200

  let score = 0
  let checks = 0

  if (proteinG !== undefined) {
    checks++
    if (proteinG >= proteinTarget * 0.9) score++
  }
  if (calories !== undefined) {
    checks++
    const inRange = calories >= calorieTarget * 0.85 && calories <= calorieTarget * 1.15
    if (inRange) score++
  }

  return checks === 0 ? 0.5 : score / checks
}
