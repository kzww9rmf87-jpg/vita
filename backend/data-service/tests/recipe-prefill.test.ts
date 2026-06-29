import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

vi.mock('../src/ai-client.js', () => ({
  requestRecipePrefill: vi.fn(),
  AIEngineError: class AIEngineError extends Error {
    constructor(public status: number, public code: string, message: string) {
      super(message)
      this.name = 'AIEngineError'
    }
  },
}))

const { requestRecipePrefill } = await import('../src/ai-client.js') as {
  requestRecipePrefill: ReturnType<typeof vi.fn>
}
const { AIEngineError } = await import('../src/ai-client.js') as {
  AIEngineError: new (status: number, code: string, message: string) => Error & { status: number; code: string }
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { nutritionRoutes } = await import('../src/routes/nutrition.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(nutritionRoutes, { prefix: '/nutrition' })
  return app
}

const MOCK_PREFILL = {
  name: 'Lasagnes bolognaise',
  servings: 6,
  prep_minutes: 20,
  cook_minutes: 45,
  notes: 'Recette familiale.',
  calories_per_serving: 480,
  protein_g_per_serving: 28.0,
  carbs_g_per_serving: 42.0,
  fat_g_per_serving: 22.0,
  fiber_g_per_serving: 3.5,
  ingredients: [
    { name: 'Pâtes à lasagnes', quantity_g: 300, sort_order: 0 },
    { name: 'Bœuf haché',       quantity_g: 500, sort_order: 1 },
  ],
  is_estimated: true,
}

describe('POST /nutrition/recipes/prefill', () => {
  beforeEach(() => { vi.resetAllMocks() })

  it('200 retourne la recette pré-remplie', async () => {
    ;(requestRecipePrefill as any).mockResolvedValue(MOCK_PREFILL)
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Lasagnes bolognaise', servings: 6 },
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.name).toBe('Lasagnes bolognaise')
    expect(body.is_estimated).toBe(true)
    expect(body.calories_per_serving).toBe(480)
    expect(body.ingredients).toHaveLength(2)
  })

  it('200 sans portions (défaut)', async () => {
    ;(requestRecipePrefill as any).mockResolvedValue({ ...MOCK_PREFILL, servings: 4 })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Quiche lorraine' },
    })
    expect(res.statusCode).toBe(200)
    expect(requestRecipePrefill).toHaveBeenCalledWith('Quiche lorraine', undefined)
  })

  it('400 si recipeName vide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: '' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si recipeName manquant', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: {},
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si recipeName trop long', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'x'.repeat(201) },
    })
    expect(res.statusCode).toBe(400)
  })

  it('400 si servings hors bornes', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Soupe', servings: 0 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('503 si AI engine indisponible (AIEngineError 502)', async () => {
    ;(requestRecipePrefill as any).mockRejectedValue(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Soupe' },
    })
    expect(res.statusCode).toBe(503)
    expect(res.json().error).toBe('AI_ENGINE_UNAVAILABLE')
  })

  it('503 si AI engine timeout (AIEngineError 504)', async () => {
    ;(requestRecipePrefill as any).mockRejectedValue(
      new AIEngineError(504, 'AI_ENGINE_TIMEOUT', 'timeout')
    )
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Soupe' },
    })
    expect(res.statusCode).toBe(503)
  })

  it('503 si erreur réseau inattendue', async () => {
    ;(requestRecipePrefill as any).mockRejectedValue(new Error('network error'))
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Soupe' },
    })
    expect(res.statusCode).toBe(503)
    expect(res.json().error).toBe('AI_ENGINE_UNAVAILABLE')
  })

  it('transmet le recipeName vers AI engine', async () => {
    ;(requestRecipePrefill as any).mockResolvedValue(MOCK_PREFILL)
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Lasagnes bolognaise', servings: 6 },
    })
    expect(requestRecipePrefill).toHaveBeenCalledWith('Lasagnes bolognaise', 6)
  })

  it('is_estimated est toujours présent dans la réponse', async () => {
    ;(requestRecipePrefill as any).mockResolvedValue(MOCK_PREFILL)
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url:    '/nutrition/recipes/prefill',
      payload: { recipeName: 'Tarte aux pommes' },
    })
    expect(res.json().is_estimated).toBe(true)
  })
})
