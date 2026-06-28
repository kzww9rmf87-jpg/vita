import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

const { query, queryOne } = await import('../src/db.js') as {
  query: ReturnType<typeof vi.fn>
  queryOne: ReturnType<typeof vi.fn>
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { nutritionRoutes } = await import('../src/routes/nutrition.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    (req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(nutritionRoutes, { prefix: '/nutrition' })
  return app
}

describe('POST /nutrition (daily)', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('upserts daily entry', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition',
      payload: { date: '2026-06-28', calories: 2000 },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ date: '2026-06-28' })
  })

  it('400 on invalid date format', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition',
      payload: { date: 'invalid', calories: 2000 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('does not store quality_score or adherence_score', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url: '/nutrition',
      payload: { date: '2026-06-28', calories: 2000 },
    })
    const sql: string = (query as any).mock.calls[0][0]
    expect(sql).not.toContain('quality_score')
    expect(sql).not.toContain('adherence_score')
  })
})

describe('GET /nutrition/history', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns list of daily entries', async () => {
    ;(query as any).mockResolvedValue([
      { date: '2026-06-28', calories: 2000 },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/history' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })

  it('caps days at 365', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/nutrition/history?days=500' })
    expect((query as any).mock.calls[0][1][1]).toBe(365)
  })
})

describe('POST /nutrition/meals', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates a meal and returns id', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'meal-1' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/meals',
      payload: { date: '2026-06-28', description: 'Pâtes bolognaise', mealType: 'lunch' },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'meal-1' })
  })

  it('400 when description missing', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/meals',
      payload: { date: '2026-06-28' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 when mealType invalid', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/meals',
      payload: { date: '2026-06-28', description: 'X', mealType: 'brunch' },
    })
    expect(res.statusCode).toBe(400)
  })
})

describe('GET /nutrition/meals', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns meals for a date', async () => {
    ;(query as any).mockResolvedValue([
      { id: 'meal-1', description: 'Café', meal_type: 'breakfast' },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/meals?date=2026-06-28' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })
})

describe('DELETE /nutrition/meals/:id', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('204 when meal found and deleted', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'meal-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/nutrition/meals/meal-1' })
    expect(res.statusCode).toBe(204)
  })

  it('404 when meal not found', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/nutrition/meals/nonexistent' })
    expect(res.statusCode).toBe(404)
  })

  it('passes userId for ownership check', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'meal-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'DELETE', url: '/nutrition/meals/meal-1' })
    expect((queryOne as any).mock.calls[0][1]).toContain('user-uuid-123')
  })
})

describe('POST /nutrition/food-items', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates a food item', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'food-1' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/food-items',
      payload: { name: 'Poulet grillé', caloriesPer100g: 165 },
    })
    expect(res.statusCode).toBe(201)
  })

  it('400 when name missing', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/food-items',
      payload: { caloriesPer100g: 165 },
    })
    expect(res.statusCode).toBe(400)
  })
})

describe('GET /nutrition/food-items', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns food items for user', async () => {
    ;(query as any).mockResolvedValue([{ id: 'f1', name: 'Riz' }])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/food-items' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })
})

describe('POST /nutrition/recipes', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates a recipe', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'recipe-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/recipes',
      payload: {
        name: 'Riz au poulet',
        servings: 2,
        ingredients: [{ name: 'Riz', quantityG: 100 }],
      },
    })
    expect(res.statusCode).toBe(201)
  })

  it('400 when name missing', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/recipes',
      payload: { servings: 2 },
    })
    expect(res.statusCode).toBe(400)
  })
})

describe('GET /nutrition/recipes', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns recipes for user', async () => {
    ;(query as any).mockResolvedValue([{ id: 'r1', name: 'Riz au poulet' }])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes' })
    expect(res.statusCode).toBe(200)
  })
})

describe('GET /nutrition/recipes/:id', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns recipe with ingredients', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'r1', name: 'Riz' })
    ;(query as any).mockResolvedValue([{ name: 'Riz', quantity_g: 100 }])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes/r1' })
    expect(res.statusCode).toBe(200)
  })

  it('404 when recipe not found', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes/nonexistent' })
    expect(res.statusCode).toBe(404)
  })
})
