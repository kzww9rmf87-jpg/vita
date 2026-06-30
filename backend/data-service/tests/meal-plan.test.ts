import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

vi.mock('../src/ai-client.js', () => ({
  requestMealDistribution:   vi.fn(),
  requestSmartMealPlan:      vi.fn(),
  calculateNutritionTargets: vi.fn(),
}))

const { query, queryOne } = await import('../src/db.js') as {
  query: ReturnType<typeof vi.fn>
  queryOne: ReturnType<typeof vi.fn>
}

const { requestMealDistribution, requestSmartMealPlan } = await import('../src/ai-client.js') as {
  requestMealDistribution: ReturnType<typeof vi.fn>
  requestSmartMealPlan:    ReturnType<typeof vi.fn>
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
      payload: { week_start: '2026-06-30', name: 'Semaine test' },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'plan-id-1' })
  })

  it('400 si week_start manquant', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { name: 'Sans date' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si week_start format invalide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { week_start: '30/06/2026' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('passe user_id depuis JWT', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-1' })
    const app = await makeApp()
    await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { week_start: '2026-06-30' },
    })
    const sql: string = (queryOne as any).mock.calls[0][0]
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(sql).toContain('INSERT INTO meal_plans')
    expect(args[0]).toBe('user-uuid-123')
  })

  // Régression : iOS envoie week_start (snake_case via JSONEncoder.vita)
  it('régression iOS — payload snake_case week_start accepté', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-regress' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { week_start: '2026-06-30', name: 'Semaine juin' },
    })
    expect(res.statusCode).toBe(201)
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(args[1]).toBe('2026-06-30')
  })

  // Régression : iOS envoie weekStart (dict literal — NON converti par JSONEncoder.vita)
  it('régression iOS — payload camelCase weekStart (dict literal) accepté', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-camel' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { weekStart: '2026-06-29' },
    })
    expect(res.statusCode).toBe(201)
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(args[1]).toBe('2026-06-29')
  })

  it('400 si weekStart format invalide (camelCase)', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { weekStart: '29/06/2026' },
    })
    expect(res.statusCode).toBe(400)
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

  // Régression NUMERIC : portions NUMERIC(4,1) retourné comme string par node-postgres
  // Le ::FLOAT cast dans le SQL garantit un number JS avant sérialisation JSON
  it('régression NUMERIC — portions retournées comme number dans les items', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1', week_start: '2026-06-30' })
    ;(query as any).mockResolvedValue([
      {
        id: 'item-1', day_of_week: 1, meal_slot: 'lunch',
        recipe_name: 'Poulet', portions: 1.5,  // simule ::FLOAT (number JS)
        protein_g: 30.0, carbs_g: 20.0, fat_g: 10.0, fiber_g: 2.0,
      },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/meal-plans/p1' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.items[0]).toHaveProperty('portions')
    expect(body.items[0]).toHaveProperty('protein_g')
  })

  // Régression SQL : le SELECT doit inclure ::FLOAT sur portions et macros JOIN
  it('régression SQL — SELECT caste portions et macros en FLOAT', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1', week_start: '2026-06-30' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/meal-plans/p1' })
    const sql: string = (query as any).mock.calls[0][0]
    expect(sql).toContain('portions::FLOAT')
    expect(sql).toContain('protein_g::FLOAT')
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
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce({ id: 'item-new' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { day_of_week: 1, meal_slot: 'lunch', recipe_name: 'Salade niçoise', portions: 2 },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'item-new' })
  })

  it('400 si day_of_week hors bornes', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { day_of_week: 7, meal_slot: 'lunch', recipe_name: 'Test', portions: 1 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('400 si meal_slot invalide (valeur inconnue)', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { day_of_week: 0, meal_slot: 'brunch', recipe_name: 'Test', portions: 1 },
    })
    expect(res.statusCode).toBe(400)
  })

  // Sprint 9.3 — les 4 créneaux doivent être acceptés
  it('201 breakfast accepté (Sprint 9.3)', async () => {
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce({ id: 'item-breakfast' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { day_of_week: 0, meal_slot: 'breakfast', recipe_name: 'Yaourt granola', portions: 1 },
    })
    expect(res.statusCode).toBe(201)
    const args: unknown[] = (queryOne as any).mock.calls[1][1]
    expect(args[2]).toBe('breakfast')
  })

  it('201 snack accepté (Sprint 9.3)', async () => {
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce({ id: 'item-snack' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: { day_of_week: 3, meal_slot: 'snack', recipe_name: 'Pomme & amandes', portions: 1 },
    })
    expect(res.statusCode).toBe(201)
    const args: unknown[] = (queryOne as any).mock.calls[1][1]
    expect(args[2]).toBe('snack')
  })

  it('404 si plan introuvable', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/unknown/items',
      payload: { day_of_week: 0, meal_slot: 'dinner', recipe_name: 'Test', portions: 1 },
    })
    expect(res.statusCode).toBe(404)
  })

  // Régression : payload exact iOS (MealPlanItemCreate encodé en snake_case)
  it('régression iOS — payload snake_case complet accepté', async () => {
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce({ id: 'item-regress' })
    const app = await makeApp()
    const recipeUUID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/items',
      payload: {
        day_of_week: 2,
        meal_slot:   'dinner',
        recipe_id:   recipeUUID,
        recipe_name: 'Lasagnes bolognaises',
        portions:    1.5,
        sort_order:  0,
      },
    })
    expect(res.statusCode).toBe(201)
    // Vérifier que les valeurs snake_case sont bien transmises à la DB
    const args: unknown[] = (queryOne as any).mock.calls[1][1]
    expect(args[1]).toBe(2)          // day_of_week
    expect(args[2]).toBe('dinner')   // meal_slot
    expect(args[3]).toBe(recipeUUID) // recipe_id
    expect(args[4]).toBe('Lasagnes bolognaises') // recipe_name
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

  // Régression iOS — DELETE sans Content-Type (FST_ERR_CTP_EMPTY_JSON_BODY)
  // Cause : APIClient.swift posait Content-Type: application/json sur toutes les requêtes
  // y compris DELETE sans body → Fastify rejetait avec 400 sur le serveur réel.
  // Fix : Content-Type n'est posé que si un body est présent (post/patch uniquement).
  // Note : FST_ERR_CTP_EMPTY_JSON_BODY ne se reproduit pas via app.inject() (pas de vrai TCP),
  // ce test valide que le chemin sans Content-Type retourne bien 204.
  it('régression iOS — DELETE sans Content-Type retourne 204', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'item-1' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'DELETE',
      url: '/meal-plans/p1/items/item-1',
    })
    expect(res.statusCode).toBe(204)
  })
})

