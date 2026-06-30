/**
 * Sport — routes data-service.
 *
 * Profil sportif et plans d'entraînement (Training Planner).
 * Pas de calcul intelligent — fondations uniquement (Sprint 11).
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'

// ── Schémas ───────────────────────────────────────────────────────────────────

// Schémas en snake_case — correspond à ce qu'iOS envoie via JSONEncoder.vita (.convertToSnakeCase)

const SportProfileSchema = z.object({
  fitness_level:        z.enum(['beginner', 'intermediate', 'advanced', 'elite']).default('beginner'),
  preferred_activities: z.array(z.string().max(100)).max(20).default([]),
  sessions_per_week:    z.number().int().min(1).max(14).default(3),
  session_duration_min: z.number().int().min(10).max(300).default(45),
  // 0=dimanche … 6=samedi
  available_days:       z.array(z.number().int().min(0).max(6)).max(7).default([1, 3, 5]),
  context:              z.string().max(2000).optional(),
})

const SportProfilePatchSchema = SportProfileSchema.partial()

const TrainingPlanSessionSchema = z.object({
  day_of_week:   z.number().int().min(0).max(6),
  activity_name: z.string().min(1).max(100),
  duration_min:  z.number().int().min(5).max(300).default(45),
  notes:         z.string().max(1000).optional(),
  sort_order:    z.number().int().min(0).default(0),
})

const TrainingPlanSchema = z.object({
  name:        z.string().min(1).max(100),
  description: z.string().max(1000).optional(),
  is_active:   z.boolean().default(false),
  sessions:    z.array(TrainingPlanSessionSchema).max(50).default([]),
})

// ── Routes ────────────────────────────────────────────────────────────────────

export const sportRoutes: FastifyPluginAsync = async (app) => {

  // ── Profil sportif ──────────────────────────────────────────────────────────

  // GET /sport/profile
  // Returns: SportProfile | 404
  // Auth: JWT requis
  app.get('/profile', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const row = await queryOne<{
      id: string
      fitness_level: string
      preferred_activities: string[]
      sessions_per_week: number
      session_duration_min: number
      available_days: number[]
      context: string | null
      created_at: string
      updated_at: string
    }>(
      `SELECT id, fitness_level, preferred_activities, sessions_per_week,
              session_duration_min, available_days, context, created_at, updated_at
       FROM sport_profiles WHERE user_id = $1`,
      [userId]
    )

    if (!row) return reply.status(404).send({ error: 'NOT_FOUND' })

    return reply.send({
      id:                  row.id,
      fitnessLevel:        row.fitness_level,
      preferredActivities: row.preferred_activities,
      sessionsPerWeek:     row.sessions_per_week,
      sessionDurationMin:  row.session_duration_min,
      availableDays:       row.available_days,
      context:             row.context,
      createdAt:           row.created_at,
      updatedAt:           row.updated_at,
    })
  })

  // PUT /sport/profile
  // Body: SportProfileSchema (partial accepté via merge)
  // Returns: { id: string }
  // Auth: JWT requis
  app.put('/profile', async (req, reply) => {
    const parsed = SportProfilePatchSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    const existing = await queryOne<{ id: string }>(
      `SELECT id FROM sport_profiles WHERE user_id = $1`,
      [userId]
    )

    if (!existing) {
      // INSERT avec les valeurs fournies + défauts Zod
      const full = SportProfileSchema.parse({ ...body })
      const row = await queryOne<{ id: string }>(
        `INSERT INTO sport_profiles
           (user_id, fitness_level, preferred_activities, sessions_per_week,
            session_duration_min, available_days, context)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         RETURNING id`,
        [
          userId,
          full.fitness_level,
          full.preferred_activities,
          full.sessions_per_week,
          full.session_duration_min,
          full.available_days,
          full.context ?? null,
        ]
      )
      return reply.status(201).send({ id: row!.id })
    }

    // UPDATE partiel
    const fields: string[] = []
    const values: unknown[] = [existing.id]
    let idx = 2

    const addField = (col: string, val: unknown) => {
      if (val !== undefined) { fields.push(`${col} = $${idx++}`); values.push(val) }
    }

    addField('fitness_level',        body.fitness_level)
    addField('preferred_activities', body.preferred_activities)
    addField('sessions_per_week',    body.sessions_per_week)
    addField('session_duration_min', body.session_duration_min)
    addField('available_days',       body.available_days)
    addField('context',              body.context)

    if (fields.length > 0) {
      await query(
        `UPDATE sport_profiles SET ${fields.join(', ')} WHERE id = $1`,
        values
      )
    }

    return reply.status(200).send({ id: existing.id })
  })

  // ── Plans d'entraînement ────────────────────────────────────────────────────

  // GET /sport/training-plans
  // Returns: TrainingPlan[] (sans les sessions)
  // Auth: JWT requis
  app.get('/training-plans', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const plans = await query<{
      id: string
      name: string
      description: string | null
      is_active: boolean
      created_at: string
    }>(
      `SELECT id, name, description, is_active, created_at
       FROM training_plans
       WHERE user_id = $1
       ORDER BY is_active DESC, created_at DESC`,
      [userId]
    )

    return reply.send(plans.map(p => ({
      id:          p.id,
      name:        p.name,
      description: p.description,
      isActive:    p.is_active,
      createdAt:   p.created_at,
    })))
  })

  // POST /sport/training-plans
  // Body: TrainingPlanSchema
  // Returns: { id: string }
  // Auth: JWT requis
  app.post('/training-plans', async (req, reply) => {
    const parsed = TrainingPlanSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    // Si ce plan est actif, désactiver les autres
    if (body.is_active) {
      await query(
        `UPDATE training_plans SET is_active = false WHERE user_id = $1`,
        [userId]
      )
    }

    const row = await queryOne<{ id: string }>(
      `INSERT INTO training_plans (user_id, name, description, is_active)
       VALUES ($1,$2,$3,$4)
       RETURNING id`,
      [userId, body.name, body.description ?? null, body.is_active]
    )
    const planId = row!.id

    for (const s of body.sessions) {
      await query(
        `INSERT INTO training_plan_sessions
           (plan_id, day_of_week, activity_name, duration_min, notes, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [planId, s.day_of_week, s.activity_name, s.duration_min, s.notes ?? null, s.sort_order]
      )
    }

    return reply.status(201).send({ id: planId })
  })

  // GET /sport/training-plans/:id
  // Returns: TrainingPlan avec sessions
  // Auth: JWT requis + vérification ownership
  app.get('/training-plans/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const plan = await queryOne<{
      id: string
      name: string
      description: string | null
      is_active: boolean
      created_at: string
    }>(
      `SELECT id, name, description, is_active, created_at
       FROM training_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    const sessions = await query<{
      id: string
      day_of_week: number
      activity_name: string
      duration_min: number
      notes: string | null
      sort_order: number
    }>(
      `SELECT id, day_of_week, activity_name, duration_min, notes, sort_order
       FROM training_plan_sessions WHERE plan_id = $1
       ORDER BY day_of_week, sort_order`,
      [id]
    )

    return reply.send({
      id:          plan.id,
      name:        plan.name,
      description: plan.description,
      isActive:    plan.is_active,
      createdAt:   plan.created_at,
      sessions:    sessions.map(s => ({
        id:           s.id,
        dayOfWeek:    s.day_of_week,
        activityName: s.activity_name,
        durationMin:  s.duration_min,
        notes:        s.notes,
        sortOrder:    s.sort_order,
      })),
    })
  })

  // DELETE /sport/training-plans/:id
  // Auth: JWT requis + vérification ownership
  app.delete('/training-plans/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const existing = await queryOne(
      `SELECT id FROM training_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!existing) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM training_plans WHERE id = $1`, [id])
    return reply.status(204).send()
  })
}
