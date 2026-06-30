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
  const { sleepRoutes } = await import('../src/routes/sleep.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    (req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(sleepRoutes, { prefix: '/sleep' })
  return app
}

describe('POST /sleep', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('creates a sleep entry with quality_score', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'entry-id-1' })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sleep',
      payload: { date: '2026-06-28', quality_score: 4, duration_minutes: 480 },
    })
    expect(res.statusCode).toBe(201)
    expect(res.json()).toMatchObject({ id: 'entry-id-1' })
  })

  it('400 when qualityScore is missing', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sleep',
      payload: { date: '2026-06-28' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('400 when qualityScore out of range', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sleep',
      payload: { date: '2026-06-28', quality_score: 6 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('400 when date format invalid', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST',
      url: '/sleep',
      payload: { date: '28/06/2026', qualityScore: 3 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('computes duration from bedtime/wakeTime when durationMinutes absent', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'x' })
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url: '/sleep',
      payload: {
        date: '2026-06-28',
        quality_score: 3,
        bedtime: '2026-06-27T22:00:00Z',
        wake_time: '2026-06-28T06:30:00Z',
      },
    })
    const call = (queryOne as any).mock.calls[0]
    // durationMinutes passed to DB = 510
    expect(call[1]).toContain(510)
  })

  it('passes userId to DB from JWT', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'x' })
    const app = await makeApp()
    await app.inject({
      method: 'POST',
      url: '/sleep',
      payload: { date: '2026-06-28', quality_score: 3 },
    })
    expect((queryOne as any).mock.calls[0][1][0]).toBe('user-uuid-123')
  })
})

describe('GET /sleep/history', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns entries list', async () => {
    ;(query as any).mockResolvedValue([
      { date: '2026-06-28', quality_score: 4, duration_minutes: 480 },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sleep/history' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })

  it('defaults to 30 days', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/sleep/history' })
    expect((query as any).mock.calls[0][1][1]).toBe(30)
  })

  it('caps days at 365', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/sleep/history?days=999' })
    expect((query as any).mock.calls[0][1][1]).toBe(365)
  })
})

describe('DELETE /sleep/:date', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('204 on successful delete', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/sleep/2026-06-28' })
    expect(res.statusCode).toBe(204)
  })

  it('400 on invalid date format', async () => {
    const app = await makeApp()
    const res = await app.inject({ method: 'DELETE', url: '/sleep/invalid' })
    expect(res.statusCode).toBe(400)
  })

  it('passes userId and date to DB', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'DELETE', url: '/sleep/2026-06-28' })
    const call = (query as any).mock.calls[0]
    expect(call[1]).toContain('user-uuid-123')
    expect(call[1]).toContain('2026-06-28')
  })
})

describe('PATCH /sleep/:date', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('200 when entry exists', async () => {
    ;(queryOne as any).mockResolvedValueOnce({ id: 'x' })  // SELECT existing
    ;(query as any).mockResolvedValue([])                    // UPDATE
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/sleep/2026-06-28',
      payload: { quality_score: 5 },
    })
    expect(res.statusCode).toBe(200)
  })

  it('404 when entry not found', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/sleep/2026-06-28',
      payload: { quality_score: 5 },
    })
    expect(res.statusCode).toBe(404)
  })

  it('400 when quality_score out of range in patch', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'PATCH',
      url: '/sleep/2026-06-28',
      payload: { quality_score: 0 },
    })
    expect(res.statusCode).toBe(400)
  })

  it('does not clear optional fields not present in patch body', async () => {
    ;(queryOne as any).mockResolvedValueOnce({ id: 'x' })
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({
      method: 'PATCH',
      url: '/sleep/2026-06-28',
      payload: { quality_score: 5 },
    })
    const sql: string = (query as any).mock.calls[0][0]
    // Un PATCH avec seulement qualityScore ne doit pas toucher bedtime, notes, etc.
    expect(sql).not.toContain('bedtime')
    expect(sql).not.toContain('wake_time')
    expect(sql).not.toContain('notes')
    expect(sql).not.toContain('duration_minutes')
  })
})
