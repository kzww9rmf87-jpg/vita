import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { requestRecommendation, sendChatMessage, AIEngineError } from '../src/ai-client.js'

// ── Helpers ─────────────────────────────────────────────────────────

function mockFetch(status: number, body: unknown) {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(body),
  })
}

function mockFetchNetworkError(name = 'Error') {
  const err = new Error('network failure')
  err.name = name
  return vi.fn().mockRejectedValue(err)
}

// ── Setup ────────────────────────────────────────────────────────────

beforeEach(() => {
  process.env.AI_ENGINE_URL = 'http://ai-engine:3003'
  process.env.AI_SERVICE_TOKEN = 'test-token-secret'
})

afterEach(() => {
  vi.restoreAllMocks()
})

// ── requestRecommendation ────────────────────────────────────────────

describe('requestRecommendation', () => {

  it('returns parsed recommendation on 200', async () => {
    const payload = {
      content: 'Ton sommeil est solide cette semaine.',
      actionType: 'sleep',
      agentSource: 'sleep_agent',
      confidence: 0.87,
    }
    vi.stubGlobal('fetch', mockFetch(200, payload))

    const result = await requestRecommendation('user-123')

    expect(result).toEqual(payload)
  })

  it('sends X-Service-Token header', async () => {
    const fetchSpy = mockFetch(200, {
      content: '', actionType: '', agentSource: '', confidence: 0,
    })
    vi.stubGlobal('fetch', fetchSpy)

    await requestRecommendation('user-123')

    const [, options] = fetchSpy.mock.calls[0] as [string, RequestInit]
    expect((options.headers as Record<string, string>)['X-Service-Token']).toBe('test-token-secret')
  })

  it('sends POST to /recommend with userId in body', async () => {
    const fetchSpy = mockFetch(200, {
      content: '', actionType: '', agentSource: '', confidence: 0,
    })
    vi.stubGlobal('fetch', fetchSpy)

    await requestRecommendation('user-abc', true)

    const [url, options] = fetchSpy.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('http://ai-engine:3003/recommend')
    expect(JSON.parse(options.body as string)).toMatchObject({
      userId: 'user-abc',
      forceRefresh: true,
    })
  })

  it('throws AIEngineError with status 502 when ai-engine is unreachable', async () => {
    vi.stubGlobal('fetch', mockFetchNetworkError())

    await expect(requestRecommendation('user-123')).rejects.toMatchObject({
      name: 'AIEngineError',
      status: 502,
      code: 'AI_ENGINE_UNREACHABLE',
    })
  })

  it('throws AIEngineError with status 504 on timeout', async () => {
    // AbortError simule le timeout
    vi.stubGlobal('fetch', mockFetchNetworkError('AbortError'))

    await expect(requestRecommendation('user-123')).rejects.toMatchObject({
      name: 'AIEngineError',
      status: 504,
      code: 'AI_ENGINE_TIMEOUT',
    })
  })

  it('throws AIEngineError with ai-engine status when response is not ok', async () => {
    vi.stubGlobal('fetch', mockFetch(500, { detail: 'ORCHESTRATOR_FAILED' }))

    await expect(requestRecommendation('user-123')).rejects.toMatchObject({
      name: 'AIEngineError',
      status: 500,
      code: 'ORCHESTRATOR_FAILED',
    })
  })

  it('uses generic code when ai-engine error body is not JSON', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 503,
      json: () => Promise.reject(new Error('not json')),
    }))

    await expect(requestRecommendation('user-123')).rejects.toMatchObject({
      name: 'AIEngineError',
      status: 503,
      code: 'AI_ENGINE_ERROR',
    })
  })
})

// ── sendChatMessage ──────────────────────────────────────────────────

describe('sendChatMessage', () => {

  it('returns parsed chat response on 200', async () => {
    const payload = {
      response: 'Tu dors mieux quand tu fais du sport le matin.',
      conversationId: 'conv-456',
    }
    vi.stubGlobal('fetch', mockFetch(200, payload))

    const result = await sendChatMessage('user-123', 'Comment je dors en ce moment ?')

    expect(result).toEqual(payload)
  })

  it('forwards conversationId when provided', async () => {
    const fetchSpy = mockFetch(200, { response: '', conversationId: 'conv-456' })
    vi.stubGlobal('fetch', fetchSpy)

    await sendChatMessage('user-123', 'Bonjour', 'conv-456')

    const [, options] = fetchSpy.mock.calls[0] as [string, RequestInit]
    expect(JSON.parse(options.body as string)).toMatchObject({
      conversationId: 'conv-456',
    })
  })

  it('sends POST to /chat', async () => {
    const fetchSpy = mockFetch(200, { response: '', conversationId: '' })
    vi.stubGlobal('fetch', fetchSpy)

    await sendChatMessage('user-123', 'Bonjour')

    const [url] = fetchSpy.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('http://ai-engine:3003/chat')
  })

  it('throws AIEngineError on 401 from ai-engine', async () => {
    vi.stubGlobal('fetch', mockFetch(401, { detail: 'Invalid service token' }))

    await expect(
      sendChatMessage('user-123', 'Bonjour')
    ).rejects.toMatchObject({
      name: 'AIEngineError',
      status: 401,
    })
  })
})
