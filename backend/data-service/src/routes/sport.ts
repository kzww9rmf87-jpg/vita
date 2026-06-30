/**
 * Sport — routes data-service.
 *
 * Profil sportif, plans d'entraînement et AI Training Planner.
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import { requestTrainingPlan, requestSportDiscover, AIEngineError } from '../ai-client.js'

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
  // Sprint 12.2 — préférences découverte
  motivation:            z.enum(['bouger_un_peu', 'reprendre_confiance', 'ameliorer_energie', 'perdre_poids', 'preparer_sport']).optional(),
  attractive_activities: z.array(z.string().max(100)).max(20).default([]),
  rejected_activities:   z.array(z.string().max(100)).max(20).default([]),
  preferred_context:     z.array(z.enum(['seul', 'groupe', 'dehors', 'maison', 'salle'])).max(5).default([]),
  apprehension_level:    z.enum(['aucune', 'legere', 'moderee', 'elevee']).default('aucune'),
  realistic_time_min:    z.number().int().min(10).max(120).optional(),
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

// ── Inférence du type dominant depuis le nom d'activité ──────────────────────

const _TYPE_KEYWORDS: Array<[string[], string]> = [
  [['musculation', 'muscu', 'weight', 'haltère', 'gym', 'force'], 'strength'],
  [['krav', 'combat', 'boxe', 'judo', 'mma', 'arts martiaux'],    'combat'],
  [['yoga', 'mobilité', 'mobilite', 'étirement', 'stretching', 'pilates'], 'mobility'],
  [['marche', 'walk', 'randonnée', 'rando'],                      'walk'],
  [['course', 'run', 'vélo', 'velo', 'natation', 'swim', 'cardio', 'hiit'], 'cardio'],
]

function _inferType(name: string): string {
  const lower = name.toLowerCase()
  for (const [keywords, type] of _TYPE_KEYWORDS) {
    if (keywords.some(k => lower.includes(k))) return type
  }
  return 'cardio'
}

function _inferDominantType(activityNames: string[]): string {
  if (activityNames.length === 0) return 'rest'
  const counts: Record<string, number> = {}
  for (const name of activityNames) {
    const t = _inferType(name)
    counts[t] = (counts[t] ?? 0) + 1
  }
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]![0]
}

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
      motivation: string | null
      attractive_activities: string[]
      rejected_activities: string[]
      preferred_context: string[]
      apprehension_level: string
      realistic_time_min: number | null
      created_at: string
      updated_at: string
    }>(
      `SELECT id, fitness_level, preferred_activities, sessions_per_week,
              session_duration_min, available_days, context,
              motivation, attractive_activities, rejected_activities,
              preferred_context, apprehension_level, realistic_time_min,
              created_at, updated_at
       FROM sport_profiles WHERE user_id = $1`,
      [userId]
    )

    if (!row) return reply.status(404).send({ error: 'NOT_FOUND' })

    return reply.send({
      id:                   row.id,
      fitnessLevel:         row.fitness_level,
      preferredActivities:  row.preferred_activities,
      sessionsPerWeek:      row.sessions_per_week,
      sessionDurationMin:   row.session_duration_min,
      availableDays:        row.available_days,
      context:              row.context,
      motivation:           row.motivation,
      attractiveActivities: row.attractive_activities,
      rejectedActivities:   row.rejected_activities,
      preferredContext:     row.preferred_context,
      apprehensionLevel:    row.apprehension_level,
      realisticTimeMin:     row.realistic_time_min,
      createdAt:            row.created_at,
      updatedAt:            row.updated_at,
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
            session_duration_min, available_days, context,
            motivation, attractive_activities, rejected_activities,
            preferred_context, apprehension_level, realistic_time_min)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
         RETURNING id`,
        [
          userId,
          full.fitness_level,
          full.preferred_activities,
          full.sessions_per_week,
          full.session_duration_min,
          full.available_days,
          full.context ?? null,
          full.motivation ?? null,
          full.attractive_activities,
          full.rejected_activities,
          full.preferred_context,
          full.apprehension_level,
          full.realistic_time_min ?? null,
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
    addField('motivation',           body.motivation)
    addField('attractive_activities', body.attractive_activities)
    addField('rejected_activities',   body.rejected_activities)
    addField('preferred_context',     body.preferred_context)
    addField('apprehension_level',    body.apprehension_level)
    addField('realistic_time_min',    body.realistic_time_min)

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

  // GET /sport/training-plans/active/context
  // Retourne le contexte sportif de la semaine active (7 jours, load_level, dominant_type).
  // Utilisé par le Nutrition Planner pour organiser les repas selon la charge sportive.
  // Si aucun plan actif : retourne 7 jours "rest".
  // Auth: JWT requis
  app.get('/training-plans/active/context', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const plan = await queryOne<{ id: string }>(
      `SELECT id FROM training_plans WHERE user_id = $1 AND is_active = true LIMIT 1`,
      [userId]
    )

    if (!plan) {
      return reply.send({
        hasActivePlan: false,
        days: Array.from({ length: 7 }, (_, i) => ({
          day_of_week:        i,
          activity_label:     'Repos',
          load_level:         'rest',
          session_count:      0,
          total_duration_min: 0,
          dominant_type:      'rest',
        })),
      })
    }

    const sessions = await query<{
      day_of_week:   number
      activity_name: string
      duration_min:  number
    }>(
      `SELECT day_of_week, activity_name, duration_min
       FROM training_plan_sessions WHERE plan_id = $1
       ORDER BY day_of_week, sort_order`,
      [plan.id]
    )

    // Regrouper par jour
    const byDay = new Map<number, typeof sessions>()
    for (const s of sessions) {
      if (!byDay.has(s.day_of_week)) byDay.set(s.day_of_week, [])
      byDay.get(s.day_of_week)!.push(s)
    }

    const days = Array.from({ length: 7 }, (_, day) => {
      const daySessions  = byDay.get(day) ?? []
      const count        = daySessions.length
      const totalMin     = daySessions.reduce((sum, s) => sum + s.duration_min, 0)
      const dominantType = count > 0 ? _inferDominantType(daySessions.map(s => s.activity_name)) : 'rest'

      let loadLevel: 'rest' | 'light' | 'moderate' | 'demanding'
      if (count === 0)                              loadLevel = 'rest'
      else if (count === 1 && totalMin <= 30)       loadLevel = 'light'
      else if (totalMin <= 60)                      loadLevel = 'moderate'
      else                                          loadLevel = 'demanding'

      return {
        day_of_week:        day,
        activity_label:     count > 0 ? daySessions[0]!.activity_name : 'Repos',
        load_level:         loadLevel,
        session_count:      count,
        total_duration_min: totalMin,
        dominant_type:      dominantType,
      }
    })

    return reply.send({ hasActivePlan: true, days })
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

  // ── AI Training Planner ─────────────────────────────────────────────────────

  // POST /sport/training-planner/suggest
  // Génère une semaine d'entraînement depuis le profil sportif de l'utilisateur.
  // Si aucun profil n'existe, utilise les valeurs par défaut (beginner, 3 séances, [1,3,5]).
  // Ne persiste rien — l'utilisateur sauvegarde ensuite via POST /sport/training-plans.
  // Returns: TrainingWeekPlan + hasProfile: bool
  // Auth: JWT requis
  app.post('/training-planner/suggest', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const row = await queryOne<{
      fitness_level:         string
      preferred_activities:  string[]
      sessions_per_week:     number
      session_duration_min:  number
      available_days:        number[]
      context:               string | null
      motivation:            string | null
      attractive_activities: string[]
      rejected_activities:   string[]
      preferred_context:     string[]
      apprehension_level:    string
      realistic_time_min:    number | null
    }>(
      `SELECT fitness_level, preferred_activities, sessions_per_week,
              session_duration_min, available_days, context,
              motivation, attractive_activities, rejected_activities,
              preferred_context, apprehension_level, realistic_time_min
       FROM sport_profiles WHERE user_id = $1`,
      [userId]
    )

    // Sans profil : valeurs par défaut identiques à SportProfileSchema
    const hasProfile = row !== null
    const profile = row ?? {
      fitness_level:         'beginner',
      preferred_activities:  [] as string[],
      sessions_per_week:     3,
      session_duration_min:  45,
      available_days:        [1, 3, 5],
      context:               null,
      motivation:            null,
      attractive_activities: [] as string[],
      rejected_activities:   [] as string[],
      preferred_context:     [] as string[],
      apprehension_level:    'aucune',
      realistic_time_min:    null,
    }

    try {
      const result = await requestTrainingPlan(userId, {
        fitness_level:         profile.fitness_level,
        preferred_activities:  profile.preferred_activities,
        sessions_per_week:     profile.sessions_per_week,
        session_duration_min:  profile.session_duration_min,
        available_days:        profile.available_days,
        context:               profile.context,
        motivation:            profile.motivation            ?? undefined,
        attractive_activities: profile.attractive_activities,
        rejected_activities:   profile.rejected_activities,
        preferred_context:     profile.preferred_context,
        apprehension_level:    profile.apprehension_level,
        realistic_time_min:    profile.realistic_time_min   ?? undefined,
      })

      return reply.send({
        sessions: result.sessions.map(s => ({
          dayOfWeek:    s.day_of_week,
          activityName: s.activity_name,
          sessionType:  s.session_type,
          durationMin:  s.duration_min,
          notes:        s.notes,
          sortOrder:    s.sort_order,
        })),
        rationale:  result.rationale,
        usedClaude: result.used_claude,
        hasProfile,
      })
    } catch (err) {
      if (err instanceof AIEngineError) {
        if (err.status === 504) {
          return reply.status(504).send({ error: 'AI_TIMEOUT' })
        }
        return reply.status(502).send({ error: 'AI_UNAVAILABLE' })
      }
      throw err
    }
  })

  // POST /sport/training-planner/discover
  // Propose 3-5 options d'activité adaptées au profil.
  // Charge le profil existant si présent, complète avec les overrides du body.
  // Returns: SportDiscoverResult
  // Auth: JWT requis
  app.post('/training-planner/discover', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    // Body facultatif — overrides du profil
    const DiscoverOverrideSchema = z.object({
      fitness_level:         z.enum(['beginner', 'intermediate', 'advanced', 'elite']).optional(),
      motivation:            z.enum(['bouger_un_peu', 'reprendre_confiance', 'ameliorer_energie', 'perdre_poids', 'preparer_sport']).optional(),
      attractive_activities: z.array(z.string().max(100)).max(20).optional(),
      rejected_activities:   z.array(z.string().max(100)).max(20).optional(),
      preferred_context:     z.array(z.enum(['seul', 'groupe', 'dehors', 'maison', 'salle'])).max(5).optional(),
      apprehension_level:    z.enum(['aucune', 'legere', 'moderee', 'elevee']).optional(),
      realistic_time_min:    z.number().int().min(10).max(120).optional(),
      context:               z.string().max(2000).optional(),
    }).optional()

    const parsed = DiscoverOverrideSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const overrides = parsed.data ?? {}

    // Charger le profil existant
    const row = await queryOne<{
      fitness_level:         string
      motivation:            string | null
      attractive_activities: string[]
      rejected_activities:   string[]
      preferred_context:     string[]
      apprehension_level:    string
      realistic_time_min:    number | null
      context:               string | null
    }>(
      `SELECT fitness_level, motivation, attractive_activities, rejected_activities,
              preferred_context, apprehension_level, realistic_time_min, context
       FROM sport_profiles WHERE user_id = $1`,
      [userId]
    )

    try {
      const result = await requestSportDiscover(userId, {
        fitness_level:         overrides.fitness_level         ?? row?.fitness_level         ?? 'beginner',
        motivation:            overrides.motivation            ?? row?.motivation             ?? undefined,
        attractive_activities: overrides.attractive_activities ?? row?.attractive_activities  ?? [],
        rejected_activities:   overrides.rejected_activities   ?? row?.rejected_activities   ?? [],
        preferred_context:     overrides.preferred_context     ?? row?.preferred_context      ?? [],
        apprehension_level:    overrides.apprehension_level    ?? row?.apprehension_level     ?? 'aucune',
        realistic_time_min:    overrides.realistic_time_min    ?? row?.realistic_time_min     ?? undefined,
        context:               overrides.context               ?? row?.context                ?? undefined,
      })

      return reply.send(result)
    } catch (err) {
      if (err instanceof AIEngineError) {
        if (err.status === 504) {
          return reply.status(504).send({ error: 'AI_TIMEOUT' })
        }
        return reply.status(502).send({ error: 'AI_UNAVAILABLE' })
      }
      throw err
    }
  })
}