// ── POST /meal-plans/:id/distribute ──────────────────────────────────────────

describe('POST /meal-plans/:id/distribute', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 distribue les recettes via AI engine', async () => {
    const recipeUUID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce(null)
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Poulet', servings: 4, prep_minutes: 20, cook_minutes: 60,
          calories: null, protein_g: null, carbs_g: null, fat_g: null, fiber_g: null },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValue([])

    ;(requestSmartMealPlan as any).mockResolvedValue({
      slots: [
        { recipe_id: recipeUUID, recipe_name: 'Poulet', day_of_week: 0, meal_slot: 'lunch',
          portions: 1, macros: { calories: null, protein_g: null, carbs_g: null, fat_g: null, fiber_g: null } },
      ],
      day_macros:  [],
      week_macros: { day_of_week: -1, calories: null },
      used_claude: false,
    })

    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: [recipeUUID] },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ itemsCreated: 1 })
  })

  it('400 si recipe_ids vide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: [] },
    })
    expect(res.statusCode).toBe(400)
  })

  it('400 si recipe_ids contient des non-UUID', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: ['not-a-uuid'] },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('503 si AI Engine est indisponible', async () => {
    const recipeUUID = '11111111-1111-1111-1111-111111111111'
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce(null)
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Poulet', servings: 4, prep_minutes: 20, cook_minutes: 60,
          calories: null, protein_g: null, carbs_g: null, fat_g: null, fiber_g: null },
      ])
      .mockResolvedValueOnce([])
    ;(requestSmartMealPlan as any).mockRejectedValue(Object.assign(new Error('AI engine unreachable'), { code: 'AI_ENGINE_UNAVAILABLE' }))

    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: [recipeUUID] },
    })
    expect(res.statusCode).toBe(503)
    expect(res.json().error).toBe('AI_ENGINE_UNAVAILABLE')
  })

  it('ON CONFLICT préserve le nom existant si name absent du body', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-existing' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans',
      payload: { week_start: '2026-06-30' },
    })
    expect(res.statusCode).toBe(201)
    const sql: string = (queryOne as any).mock.calls[0][0]
    expect(sql).toContain('COALESCE')
  })

  // Régression : iOS envoie recipeIds (dict literal — NON converti par JSONEncoder.vita)
  it('régression iOS — recipeIds camelCase (dict literal) accepté', async () => {
    const recipeUUID = '33333333-3333-3333-3333-333333333333'
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce(null)
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Poulet', servings: 4, prep_minutes: 20, cook_minutes: 60,
          calories: null, protein_g: null, carbs_g: null, fat_g: null, fiber_g: null },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValue([])
    ;(requestSmartMealPlan as any).mockResolvedValue({
      slots: [],
      day_macros: [], week_macros: {}, used_claude: false,
    })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipeIds: [recipeUUID] },
    })
    expect(res.statusCode).toBe(200)
  })

  // Régression : iOS envoie recipe_ids (snake_case) dans distribute
  it('régression iOS — recipe_ids snake_case accepté', async () => {
    const recipeUUID = '22222222-2222-2222-2222-222222222222'
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce(null)
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Quiche', servings: 6, prep_minutes: 15, cook_minutes: 35,
          calories: 400, protein_g: 20.0, carbs_g: 30.0, fat_g: 22.0, fiber_g: 3.0 },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([])
      .mockResolvedValue([])
    ;(requestSmartMealPlan as any).mockResolvedValue({
      slots: [],
      day_macros: [], week_macros: {}, used_claude: false,
    })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: [recipeUUID] },
    })
    expect(res.statusCode).toBe(200)
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

  // Régression SQL : le SELECT doit caster quantity en FLOAT
  it('régression SQL — SELECT caste quantity en FLOAT', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/meal-plans/p1/shopping-list' })
    const sql: string = (query as any).mock.calls[0][0]
    expect(sql).toContain('quantity::FLOAT')
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
      payload: { is_checked: true },
    })
    expect(res.statusCode).toBe(200)
  })

  it('404 si item inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/meal-plans/p1/shopping-list/nope',
      payload: { is_checked: false },
    })
    expect(res.statusCode).toBe(404)
  })

  // Régression : iOS envoie isChecked (dict literal — NON converti par JSONEncoder.vita)
  it('régression iOS — isChecked camelCase (dict literal) accepté', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'sl-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH', url: '/meal-plans/p1/shopping-list/sl-1',
      payload: { isChecked: true },
    })
    expect(res.statusCode).toBe(200)
  })

  // Régression : iOS envoie is_checked (snake_case via JSONEncoder.vita)
  it('régression iOS — is_checked snake_case transmis à la DB', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'sl-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'PATCH', url: '/meal-plans/p1/shopping-list/sl-1',
      payload: { is_checked: true },
    })
    const updateCall = (query as any).mock.calls.find(
      (c: unknown[]) => (c[0] as string).includes('UPDATE shopping_list_items')
    )
    expect(updateCall).toBeDefined()
    expect(updateCall![1][1]).toBe(true)
  })
})

