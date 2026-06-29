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
  objective: 'gain',
  weightKg: 80,
  heightCm: 180,
  age: 28,
  sex: 'male',
  activityLevel: 'moderate',
  mealsPerDay: 3,
  batchCooking: true,
  allergies: [],
  intolerances: [],
  excludedFoods: [],
  preferredCuisines: [],
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
      payload: { objective: 'maintain', activityLevel: 'moderate' },
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

  it('400 si weightKg négatif', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/nutrition/profile',
      payload: { ...FULL_BODY, weightKg: -5 },
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
      payload: { batchCooking: true },
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

  it('400 si valeur hors plage (mealsPerDay > 6)', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/nutrition/profile',
      payload: { mealsPerDay: 10 },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })
})
