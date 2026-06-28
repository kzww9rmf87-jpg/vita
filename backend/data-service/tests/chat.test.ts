import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import { chatRoutes } from '../src/routes/chat.js'

// Mock ai-client — les tests de chat ne testent pas l'ai-engine
vi.mock('../src/ai-client.js', () => ({
  sendChatMessage: vi.fn(),
  AIEngineError: class AIEngineError extends Error {
    status: number
    code: string
    constructor(status: number, code: string, message: string) {
      super(message)
      this.name = 'AIEngineError'
      this.status = status
      this.code = code
    }
  },
}))

import { sendChatMessage, AIEngineError } from '../src/ai-client.js'

// ── Helpers ─────────────────────────────────────────────────────────

async function buildApp() {
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })

  // Middleware JWT minimal pour les tests
  app.addHook('onRequest', async (req) => {
    try {
      await req.jwtVerify()
    } catch {
      // Laisse passer pour les tests sans token valide
    }
  })

  await app.register(chatRoutes, { prefix: '/chat' })
  return app
}

function makeToken(app: ReturnType<typeof Fastify>) {
  return app.jwt.sign({ sub: 'user-test-123' })
}

// ── Setup ────────────────────────────────────────────────────────────

let app: Awaited<ReturnType<typeof buildApp>>

beforeEach(async () => {
  app = await buildApp()
})

afterEach(async () => {
  vi.resetAllMocks()
  await app.close()
})

// ── POST /chat ────────────────────────────────────────────────────────

describe('POST /chat', () => {

  it('returns 200 with ai-engine response', async () => {
    const aiResponse = {
      conversation_id: 'conv-abc',
      response: 'Tu dors mieux depuis que tu cours le matin.',
      tokens_used: 312,
    }
    vi.mocked(sendChatMessage).mockResolvedValue(aiResponse as any)

    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Comment je dors en ce moment ?' },
    })

    expect(response.statusCode).toBe(200)
    expect(response.json()).toMatchObject({
      conversation_id: 'conv-abc',
      response: 'Tu dors mieux depuis que tu cours le matin.',
    })
  })

  it('passes conversationId to ai-engine when provided', async () => {
    vi.mocked(sendChatMessage).mockResolvedValue({
      conversation_id: 'conv-existing',
      response: 'Suite de la conversation.',
      tokens_used: 150,
    } as any)

    await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Et le sport ?', conversationId: '00000000-0000-0000-0000-000000000001' },
    })

    expect(sendChatMessage).toHaveBeenCalledWith(
      'user-test-123',
      'Et le sport ?',
      '00000000-0000-0000-0000-000000000001'
    )
  })

  it('passes undefined conversationId for first message', async () => {
    vi.mocked(sendChatMessage).mockResolvedValue({
      conversation_id: 'conv-new',
      response: 'Bonjour.',
      tokens_used: 50,
    } as any)

    await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Bonjour VITA' },
    })

    expect(sendChatMessage).toHaveBeenCalledWith(
      'user-test-123',
      'Bonjour VITA',
      undefined
    )
  })

  it('returns 400 for empty message', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: '' },
    })

    expect(response.statusCode).toBe(400)
    expect(response.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
    expect(sendChatMessage).not.toHaveBeenCalled()
  })

  it('returns 400 for message exceeding 2000 characters', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'a'.repeat(2001) },
    })

    expect(response.statusCode).toBe(400)
    expect(response.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
  })

  it('returns 400 for invalid conversationId format', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Bonjour', conversationId: 'not-a-uuid' },
    })

    expect(response.statusCode).toBe(400)
    expect(response.json()).toMatchObject({ error: 'VALIDATION_ERROR' })
  })

  it('returns 502 when ai-engine is unreachable', async () => {
    const { AIEngineError: AiErr } = await import('../src/ai-client.js')
    vi.mocked(sendChatMessage).mockRejectedValue(
      new AiErr(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )

    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Bonjour' },
    })

    expect(response.statusCode).toBe(502)
    expect(response.json()).toMatchObject({ error: 'AI_ENGINE_UNREACHABLE' })
  })

  it('returns 503 when ai-engine rejects service token (config error)', async () => {
    const { AIEngineError: AiErr } = await import('../src/ai-client.js')
    vi.mocked(sendChatMessage).mockRejectedValue(
      new AiErr(401, 'UNAUTHORIZED', 'bad token')
    )

    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Bonjour' },
    })

    // 401 de l'ai-engine = mauvaise config, pas une erreur utilisateur → 503
    expect(response.statusCode).toBe(503)
  })

  it('returns 504 on ai-engine timeout', async () => {
    const { AIEngineError: AiErr } = await import('../src/ai-client.js')
    vi.mocked(sendChatMessage).mockRejectedValue(
      new AiErr(504, 'AI_ENGINE_TIMEOUT', 'timeout')
    )

    const response = await app.inject({
      method: 'POST',
      url: '/chat',
      headers: { authorization: `Bearer ${makeToken(app)}` },
      body: { message: 'Bonjour' },
    })

    expect(response.statusCode).toBe(504)
    expect(response.json()).toMatchObject({ error: 'AI_ENGINE_TIMEOUT' })
  })
})
