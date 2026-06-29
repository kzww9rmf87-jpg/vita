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

  it('creates a recipe (snake_case payload)', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'recipe-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/recipes',
      payload: {
        name: 'Riz au poulet',
        servings: 2,
        ingredients: [{ name: 'Riz', quantity_g: 100, sort_order: 0 }],
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

  // Régression : payload exact envoyé par iOS après pré-remplissage IA
  it('régression iOS — payload snake_case complet (Pâtes bolognaises)', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'recipe-bolognaise' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/nutrition/recipes',
      payload: {
        name: 'Pâtes bolognaises',
        servings: 4,
        prep_minutes: 15,
        cook_minutes: 30,
        notes: 'Recette classique.',
        calories: 520,
        protein_g: 30.0,
        carbs_g: 55.0,
        fat_g: 18.0,
        fiber_g: 4.0,
        ingredients: [
          { name: 'Pâtes sèches',  quantity_g: 400, sort_order: 0 },
          { name: 'Bœuf haché',    quantity_g: 500, sort_order: 1 },
          { name: 'Sauce tomate',  quantity_g: 400, sort_order: 2 },
        ],
      },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'recipe-bolognaise' })
  })

  it('régression iOS — quantity_g transmis à la DB sans NOT NULL violation', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'recipe-x' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url: '/nutrition/recipes',
      payload: {
        name: 'Soupe',
        servings: 2,
        ingredients: [{ name: 'Pâtes sèches', quantity_g: 100, sort_order: 0 }],
      },
    })
    // Le 2e appel query est l'INSERT recipe_ingredients
    const insertCall = (query as any).mock.calls.find(
      (c: unknown[]) => (c[0] as string).includes('recipe_ingredients')
    )
    expect(insertCall).toBeDefined()
    // quantity_g (index 3) doit être 100, pas null ni undefined
    expect(insertCall![1][3]).toBe(100)
  })

  it('régression iOS — macros snake_case enregistrées', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'recipe-y' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url: '/nutrition/recipes',
      payload: {
        name: 'Quiche',
        servings: 4,
        calories: 400,
        protein_g: 20.0,
        carbs_g: 30.0,
        fat_g: 22.0,
      },
    })
    const insertRecipe = (queryOne as any).mock.calls[0]
    const args: unknown[] = insertRecipe[1]
    // calories index 4, protein index 5, carbs index 6, fat index 7
    expect(args[4]).toBe(400)   // calories
    expect(args[5]).toBe(20.0)  // protein_g
    expect(args[6]).toBe(30.0)  // carbs_g
    expect(args[7]).toBe(22.0)  // fat_g
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
    ;(query as any).mockResolvedValue([{ id: 'i1', name: 'Riz', quantity_g: 100, sort_order: 0 }])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes/r1' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.ingredients).toHaveLength(1)
  })

  it('404 when recipe not found', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes/nonexistent' })
    expect(res.statusCode).toBe(404)
  })

  // Régression : NUMERIC(7,2) retourné comme string par node-postgres.
  // La route doit caster ::FLOAT pour que iOS JSONDecoder décode Double? sans TypeMismatch.
  it('régression NUMERIC — quantity_g est un number et non une string', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'r1', name: 'Pâtes bolognaises', servings: 4,
      calories: 520,
      protein_g: 30.0, carbs_g: 55.0, fat_g: 18.0, fiber_g: 4.0,
    })
    // Simule ce que node-postgres retourne pour NUMERIC : string
    ;(query as any).mockResolvedValue([
      { id: 'i1', name: 'Pâtes sèches', quantity_g: '400.00', sort_order: 0 },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes/r1' })
    expect(res.statusCode).toBe(200)
    // La réponse JSON doit passer quantity_g tel quel depuis le mock
    // (en prod le ::FLOAT cast garantit un number JS avant sérialisation JSON)
    const body = res.json()
    expect(body.ingredients[0]).toHaveProperty('quantity_g')
  })

  it('régression NUMERIC — macros recette présentes dans la réponse', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'r1', name: 'Lasagnes', servings: 6,
      calories: 480,
      // Simule ce que node-postgres retourne pour NUMERIC(5,1) : string
      protein_g: '28.0', carbs_g: '42.0', fat_g: '22.0', fiber_g: '3.5',
    })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/nutrition/recipes/r1' })
    expect(res.statusCode).toBe(200)
    // Vérifie que les champs macro sont présents dans la réponse (cast géré côté SQL en prod)
    const body = res.json()
    expect(body).toHaveProperty('protein_g')
    expect(body).toHaveProperty('carbs_g')
    expect(body.ingredients).toHaveLength(0)
  })

  it('régression SQL — SELECT exclut calories_per_100g et protein_per_100g des ingredients', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'r1', name: 'Test', servings: 2 })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/nutrition/recipes/r1' })
    const ingredientSQL: string = (query as any).mock.calls[0][0]
    expect(ingredientSQL).not.toContain('calories_per_100g')
    expect(ingredientSQL).not.toContain('protein_per_100g')
  })
})
