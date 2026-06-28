import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import { dailyInsightRoutes } from '../src/routes/daily-insight.js'

// Mocks — jamais de vraie DB ni d'ai-engine dans les tests unitaires
vi.mock('../src/db.js', () => ({
  query: vi.fn(),
  queryOne: vi.fn(),
}))

vi.mock('../src/ai-client.js', () => ({
  requestDailyInsight: vi.fn(),
  AIEngineError: class AIEngineError extends Error {
    constructor(public status: number, public code: string, message: string) {
      super(message)
    }
  },
}))

import { queryOne } from '../src/db.js'
import { requestDailyInsight } from '../src/ai-client.js'

// ── Helpers ──────────────────────────────────────────────────────────────────

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
  await app.register(dailyInsightRoutes, { prefix: '/daily-insight' })
  return app
}

function makeToken(app: ReturnType<typeof Fastify>) {
  return app.jwt.sign({ sub: 'user-insight-001' })
}

const INSIGHT_ROW = {
  id: 'insight-uuid-1',
  user_id: 'user-insight-001',
  date: '2026-06-28',
  climate: 'DEMANDING',
  summary: 'Une journée dense qui a sollicité toute ton énergie.',
  drivers: ['Activité physique', 'Travail', 'Stress'],
  reflection: 'La journée a été marquée par une forte charge mentale et physique.',
  question: "Qu'est-ce qui t'a permis de tenir le rythme malgré la fatigue ?",
  created_at: '2026-06-28T10:00:00',
}

// ── GET /daily-insight/:date ──────────────────────────────────────────────────

describe('GET /daily-insight/:date', () => {
  let app: Awaited<ReturnType<typeof buildApp>>

  beforeEach(async () => {
    vi.resetAllMocks()
    app = await buildApp()
  })

  it('retourne 200 avec available:true quand un insight existe', async () => {
    vi.mocked(queryOne).mockResolvedValueOnce(INSIGHT_ROW)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/daily-insight/2026-06-28',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.available).toBe(true)
    expect(body.climate).toBe('DEMANDING')
    expect(body.summary).toBeDefined()
    expect(body.drivers).toBeInstanceOf(Array)
    expect(body.reflection).toBeDefined()
    expect(body.question).toBeDefined()
  })

  it('retourne { available: false } quand aucun insight existe', async () => {
    vi.mocked(queryOne).mockResolvedValueOnce(null)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/daily-insight/2026-06-28',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ available: false })
  })

  it('retourne 400 si le format de date est invalide', async () => {
    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/daily-insight/not-a-date',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('retourne 401 sans JWT', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/daily-insight/2026-06-28',
    })
    expect(res.statusCode).toBe(401)
  })

  it('passe le userId (sub JWT) dans la requête DB', async () => {
    vi.mocked(queryOne).mockResolvedValueOnce(null)
    const token = makeToken(app)

    await app.inject({
      method: 'GET',
      url: '/daily-insight/2026-06-28',
      headers: { authorization: `Bearer ${token}` },
    })

    const [, params] = vi.mocked(queryOne).mock.calls[0] as [string, unknown[]]
    expect((params as string[])[0]).toBe('user-insight-001')
  })

  it('passe la date dans la requête DB', async () => {
    vi.mocked(queryOne).mockResolvedValueOnce(null)
    const token = makeToken(app)

    await app.inject({
      method: 'GET',
      url: '/daily-insight/2026-06-28',
      headers: { authorization: `Bearer ${token}` },
    })

    const [, params] = vi.mocked(queryOne).mock.calls[0] as [string, unknown[]]
    expect((params as string[])[1]).toBe('2026-06-28')
  })

  it('expose tous les champs obligatoires dans la réponse', async () => {
    vi.mocked(queryOne).mockResolvedValueOnce(INSIGHT_ROW)
    const token = makeToken(app)

    const res = await app.inject({
      method: 'GET',
      url: '/daily-insight/2026-06-28',
      headers: { authorization: `Bearer ${token}` },
    })

    const body = res.json()
    for (const field of ['id', 'climate', 'summary', 'drivers', 'reflection', 'question', 'created_at']) {
      expect(body).toHaveProperty(field)
    }
  })
})

// ── POST /daily-insight/generate ─────────────────────────────────────────────

describe('POST /daily-insight/generate', () => {
  let app: Awaited<ReturnType<typeof buildApp>>

  beforeEach(async () => {
    vi.resetAllMocks()
    app = await buildApp()
  })

  it('retourne 200 avec available:true après génération réussie', async () => {
    vi.mocked(requestDailyInsight).mockResolvedValueOnce(null)
    vi.mocked(queryOne).mockResolvedValueOnce(INSIGHT_ROW)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ date: '2026-06-28' }),
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().available).toBe(true)
    expect(res.json().climate).toBe('DEMANDING')
  })

  it('appelle requestDailyInsight avec userId et date', async () => {
    vi.mocked(requestDailyInsight).mockResolvedValueOnce(null)
    vi.mocked(queryOne).mockResolvedValueOnce(null)

    const token = makeToken(app)
    await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ date: '2026-06-28' }),
    })

    expect(vi.mocked(requestDailyInsight)).toHaveBeenCalledWith(
      'user-insight-001',
      '2026-06-28'
    )
  })

  it('génère pour aujourd\'hui si aucune date fournie', async () => {
    vi.mocked(requestDailyInsight).mockResolvedValueOnce(null)
    vi.mocked(queryOne).mockResolvedValueOnce(null)

    const token = makeToken(app)
    await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({}),
    })

    const [userId, date] = vi.mocked(requestDailyInsight).mock.calls[0] as [string, string]
    expect(userId).toBe('user-insight-001')
    // Date du jour au format YYYY-MM-DD
    expect(date).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })

  it('retourne { available: false } si l\'ai-engine échoue mais ne plante pas', async () => {
    const { AIEngineError } = await import('../src/ai-client.js')
    vi.mocked(requestDailyInsight).mockRejectedValueOnce(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'AI engine down')
    )
    vi.mocked(queryOne).mockResolvedValueOnce(null)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ date: '2026-06-28' }),
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ available: false })
  })

  it('retourne 401 sans JWT', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      body: JSON.stringify({ date: '2026-06-28' }),
    })
    expect(res.statusCode).toBe(401)
  })

  it('retourne 400 si la date est mal formatée', async () => {
    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ date: '28/06/2026' }),
    })
    expect(res.statusCode).toBe(400)
  })

  it('est idempotent : appelle toujours requestDailyInsight (idempotence gérée côté ai-engine)', async () => {
    // L'idempotence est gérée côté ai-engine, pas côté data-service.
    // Le data-service appelle toujours l'ai-engine, qui retourne l'existant sans régénérer.
    vi.mocked(requestDailyInsight).mockResolvedValueOnce(null)
    vi.mocked(queryOne).mockResolvedValueOnce(INSIGHT_ROW)

    const token = makeToken(app)
    await app.inject({
      method: 'POST',
      url: '/daily-insight/generate',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ date: '2026-06-28' }),
    })

    expect(vi.mocked(requestDailyInsight)).toHaveBeenCalledTimes(1)
  })
})