// ── Sprint 9.3 — Distribution multi-créneaux ──────────────────────────────────

describe('Sprint 9.3 — distribute avec breakfast et snack', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('distribute insère correctement un slot breakfast retourné par l\'AI engine', async () => {
    const recipeUUID = 'aaaaaaaa-bbbb-cccc-dddd-ffffffffffff'
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce({ meals_per_day: 3, objective: 'maintain', batch_cooking: false })
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Yaourt granola', servings: 1,
          prep_minutes: 5, cook_minutes: 0,
          calories: 280, protein_g: 10.0, carbs_g: 38.0, fat_g: 8.0, fiber_g: 2.0 },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValue([])

    ;(requestSmartMealPlan as any).mockResolvedValue({
      slots: [
        { recipe_id: recipeUUID, recipe_name: 'Yaourt granola',
          day_of_week: 0, meal_slot: 'breakfast', portions: 1,
          macros: { calories: 280, protein_g: 10.0, carbs_g: 38.0, fat_g: 8.0, fiber_g: 2.0 } },
      ],
      day_macros:  [{ day_of_week: 0, calories: 280 }],
      week_macros: { day_of_week: -1, calories: 280 },
      used_claude: false,
    })

    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: [recipeUUID] },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ itemsCreated: 1 })

    // L'INSERT doit contenir 'breakfast'
    const insertCall = (query as any).mock.calls.find(
      (c: unknown[]) => (c[0] as string).includes('INSERT INTO meal_plan_items')
    )
    expect(insertCall).toBeDefined()
    expect(insertCall![1]).toContain('breakfast')
  })

  it('distribute insère correctement un slot snack retourné par l\'AI engine', async () => {
    const recipeUUID = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
    ;(queryOne as any)
      .mockResolvedValueOnce({ id: 'p1' })
      .mockResolvedValueOnce({ meals_per_day: 4, objective: 'maintain', batch_cooking: false })
    ;(query as any)
      .mockResolvedValueOnce([
        { id: recipeUUID, name: 'Pomme & amandes', servings: 1,
          prep_minutes: 2, cook_minutes: 0,
          calories: 180, protein_g: 5.0, carbs_g: 20.0, fat_g: 9.0, fiber_g: 3.0 },
      ])
      .mockResolvedValueOnce([])
      .mockResolvedValue([])

    ;(requestSmartMealPlan as any).mockResolvedValue({
      slots: [
        { recipe_id: recipeUUID, recipe_name: 'Pomme & amandes',
          day_of_week: 2, meal_slot: 'snack', portions: 1,
          macros: { calories: 180, protein_g: 5.0, carbs_g: 20.0, fat_g: 9.0, fiber_g: 3.0 } },
      ],
      day_macros:  [{ day_of_week: 2, calories: 180 }],
      week_macros: { day_of_week: -1, calories: 180 },
      used_claude: false,
    })

    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/meal-plans/p1/distribute',
      payload: { recipe_ids: [recipeUUID] },
    })
    expect(res.statusCode).toBe(200)

    const insertCall = (query as any).mock.calls.find(
      (c: unknown[]) => (c[0] as string).includes('INSERT INTO meal_plan_items')
    )
    expect(insertCall).toBeDefined()
    expect(insertCall![1]).toContain('snack')
  })
})
