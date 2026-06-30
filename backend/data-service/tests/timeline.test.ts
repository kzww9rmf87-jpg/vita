import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

const { query } = await import('../src/db.js') as {
  query: ReturnType<typeof vi.fn>
  queryOne: ReturnType<typeof vi.fn>
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { timelineRoutes } = await import('../src/routes/timeline.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(timelineRoutes, { prefix: '/timeline' })
  return app
}

describe('GET /timeline', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns 200 with events array', async () => {
    ;(query as any).mockResolvedValue([
      { id: 'checkin-1', type: 'checkin', time: '2026-06-30T07:00:00Z', title: 'Check-in du matin', subtitle: 'Énergie 4/5', icon: 'sun.max.fill', color_key: 'accent', meta: {} },
    ])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/timeline?date=2026-06-30' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toHaveLength(1)
  })

  it('400 on invalid date format', async () => {
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/timeline?date=30/06/2026' })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('SQL query does not reference adherence_score', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/timeline?date=2026-06-30' })
    const sql: string = (query as any).mock.calls[0][0]
    expect(sql).not.toContain('adherence_score')
  })

  it('passes userId and date to DB', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    await app.inject({ method: 'GET', url: '/timeline?date=2026-06-28' })
    const params: unknown[] = (query as any).mock.calls[0][1]
    expect(params).toContain('user-uuid-123')
    expect(params).toContain('2026-06-28')
  })

  it('defaults to today when no date given', async () => {
    ;(query as any).mockResolvedValue([])
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/timeline' })
    expect(res.statusCode).toBe(200)
    const params: unknown[] = (query as any).mock.calls[0][1]
    // la date par défaut doit être au format YYYY-MM-DD
    expect(params[1]).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })
})
