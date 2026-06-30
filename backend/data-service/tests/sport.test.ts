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
  const { sportRoutes } = await import('../src/routes/sport.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(sportRoutes, { prefix: '/sport' })
  return app
}

// ── GET /sport/profile ────────────────────────────────────────────────────────

describe('GET /sport/profile', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns 404 when profile does not exist', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sport/profile' })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NOT_FOUND')
  })

  it('returns profile when it exists', async () => {
    ;(queryOne as any).mockResolvedValue({
      id: 'profile-id-1',
      fitness_level: 'intermediate',
      preferred_activities: ['Course', 'Yoga'],
      sessions_per_week: 4,
      session_duration_min: 60,
      available_days: [1, 3, 5],
      context: null,
      created_at: '2026-06-30T00:00:00Z',
      updated_at: '2026-06-30T00:00:00Z',
    })
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sport/profile' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({
      id: 'profile-id-1',
      fitnessLevel: 'intermediate',
      sessionsPerWeek: 4,
    })
  })
})

// ── PUT /sport/profile ────────────────────────────────────────────────────────

describe('PUT /sport/profile', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates profile when none exists (201)', async () => {
    ;(queryOne as any)
      .mockResolvedValueOnce(null)           // SELECT existant → null
      .mockResolvedValueOnce({ id: 'new-id' }) // INSERT RETURNING
    const app = await makeApp()
    const res = await app.inject({
      method: 'PUT',
      url: '/sport/profile',
      payload: {
        fitness_level: 'beginner',
        sessions_per_week: 3,
      },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'new-id' })
  })

  it('updates existing profile (200)', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'existing-id' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'PUT',
      url: '/sport/profile',
      payload: { sessions_per_week: 5 },
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ id: 'existing-id' })
  })

  it('400 on invalid fitness_level', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'PUT',
      url: '/sport/profile',
      payload: { fitness_level: 'superhuman' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })
})

// ── GET /sport/training-plans ─────────────────────────────────────────────────

describe('GET /sport/training-plans', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns empty array when no plans', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sport/training-plans' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual([])
  })

  it('returns plans with camelCase fields', async () => {
    ;(query as any).mockResolvedValue([
      { id: 'plan-1', name: 'Semaine A', description: null, is_active: true, created_at: '2026-06-30T00:00:00Z' },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sport/training-plans' })
    expect(res.statusCode).toBe(200)
    expect(res.json()[0]).toMatchObject({ id: 'plan-1', name: 'Semaine A', isActive: true })
  })
})

// ── POST /sport/training-plans ────────────────────────────────────────────────

describe('POST /sport/training-plans', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates a plan and returns 201', async () => {
    ;(query as any).mockResolvedValue([])    // INSERT sessions
    ;(queryOne as any).mockResolvedValue({ id: 'plan-new' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sport/training-plans',
      payload: {
        name: 'Semaine force',
        is_active: false,
        sessions: [
          { day_of_week: 1, activity_name: 'Musculation', duration_min: 60 },
        ],
      },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'plan-new' })
  })

  it('400 on missing name', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sport/training-plans',
      payload: { isActive: false, sessions: [] },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 on name too long', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sport/training-plans',
      payload: { name: 'x'.repeat(101), isActive: false, sessions: [] },
    })
    expect(res.statusCode).toBe(400)
  })
})

// ── DELETE /sport/training-plans/:id ─────────────────────────────────────────

describe('DELETE /sport/training-plans/:id', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('deletes plan and returns 204', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'plan-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/sport/training-plans/plan-1' })
    expect(res.statusCode).toBe(204)
  })

  it('404 when plan does not belong to user', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/sport/training-plans/other-plan' })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NOT_FOUND')
  })
})
