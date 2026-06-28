import { describe, it, expect, vi, beforeEach } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import { firstEncounterRoutes } from '../src/routes/first-encounter.js'

// Mocks — jamais de vraie DB ni d'ai-engine dans les tests unitaires
vi.mock('../src/ai-client.js', () => ({
  getFirstEncounterSession: vi.fn(),
  startFirstEncounter: vi.fn(),
  sendFirstEncounterMessage: vi.fn(),
  correctFirstEncounterPortrait: vi.fn(),
  AIEngineError: class AIEngineError extends Error {
    constructor(public status: number, public code: string, message: string) {
      super(message)
      this.name = 'AIEngineError'
    }
  },
}))

import {
  getFirstEncounterSession,
  startFirstEncounter,
  sendFirstEncounterMessage,
  correctFirstEncounterPortrait,
} from '../src/ai-client.js'

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
  await app.register(firstEncounterRoutes, { prefix: '/first-encounter' })
  return app
}

function makeToken(app: ReturnType<typeof Fastify>) {
  return app.jwt.sign({ sub: 'user-encounter-001' })
}

const SESSION_IN_PROGRESS = {
  status: 'in_progress',
  topic_index: 2,
  exchange_count: 3,
  exchanges: [
    { role: 'vita', content: 'Bonjour.', topic: 'situation_actuelle', created_at: '2026-06-28T10:00:00Z' },
    { role: 'user', content: 'Je vais bien.', topic: 'situation_actuelle', created_at: '2026-06-28T10:01:00Z' },
  ],
}

const SESSION_COMPLETED = {
  status: 'completed',
  portrait: 'Il me semble percevoir une personne curieuse et déterminée...',
  completed_at: '2026-06-28T11:00:00Z',
}

const MESSAGE_RESPONSE = {
  vita_response: "Qu'est-ce qui compte vraiment pour toi dans la vie ?",
  topic: 'valeurs',
  exchange_number: 4,
  is_complete: false,
  portrait: null,
}

const COMPLETE_RESPONSE = {
  vita_response: 'Je vais maintenant composer ma première impression de toi…',
  topic: 'attentes_vita',
  exchange_number: 10,
  is_complete: true,
  portrait: 'Il me semble percevoir une personne curieuse et engagée dans ses projets...',
}

// ── GET /first-encounter/session ─────────────────────────────────────────────

