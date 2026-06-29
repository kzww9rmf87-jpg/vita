/**
 * Profil nutritionnel utilisateur.
 *
 * Le profil sert à personnaliser la planification IA.
 * Ces données ne sont JAMAIS utilisées pour juger ou évaluer l'utilisateur.
 * Les cibles sont des orientations internes de planification — pas des objectifs à atteindre.
 * FOUNDING_PRINCIPLES.md §7 : "Jamais un journal de calories", "Aucun jugement alimentaire".
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import { calculateNutritionTargets } from '../ai-client.js'

// ── Schéma de validation ──────────────────────────────────────────────────────

const NutritionProfileSchema = z.object({
  objective:           z.enum(['maintain', 'lose', 'gain', 'recompose']).default('maintain'),
  weight_kg:           z.number().positive().max(500).optional(),
  height_cm:           z.number().int().positive().max(300).optional(),
  age:                 z.number().int().min(10).max(120).optional(),
  sex:                 z.enum(['male', 'female', 'other']).optional(),
  activity_level:      z.enum(['sedentary', 'light', 'moderate', 'active', 'very_active']).default('moderate'),
  meals_per_day:       z.number().int().min(1).max(6).default(3),
  batch_cooking:       z.boolean().default(false),
  cook_time_available: z.enum(['minimal', 'moderate', 'generous']).optional(),
  budget:              z.enum(['low', 'medium', 'high']).optional(),
  allergies:           z.array(z.string().max(100)).max(20).default([]),
  intolerances:        z.array(z.string().max(100)).max(20).default([]),
  excluded_foods:      z.array(z.string().max(100)).max(50).default([]),
  preferred_cuisines:  z.array(z.string().max(100)).max(20).default([]),
})

type ProfileBody = z.infer<typeof NutritionProfileSchema>

// ── Routes ────────────────────────────────────────────────────────────────────

export const nutritionProfileRoutes: FastifyPluginAsync = async (app) => {

  // GET /nutrition/profile — Lire le profil courant
  app.get('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const profile = await queryOne(
      `SELECT id, objective,
              weight_kg::FLOAT    AS weight_kg,
              height_cm, age, sex,
              activity_level, meals_per_day, batch_cooking,
              cook_time_available, budget,
              allergies, intolerances, excluded_foods, preferred_cuisines,
              target_calories,
              target_protein_g::FLOAT AS target_protein_g,
              target_carbs_g::FLOAT   AS target_carbs_g,
              target_fat_g::FLOAT     AS target_fat_g,
              target_fiber_g::FLOAT   AS target_fiber_g,
              created_at, updated_at
       FROM nutrition_profiles
       WHERE user_id = $1`,
      [userId]
    )
    if (!profile) return reply.status(404).send({ error: 'NOT_FOUND' })
    return reply.send(profile)
  })

  // POST /nutrition/profile — Créer ou mettre à jour le profil (upsert)
  app.post('/', async (req, reply) => {
    const parsed = NutritionProfileSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body: ProfileBody = parsed.data

    // Calculer les cibles via l'ai-engine (déterministe — aucun appel Claude)
    let targets: { target_calories: number | null; target_protein_g: number | null;
                   target_carbs_g: number | null; target_fat_g: number | null; target_fiber_g: number | null } =
      { target_calories: null, target_protein_g: null,
        target_carbs_g: null, target_fat_g: null, target_fiber_g: null }

    if (body.weight_kg && body.height_cm && body.age && body.sex) {
      try {
        targets = await calculateNutritionTargets({
          objective:      body.objective,
          weight_kg:      body.weight_kg,
          height_cm:      body.height_cm,
          age:            body.age,
          sex:            body.sex,
          activity_level: body.activity_level,
        })
      } catch {
        // Le calcul des cibles est optionnel — on continue sans si l'ai-engine est down
      }
    }

    const row = await queryOne<{ id: string }>(
      `INSERT INTO nutrition_profiles
         (user_id, objective, weight_kg, height_cm, age, sex,
          activity_level, meals_per_day, batch_cooking,
          cook_time_available, budget,
          allergies, intolerances, excluded_foods, preferred_cuisines,
          target_calories, target_protein_g, target_carbs_g, target_fat_g, target_fiber_g)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
       ON CONFLICT (user_id) DO UPDATE SET
         objective          = EXCLUDED.objective,
         weight_kg          = EXCLUDED.weight_kg,
         height_cm          = EXCLUDED.height_cm,
         age                = EXCLUDED.age,
         sex                = EXCLUDED.sex,
         activity_level     = EXCLUDED.activity_level,
         meals_per_day      = EXCLUDED.meals_per_day,
         batch_cooking      = EXCLUDED.batch_cooking,
         cook_time_available = EXCLUDED.cook_time_available,
         budget             = EXCLUDED.budget,
         allergies          = EXCLUDED.allergies,
         intolerances       = EXCLUDED.intolerances,
         excluded_foods     = EXCLUDED.excluded_foods,
         preferred_cuisines = EXCLUDED.preferred_cuisines,
         target_calories    = EXCLUDED.target_calories,
         target_protein_g   = EXCLUDED.target_protein_g,
         target_carbs_g     = EXCLUDED.target_carbs_g,
         target_fat_g       = EXCLUDED.target_fat_g,
         target_fiber_g     = EXCLUDED.target_fiber_g,
         updated_at         = NOW()
       RETURNING id`,
      [
        userId,
        body.objective,
        body.weight_kg ?? null,
        body.height_cm ?? null,
        body.age ?? null,
        body.sex ?? null,
        body.activity_level,
        body.meals_per_day,
        body.batch_cooking,
        body.cook_time_available ?? null,
        body.budget ?? null,
        body.allergies,
        body.intolerances,
        body.excluded_foods,
        body.preferred_cuisines,
        targets.target_calories ?? null,
        targets.target_protein_g ?? null,
        targets.target_carbs_g ?? null,
        targets.target_fat_g ?? null,
        targets.target_fiber_g ?? null,
      ]
    )
    return reply.status(201).send({ id: row!.id })
  })

  // PATCH /nutrition/profile — Mise à jour partielle
  app.patch('/', async (req, reply) => {
    const parsed = NutritionProfileSchema.partial().safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub

    const existing = await queryOne(
      `SELECT id, weight_kg, height_cm, age, sex, activity_level, objective
       FROM nutrition_profiles WHERE user_id = $1`,
      [userId]
    )
    if (!existing) return reply.status(404).send({ error: 'NOT_FOUND' })

    const body = parsed.data
    const fields: string[] = []
    const values: unknown[] = [userId]
    let idx = 2

    const addField = (col: string, val: unknown) => {
      if (val !== undefined) { fields.push(`${col} = $${idx++}`); values.push(val) }
    }

    addField('objective',           body.objective)
    addField('weight_kg',           body.weight_kg)
    addField('height_cm',           body.height_cm)
    addField('age',                 body.age)
    addField('sex',                 body.sex)
    addField('activity_level',      body.activity_level)
    addField('meals_per_day',       body.meals_per_day)
    addField('batch_cooking',       body.batch_cooking)
    addField('cook_time_available', body.cook_time_available)
    addField('budget',              body.budget)
    addField('allergies',           body.allergies)
    addField('intolerances',        body.intolerances)
    addField('excluded_foods',      body.excluded_foods)
    addField('preferred_cuisines',  body.preferred_cuisines)

    if (fields.length === 0) return reply.status(400).send({ error: 'NO_FIELDS' })

    // Recalculer les cibles si les données anthropométriques changent
    const mergedWeight   = body.weight_kg      ?? (existing as any).weight_kg
    const mergedHeight   = body.height_cm      ?? (existing as any).height_cm
    const mergedAge      = body.age            ?? (existing as any).age
    const mergedSex      = body.sex            ?? (existing as any).sex
    const mergedActivity = body.activity_level ?? (existing as any).activity_level
    const mergedObjective = body.objective     ?? (existing as any).objective

    if (mergedWeight && mergedHeight && mergedAge && mergedSex) {
      try {
        const targets = await calculateNutritionTargets({
          objective:      mergedObjective,
          weight_kg:      mergedWeight,
          height_cm:      mergedHeight,
          age:            mergedAge,
          sex:            mergedSex,
          activity_level: mergedActivity,
        })
        addField('target_calories',  targets.target_calories)
        addField('target_protein_g', targets.target_protein_g)
        addField('target_carbs_g',   targets.target_carbs_g)
        addField('target_fat_g',     targets.target_fat_g)
        addField('target_fiber_g',   targets.target_fiber_g)
      } catch { /* optionnel */ }
    }

    fields.push(`updated_at = NOW()`)
    await query(
      `UPDATE nutrition_profiles SET ${fields.join(', ')} WHERE user_id = $1`,
      values
    )
    return reply.status(200).send({ updated: true })
  })
}
