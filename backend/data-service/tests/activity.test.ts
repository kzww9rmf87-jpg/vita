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
  const { activityRoutes } = await import('../src/routes/activity.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    (req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(activityRoutes, { prefix: '/activity' })
  return app
}

describe('POST /activity', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates a session and returns id', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-id-1' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/activity',
      payload: { date: '2026-06-28', activity_name: 'Course', duration_minutes: 45 },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'session-id-1' })
  })

  it('400 when activityName missing', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/activity',
      payload: { date: '2026-06-28' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 when rpe out of range', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/activity',
      payload: { date: '2026-06-28', activity_name: 'X', rpe: 11 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('inserts exercise sets when provided', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url: '/activity',
      payload: {
        date: '2026-06-28',
        activity_name: 'Musculation',
        sets: [{ exercise_name: 'Squat', set_number: 1, reps: 10, weight_kg: 100 }],
      },
    })
    // queryOne pour INSERT session, query pour INSERT sets
    expect((query as any).mock.calls.length).toBeGreaterThan(0)
  })

  it('does not include training_load in response', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'x' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/activity',
      payload: { date: '2026-06-28', activity_name: 'Yoga' },
    })
    const body = res.json()
    expect(body).not.toHaveProperty('training_load')
    expect(body).not.toHaveProperty('fitness_score')
  })
})

describe('GET /activity/history', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns sessions list', async () => {
    ;(query as any).mockResolvedValue([
      { id: 'x', activity_name: 'Course', duration_minutes: 45 },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/activity/history' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })

  it('caps days at 365', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/activity/history?days=500' })
    expect((query as any).mock.calls[0][1][1]).toBe(365)
  })
})

describe('DELETE /activity/:id', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('204 when session found and deleted', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/activity/session-1' })
    expect(res.statusCode).toBe(204)
  })

  it('404 when session not found', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/activity/nonexistent' })
    expect(res.statusCode).toBe(404)
  })

  it('passes userId for ownership check', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'x' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'DELETE', url: '/activity/session-1' })
    expect((queryOne as any).mock.calls[0][1]).toContain('user-uuid-123')
  })
})

describe('PATCH /activity/:id', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('200 when session exists', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/activity/session-1',
      payload: { duration_minutes: 60 },
    })
    expect(res.statusCode).toBe(200)
  })

  it('404 when session not found', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/activity/nonexistent',
      payload: { duration_minutes: 60 },
    })
    expect(res.statusCode).toBe(404)
  })

  it('does not clear optional fields not present in patch body', async () => {
    ;(queryOne as any).mockResolvedValueOnce({ id: 'session-1' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'PATCH',
      url: '/activity/session-1',
      payload: { duration_minutes: 60 },
    })
    const sql: string = (query as any).mock.calls[0][0]
    expect(sql).not.toContain('rpe')
    expect(sql).not.toContain('notes')
    expect(sql).not.toContain('calories_burned')
    expect(sql).not.toContain('hr_avg_bpm')
  })
})

describe('GET /activity/session/:id/sets', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns sets for a session', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-1' })
    ;(query as any).mockResolvedValue([
      { exercise_name: 'Squat', set_number: 1, reps: 10 },
    ])
    const app = await makeApp()
    const res = await app.inject({
      method: 'GET',
      url: '/activity/session/session-1/sets',
    })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })

  it('404 if session not owned by user', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'GET',
      url: '/activity/session/other-session/sets',
    })
    expect(res.statusCode).toBe(404)
  })
})