describe('GET /first-encounter/session', () => {
  let app: Awaited<ReturnType<typeof buildApp>>

  beforeEach(async () => {
    vi.resetAllMocks()
    app = await buildApp()
  })

  it('retourne 200 avec la session en cours', async () => {
    vi.mocked(getFirstEncounterSession).mockResolvedValueOnce(SESSION_IN_PROGRESS as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/first-encounter/session',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().status).toBe('in_progress')
    expect(res.json().exchange_count).toBe(3)
    expect(res.json().exchanges).toHaveLength(2)
  })

  it('retourne { status: not_started } quand aucune session', async () => {
    vi.mocked(getFirstEncounterSession).mockResolvedValueOnce({ status: 'not_started' } as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/first-encounter/session',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ status: 'not_started' })
  })

  it('retourne la session complète avec portrait', async () => {
    vi.mocked(getFirstEncounterSession).mockResolvedValueOnce(SESSION_COMPLETED as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/first-encounter/session',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().status).toBe('completed')
    expect(res.json().portrait).toBeDefined()
  })

  it('retourne not_started si ai-engine inaccessible', async () => {
    const { AIEngineError } = await import('../src/ai-client.js')
    vi.mocked(getFirstEncounterSession).mockRejectedValueOnce(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'AI engine down')
    )

    const token = makeToken(app)
    const res = await app.inject({
      method: 'GET',
      url: '/first-encounter/session',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ status: 'not_started' })
  })

  it('retourne 401 sans JWT', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/first-encounter/session',
    })
    expect(res.statusCode).toBe(401)
  })

  it("passe l'userId (sub JWT) à getFirstEncounterSession", async () => {
    vi.mocked(getFirstEncounterSession).mockResolvedValueOnce({ status: 'not_started' } as any)
    const token = makeToken(app)

    await app.inject({
      method: 'GET',
      url: '/first-encounter/session',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(vi.mocked(getFirstEncounterSession)).toHaveBeenCalledWith('user-encounter-001')
  })
})

// ── POST /first-encounter/start ───────────────────────────────────────────────

describe('POST /first-encounter/start', () => {
  let app: Awaited<ReturnType<typeof buildApp>>

  beforeEach(async () => {
    vi.resetAllMocks()
    app = await buildApp()
  })

  it('retourne 201 avec le message d\'ouverture', async () => {
    vi.mocked(startFirstEncounter).mockResolvedValueOnce({
      already_started: false,
      vita_opening: 'Bonjour. Je suis contente que tu sois là.',
      session_id: 'session-uuid-1',
    } as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/start',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(201)
    expect(res.json().vita_opening).toBeDefined()
    expect(res.json().session_id).toBe('session-uuid-1')
  })

  it('retourne 201 avec already_started si session existante', async () => {
    vi.mocked(startFirstEncounter).mockResolvedValueOnce({
      already_started: true,
      ...SESSION_IN_PROGRESS,
    } as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/start',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(201)
    expect(res.json().already_started).toBe(true)
  })

  it('retourne 401 sans JWT', async () => {
    const res = await app.inject({ method: 'POST', url: '/first-encounter/start' })
    expect(res.statusCode).toBe(401)
  })

  it('retourne 503 si ai-engine inaccessible', async () => {
    const { AIEngineError } = await import('../src/ai-client.js')
    vi.mocked(startFirstEncounter).mockRejectedValueOnce(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/start',
      headers: { authorization: `Bearer ${token}` },
    })

    expect(res.statusCode).toBe(503)
    expect(res.json().error).toBe('SERVICE_UNAVAILABLE')
  })
})

// ── POST /first-encounter/message ─────────────────────────────────────────────

describe('POST /first-encounter/message', () => {
  let app: Awaited<ReturnType<typeof buildApp>>

  beforeEach(async () => {
    vi.resetAllMocks()
    app = await buildApp()
  })

  it('retourne 200 avec la réponse VITA', async () => {
    vi.mocked(sendFirstEncounterMessage).mockResolvedValueOnce(MESSAGE_RESPONSE as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ content: "Je traverse une période de transition professionnelle." }),
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().vita_response).toBeDefined()
    expect(res.json().topic).toBe('valeurs')
    expect(res.json().exchange_number).toBe(4)
    expect(res.json().is_complete).toBe(false)
    expect(res.json().portrait).toBeNull()
  })

  it('retourne 200 avec portrait quand is_complete = true', async () => {
    vi.mocked(sendFirstEncounterMessage).mockResolvedValueOnce(COMPLETE_RESPONSE as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ content: "J'attends que VITA m'aide à me comprendre." }),
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().is_complete).toBe(true)
    expect(res.json().portrait).toBeDefined()
    expect(res.json().portrait.length).toBeGreaterThan(0)
  })

  it('retourne 400 si content vide', async () => {
    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ content: "" }),
    })

    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('retourne 400 si content absent', async () => {
    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({}),
    })

    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('retourne 401 sans JWT', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      body: JSON.stringify({ content: "Bonjour" }),
    })
    expect(res.statusCode).toBe(401)
  })

  it('passe userId et content à sendFirstEncounterMessage', async () => {
    vi.mocked(sendFirstEncounterMessage).mockResolvedValueOnce(MESSAGE_RESPONSE as any)
    const token = makeToken(app)

    await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ content: "Mon message important" }),
    })

    expect(vi.mocked(sendFirstEncounterMessage)).toHaveBeenCalledWith(
      'user-encounter-001',
      'Mon message important'
    )
  })

  it('retourne 503 si ai-engine inaccessible', async () => {
    const { AIEngineError } = await import('../src/ai-client.js')
    vi.mocked(sendFirstEncounterMessage).mockRejectedValueOnce(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/message',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ content: "Mon message" }),
    })

    expect(res.statusCode).toBe(503)
  })
})

// ── POST /first-encounter/correct ─────────────────────────────────────────────

describe('POST /first-encounter/correct', () => {
  let app: Awaited<ReturnType<typeof buildApp>>

  beforeEach(async () => {
    vi.resetAllMocks()
    app = await buildApp()
  })

  it('retourne 200 avec le portrait corrigé', async () => {
    vi.mocked(correctFirstEncounterPortrait).mockResolvedValueOnce({
      portrait: 'Portrait révisé et plus précis...',
    } as any)

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/correct',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ correction: "Tu as dit que j'aimais la montagne, c'est la mer en fait." }),
    })

    expect(res.statusCode).toBe(200)
    expect(res.json().portrait).toBe('Portrait révisé et plus précis...')
  })

  it('retourne 400 si correction vide', async () => {
    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/correct',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ correction: "" }),
    })

    expect(res.statusCode).toBe(400)
  })

  it('retourne 401 sans JWT', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/correct',
      body: JSON.stringify({ correction: "Correction" }),
    })
    expect(res.statusCode).toBe(401)
  })

  it('passe userId et correction à correctFirstEncounterPortrait', async () => {
    vi.mocked(correctFirstEncounterPortrait).mockResolvedValueOnce({ portrait: '...' } as any)
    const token = makeToken(app)

    await app.inject({
      method: 'POST',
      url: '/first-encounter/correct',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ correction: "En fait je suis ingénieure, pas architecte." }),
    })

    expect(vi.mocked(correctFirstEncounterPortrait)).toHaveBeenCalledWith(
      'user-encounter-001',
      'En fait je suis ingénieure, pas architecte.'
    )
  })

  it('retourne 503 si ai-engine inaccessible', async () => {
    const { AIEngineError } = await import('../src/ai-client.js')
    vi.mocked(correctFirstEncounterPortrait).mockRejectedValueOnce(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )

    const token = makeToken(app)
    const res = await app.inject({
      method: 'POST',
      url: '/first-encounter/correct',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ correction: "Une correction" }),
    })

    expect(res.statusCode).toBe(503)
  })
})
