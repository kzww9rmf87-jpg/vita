import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

vi.mock('../src/ai-client.js', () => ({
  calculateNutritionTargets: vi.fn(),
}))

const { queryOne, query } = await import('../src/db.js') as {
  queryOne: ReturnType<typeof vi.fn>
  query:    ReturnType<typeof vi.fn>
}
const { calculateNutritionTargets } = await import('../src/ai-client.js') as {
  calculateNutritionTargets: ReturnType<typeof vi.fn>
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { nutritionProfileRoutes } = await import('../src/routes/nutrition-profile.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(nutritionProfileRoutes, { prefix: '/nutrition/profile' })
  return app
}

const MOCK_TARGETS = {
  target_calories: 2200,
  target_protein_g: 165.0,
  target_carbs_g: 275.0,
  target_fat_g: 73.3,
  target_fiber_g: 38.0,
}

const FULL_BODY = {
  objective:          'gain',
  weight_kg:          80,
  height_cm:          180,
  age:                28,
  sex:                'male',
  activity_level:     'moderate',
  meals_per_day:      3,
  batch_cooking:      true,
  allergies:          [],
  intolerances:       [],
  excluded_foods:     [],
  preferred_cuisines: [],
}

// ── GET /nutrition/profile ────────────────────────────────────────────────────

describe('GET /nutrition/profile', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 retourne le profil existant', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'profile-uuid',
      objective: 'maintain',
      weight_kg: 70,
      target_calories: 2000,
    })
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/profile' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ id: 'profile-uuid', objective: 'maintain' })
  })

  it('404 si pas de profil', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/profile' })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NOT_FOUND')
  })
})

// ── POST /nutrition/profile ───────────────────────────────────────────────────

describe('POST /nutrition/profile', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('201 crée le profil avec cibles quand données anthropométriques complètes', async () => {
    ;(calculateNutritionTargets as any).mockResolvedValue(MOCK_TARGETS)
    ;(queryOne as any).mockResolvedValue({ id: 'new-profile-id' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: FULL_BODY,
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'new-profile-id' })
    expect(calculateNutritionTargets).toHaveBeenCalledOnce()
  })

  it('201 crée le profil sans cibles si données anthropométriques manquantes', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'profile-no-targets' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: { objective: 'maintain', activity_level: 'moderate' },
    })
    expect(res.statusCode).toBe(201)
    expect(calculateNutritionTargets).not.toHaveBeenCalled()
  })

  it('201 crée sans cibles si ai-engine indisponible', async () => {
    ;(calculateNutritionTargets as any).mockRejectedValue(new Error('ai-engine down'))
    ;(queryOne as any).mockResolvedValue({ id: 'profile-fallback' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: FULL_BODY,
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'profile-fallback' })
  })

  it('400 si objective invalide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: { objective: 'unknown_objective' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si weight_kg négatif', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: { ...FULL_BODY, weight_kg: -5 },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si age < 10', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: { ...FULL_BODY, age: 5 },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si sex invalide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: { ...FULL_BODY, sex: 'robot' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })
})

// ── PATCH /nutrition/profile ──────────────────────────────────────────────────

describe('PATCH /nutrition/profile', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 met à jour le profil et recalcule les cibles', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'profile-uuid',
      weight_kg: 80, height_cm: 180, age: 28, sex: 'male',
      activity_level: 'moderate', objective: 'gain',
    })
    ;(calculateNutritionTargets as any).mockResolvedValue(MOCK_TARGETS)
    ;(query as any).mockResolvedValue({ rows: [] })
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/nutrition/profile',
      payload: { objective: 'maintain' },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ updated: true })
    expect(calculateNutritionTargets).toHaveBeenCalledOnce()
  })

  it('404 si profil introuvable', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/nutrition/profile',
      payload: { batch_cooking: true },
    })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NOT_FOUND')
  })

  it('400 si aucun champ fourni', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'profile-uuid', weight_kg: null, height_cm: null, age: null, sex: null })
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/nutrition/profile',
      payload: {},
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('NO_FIELDS')
  })

  it('400 si valeur hors plage (meals_per_day > 6)', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/nutrition/profile',
      payload: { meals_per_day: 10 },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })
})

// ── Tests de régression contrat iOS ──────────────────────────────────────────

describe('régression iOS — payload snake_case profil nutritionnel', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('POST accepte le payload snake_case complet envoyé par NutritionProfileViewModel', async () => {
    ;(calculateNutritionTargets as any).mockResolvedValue(MOCK_TARGETS)
    ;(queryOne as any).mockResolvedValue({ id: 'profile-snake' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: {
        objective:           'maintain',
        weight_kg:           72.5,
        height_cm:           175,
        age:                 32,
        sex:                 'female',
        activity_level:      'active',
        meals_per_day:       3,
        batch_cooking:       false,
        cook_time_available: 'moderate',
        budget:              'medium',
        allergies:           ['gluten'],
        intolerances:        ['lactose'],
        excluded_foods:      ['champignons'],
        preferred_cuisines:  ['méditerranéenne'],
      },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'profile-snake' })
  })

  it('PATCH accepte les champs snake_case partiels envoyés par iOS', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'profile-uuid',
      weight_kg: 72.5, height_cm: 175, age: 32, sex: 'female',
      activity_level: 'active', objective: 'maintain',
    })
    ;(calculateNutritionTargets as any).mockResolvedValue(MOCK_TARGETS)
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/nutrition/profile',
      payload: { activity_level: 'very_active', meals_per_day: 4 },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ updated: true })
  })

  // Régression NUMERIC : weight_kg NUMERIC(5,1) et target_* NUMERIC(5,1)
  // retournés comme strings par node-postgres sans ::FLOAT cast
  it('régression SQL GET — SELECT caste weight_kg et target_* en FLOAT', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'profile-uuid',
      objective: 'maintain',
      weight_kg: 72.5,
      target_calories: 2000,
      target_protein_g: 120.0,
      target_carbs_g: 250.0,
      target_fat_g: 65.0,
      target_fiber_g: 30.0,
    })
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/nutrition/profile' })
    const sql: string = (queryOne as any).mock.calls[0][0]
    expect(sql).toContain('weight_kg::FLOAT')
    expect(sql).toContain('target_protein_g::FLOAT')
    expect(sql).toContain('target_carbs_g::FLOAT')
    expect(sql).toContain('target_fat_g::FLOAT')
    expect(sql).toContain('target_fiber_g::FLOAT')
  })
})
