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
  const { pantryRoutes } = await import('../src/routes/pantry.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(pantryRoutes, { prefix: '/pantry' })
  return app
}

// ── GET /pantry ───────────────────────────────────────────────────────────────

describe('GET /pantry', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('retourne la liste triée', async () => {
    const items = [
      { id: 'p1', ingredient_name: 'ail', notes: null },
      { id: 'p2', ingredient_name: 'sel', notes: 'gros sel' },
    ]
    ;(query as any).mockResolvedValue(items)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/pantry' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(2)
  })

  it('passe user_id depuis JWT', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/pantry' })
    const args: unknown[] = (query as any).mock.calls[0][1]
    expect(args[0]).toBe('user-uuid-123')
  })
})

// ── POST /pantry ──────────────────────────────────────────────────────────────

describe('POST /pantry', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('201 ajoute un ingrédient', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'pantry-new' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/pantry',
      payload: { ingredient_name: "Huile d'olive" },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'pantry-new' })
  })

  it('400 si ingredient_name manquant', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/pantry',
      payload: {},
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 si ingredient_name vide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/pantry',
      payload: { ingredient_name: '' },
    })
    expect(res.statusCode).toBe(400)
  })

  it('trim le nom avant insertion', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    const app = await makeApp()
    await app.inject({
      method: 'POST', url: '/pantry',
      payload: { ingredient_name: '  Sel  ' },
    })
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(args[1]).toBe('Sel')
  })

  // Régression : iOS envoie ingredient_name (snake_case — si struct Encodable)
  it('régression iOS — payload snake_case ingredient_name accepté', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'pantry-regress' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/pantry',
      payload: { ingredient_name: 'Ail' },
    })
    expect(res.statusCode).toBe(201)
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(args[1]).toBe('Ail')
  })

  // Régression : iOS envoie ingredientName (dict literal — NON converti par JSONEncoder.vita)
  it('régression iOS — payload camelCase ingredientName (dict literal) accepté', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'pantry-camel' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/pantry',
      payload: { ingredientName: 'Huile d\'olive' },
    })
    expect(res.statusCode).toBe(201)
    const args: unknown[] = (queryOne as any).mock.calls[0][1]
    expect(args[1]).toBe("Huile d'olive")
  })
})

// ── DELETE /pantry/:id ────────────────────────────────────────────────────────

describe('DELETE /pantry/:id', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('204 supprime un item', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'p1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/pantry/p1' })
    expect(res.statusCode).toBe(204)
  })

  it('404 si item inconnu', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/pantry/nope' })
    expect(res.statusCode).toBe(404)
  })

  it('404 si item appartient à un autre utilisateur', async () => {
    // queryOne retourne null car WHERE user_id = 'user-uuid-123' ne matche pas
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/pantry/other-user-item' })
    expect(res.statusCode).toBe(404)
  })
})
