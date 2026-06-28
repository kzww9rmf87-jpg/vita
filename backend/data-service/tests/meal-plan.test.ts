import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

vi.mock('../src/ai-client.js', () => ({
  requestMealDistribution: vi.fn(),
}))

const { query, queryOne } = await import('../src/db.js') as {
  query: ReturnType<typeof vi.fn>
  queryOne: ReturnType<typeof vi.fn>
}

const { requestMealDistribution } = await import('../src/ai-client.js') as {
  requestMealDistribution: ReturnType<typeof vi.fn>
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { mealPlanRoutes } = await import('../src/routes/meal-plan.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(mealPlanRoutes, { prefix: '/meal-plans' })
  return app
}

// ── POST /meal-plans ───────────────────────────────────────────────────────────

describe('POST /meal-plans', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('201 crée un plan', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-id-1' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { weekStart: '2026-06-30', name: 'Semaine test' },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'plan-id-1' })
  })

  it('400 si weekStart manquant', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { name: 'Sans date' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si weekStart format invalide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { weekStart: '30/06/2026' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('passe user_id depuis JWT', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-1' })
    const app = await makeApp()
    await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { weekStart: '2026-06-30' },
    })
    const sql: string = (queryOne as any).mock.calls[0][0]
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(sql).toContain('INSERT INTO meal_plans')
    expect(args[0]).toBe('user-uuid-123')
  })
})

// ── GET /meal-plans ────────────────────────────────────────────────────────────

describe('GET /meal-plans', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('retourne la liste des plans', async () => {
    const plans = [
      { id: 'p1', week_start: '2026-06-30', name: null },
      { id: 'p2', week_start: '2026-06-23', name: 'Semaine test' },
    ]
    ;(query as any).mockResolvedValue(plans)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/meal-plans' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(2)
  })
})

// ── GET /meal-plans/:id ────────────────────────────────────────────────────────

describe('GET /meal-plans/:id', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 retourne plan + items', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1', week_start: '2026-06-30' })
    ;(query as any).mockResolvedValue([
      { id: 'item-1', day_of_week: 0, meal_slot: 'lunch', recipe_name: 'Poulet rôti', portions: 1 },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/meal-plans/p1' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body).toMatchObject({ id: 'p1' })
    expect(body.items).toHaveLength(1)
  })

  it('404 si plan inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/meal-plans/unknown' })
    expect(res.statusCode).toBe(404)
  })
})

// ── DELETE /meal-plans/:id ────────────────────────────────────────────────────

describe('DELETE /meal-plans/:id', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('204 supprime un plan', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/meal-plans/p1' })
    expect(res.statusCode).toBe(204)
  })

  it('404 si plan inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/meal-plans/unknown' })
    expect(res.statusCode).toBe(404)
  })
})

// ── POST /meal-plans/:id/items ────────────────────────────────────────────────

describe('POST /meal-plans/:id/items', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('201 ajoute un item', async () => {
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })         // vérification ownership
      .mockResolvedValueOnce({ id: 'item-new' })   // INSERT item
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { dayOfWeek: 1, mealSlot: 'lunch', recipeName: 'Salade niçoise', portions: 2 },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'item-new' })
  })

  it('400 si dayOfWeek hors bornes', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { dayOfWeek: 7, mealSlot: 'lunch', recipeName: 'Test', portions: 1 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('400 si mealSlot invalide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { dayOfWeek: 0, mealSlot: 'breakfast', recipeName: 'Test', portions: 1 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('404 si plan introuvable', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/unknown/items',
      payload: { dayOfWeek: 0, mealSlot: 'dinner', recipeName: 'Test', portions: 1 },
    })
    expect(res.statusCode).toBe(404)
  })
})

// ── DELETE /meal-plans/:id/items/:itemId ──────────────────────────────────────

describe('DELETE /meal-plans/:id/items/:itemId', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('204 supprime un item', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'item-1' })
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/meal-plans/p1/items/item-1' })
    expect(res.statusCode).toBe(204)
  })

  it('404 si item inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/meal-plans/p1/items/nope' })
    expect(res.statusCode).toBe(404)
  })
})

// ── POST /meal-plans/:id/distribute ──────────────────────────────────────────

describe('POST /meal-plans/:id/distribute', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 distribue les recettes via AI engine', async () => {
    const recipeUUID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Poulet', servings: 4, prep_minutes: 20, cook_minutes: 60 },
      ])                              // SELECT recipes
      .mockResolvedValueOnce([])     // DELETE existing items
      .mockResolvedValue([])         // INSERT items (×1)

    ;(requestMealDistribution as any).mockResolvedValue([
      { recipe_id: recipeUUID, recipe_name: 'Poulet', day_of_week: 0, meal_slot: 'lunch', portions: 1 },
    ])

    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipeIds: [recipeUUID] },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ itemsCreated: 1 })
  })

  it('400 si recipeIds vide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipeIds: [] },
    })
    expect(res.statusCode).toBe(400)
  })

  it('400 si recipeIds contient des non-UUID', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipeIds: ['not-a-uuid'] },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('503 si AI Engine est indisponible', async () => {
    const recipeUUID = '11111111-1111-1111-1111-111111111111'
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    ;(query as any).mockResolvedValue([
      { id: recipeUUID, name: 'Poulet', servings: 4, prep_minutes: 20, cook_minutes: 60 },
    ])
    ;(requestMealDistribution as any).mockRejectedValue(new Error('AI engine unreachable'))

    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipeIds: [recipeUUID] },
    })
    expect(res.statusCode).toBe(503)
    expect(res.json().error).toBe('AI_ENGINE_UNAVAILABLE')
  })

  it('ON CONFLICT préserve le nom existant si name absent du body', async () => {
    // Test que la route POST / n'efface pas un nom existant si on envoie weekStart seul
    ;(queryOne as any).mockResolvedValue({ id: 'plan-existing' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { weekStart: '2026-06-30' },
    })
    expect(res.statusCode).toBe(201)
    // Vérifier que le SQL utilise COALESCE
    const sql: string = (queryOne as any).mock.calls[0][0]
    expect(sql).toContain('COALESCE')
  })
})

// ── GET /meal-plans/:id/shopping-list ────────────────────────────────────────

describe('GET /meal-plans/:id/shopping-list', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 retourne la liste de courses', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    ;(query as any).mockResolvedValue([
      { id: 'sl-1', ingredient_name: 'poulet', category: 'meat', is_checked: false },
      { id: 'sl-2', ingredient_name: 'tomate', category: 'produce', is_checked: true },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/meal-plans/p1/shopping-list' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(2)
  })

  it('404 si plan inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/meal-plans/unknown/shopping-list' })
    expect(res.statusCode).toBe(404)
  })
})

// ── PATCH /meal-plans/:id/shopping-list/:itemId ───────────────────────────────

describe('PATCH /meal-plans/:id/shopping-list/:itemId', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 coche un item', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'sl-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/meal-plans/p1/shopping-list/sl-1',
      payload: { isChecked: true },
    })
    expect(res.statusCode).toBe(200)
  })

  it('404 si item inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/meal-plans/p1/shopping-list/nope',
      payload: { isChecked: false },
    })
    expect(res.statusCode).toBe(404)
  })
})
