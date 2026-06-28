import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import { debugRoutes } from '../src/routes/debug.js'

// Mock db — les tests ne touchent jamais la base de données réelle
vi.mock('../src/db.js', () => ({
  query: vi.fn(),
  queryOne: vi.fn(),
}))

import { query } from '../src/db.js'

// ── Helpers ──────────────────────────────────────────────────────────

async function buildApp() {
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })

  app.addHook('onRequest', async (req, reply) => {
    try {
      await req.jwtVerify()
    } catch {
      reply.status(401).send({ error: 'UNAUTHORIZED' })
    }
  })

  await app.register(debugRoutes, { prefix: '/debug' })
  return app
}

function makeToken(app: ReturnType<typeof Fastify>) {
  return app.jwt.sign({ sub: 'user-debug-001' })
}

const MEMORY_ROW = {
  id: 'mem-uuid-1',
  type: 'goal',
  source: 'chat',
  importance: 4,
  confidence: 0.9,
  last_seen: new Date('2026-06-20T10:00:00Z'),
  created_at: new Date('2026-06-01T08:00:00Z'),
  updated_at: new Date('2026-06-20T10:00:00Z'),
  summary: 'Veut courir un semi-marathon d\'ici octobre',
}

// ── Setup ─────────────────────────────────────────────────────────────

let app: Awaited<ReturnType<typeof buildApp>>

beforeEach(async () => {
  app = await buildApp()
})

afterEach(async () => {
  vi.resetAllMocks()
  await app.close()
})

// ── GET /debug/memories ───────────────────────────────────────────────

describe('GET /debug/memories', () => {

  it('returns 200 with memories list and count', async () => {
    vi.mocked(query).mockResolvedValueOnce([MEMORY_ROW])

    const response = await app.inject({
      method: 'GET',
      url: '/debug/memories',
      headers: { authorization: `Bearer ${makeToken(app)}` },
    })

    expect(response.statusCode).toBe(200)
    const body = response.json()
    expect(body.count).toBe(1)
    expect(body.memories).toHaveLength(1)
    expect(body.memories[0].id).toBe('mem-uuid-1')
    expect(body.memories[0].type).toBe('goal')
    expect(body.memories[0].source).toBe('chat')
    expect(body.memories[0].importance).toBe(4)
    expect(body.memories[0].summary).toBe('Veut courir un semi-marathon d\'ici octobre')
  })

  it('queries with the authenticated userId, not a hardcoded value', async () => {
    vi.mocked(query).mockResolvedValueOnce([])

    await app.inject({
      method: 'GET',
      url: '/debug/memories',
      headers: { authorization: `Bearer ${makeToken(app)}` },
    })

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('vita_long_memories'),
      ['user-debug-001']
    )
  })

  it('SQL includes LIMIT 100 — never returns more', async () => {
    vi.mocked(query).mockResolvedValueOnce([])

    await app.inject({
      method: 'GET',
      url: '/debug/memories',
      headers: { authorization: `Bearer ${makeToken(app)}` },
    })

    const [sql] = vi.mocked(query).mock.calls[0]!
    expect(sql).toMatch(/LIMIT\s+100/i)
  })

  it('returns empty list when user has no memories', async () => {
    vi.mocked(query).mockResolvedValueOnce([])

    const response = await app.inject({
      method: 'GET',
      url: '/debug/memories',
      headers: { authorization: `Bearer ${makeToken(app)}` },
    })

    expect(response.statusCode).toBe(200)
    const body = response.json()
    expect(body.memories).toEqual([])
    expect(body.count).toBe(0)
  })

  it('returns multiple memories with correct count', async () => {
    const rows = [
      MEMORY_ROW,
      { ...MEMORY_ROW, id: 'mem-uuid-2', type: 'work', summary: 'Graphiste freelance' },
      { ...MEMORY_ROW, id: 'mem-uuid-3', type: 'family', summary: 'Relation complexe avec son père' },
    ]
    vi.mocked(query).mockResolvedValueOnce(rows)

    const response = await app.inject({
      method: 'GET',
      url: '/debug/memories',
      headers: { authorization: `Bearer ${makeToken(app)}` },
    })

    expect(response.statusCode).toBe(200)
    expect(response.json().count).toBe(3)
    expect(response.json().memories).toHaveLength(3)
  })

  it('returns 401 without JWT token', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/debug/memories',
    })

    expect(response.statusCode).toBe(401)
    expect(query).not.toHaveBeenCalled()
  })

  it('response includes all required debug fields', async () => {
    vi.mocked(query).mockResolvedValueOnce([MEMORY_ROW])

    const response = await app.inject({
      method: 'GET',
      url: '/debug/memories',
      headers: { authorization: `Bearer ${makeToken(app)}` },
    })

    const mem = response.json().memories[0]
    const requiredFields = ['id', 'type', 'source', 'importance', 'confidence', 'last_seen', 'created_at', 'updated_at', 'summary']
    for (const field of requiredFields) {
      expect(mem).toHaveProperty(field)
    }
  })
})
