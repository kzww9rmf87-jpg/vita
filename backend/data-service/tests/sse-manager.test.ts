import { describe, it, expect, beforeEach } from 'vitest'
import type { ServerResponse } from 'node:http'
import {
  registerConnection,
  unregisterConnection,
  sendEvent,
  hasConnection,
  _clearAll,
} from '../src/sse-manager.js'

// ── Helpers ─────────────────────────────────────────────────────────

function makeMockResponse(writeFn?: (chunk: string) => void) {
  return {
    write: writeFn ?? (() => {}),
  } as unknown as ServerResponse
}

// ── Setup ────────────────────────────────────────────────────────────

beforeEach(() => {
  _clearAll()
})

// ── registerConnection / hasConnection ───────────────────────────────

describe('registerConnection', () => {

  it('registers a connection for a userId', () => {
    const res = makeMockResponse()
    registerConnection('user-1', res)
    expect(hasConnection('user-1')).toBe(true)
  })

  it('allows multiple connections for the same userId', () => {
    registerConnection('user-1', makeMockResponse())
    registerConnection('user-1', makeMockResponse())
    expect(hasConnection('user-1')).toBe(true)
  })

  it('returns false for unknown userId', () => {
    expect(hasConnection('user-unknown')).toBe(false)
  })
})

// ── unregisterConnection ─────────────────────────────────────────────

describe('unregisterConnection', () => {

  it('removes the connection', () => {
    const res = makeMockResponse()
    registerConnection('user-1', res)
    unregisterConnection('user-1', res)
    expect(hasConnection('user-1')).toBe(false)
  })

  it('cleans up the userId entry when last connection is removed', () => {
    const res = makeMockResponse()
    registerConnection('user-1', res)
    unregisterConnection('user-1', res)
    // Une deuxième unregister ne doit pas planter
    expect(() => unregisterConnection('user-1', res)).not.toThrow()
  })

  it('only removes the specific connection, not others for the same user', () => {
    const res1 = makeMockResponse()
    const res2 = makeMockResponse()
    registerConnection('user-1', res1)
    registerConnection('user-1', res2)
    unregisterConnection('user-1', res1)
    expect(hasConnection('user-1')).toBe(true)
  })

  it('does not throw for unknown userId', () => {
    expect(() => unregisterConnection('user-unknown', makeMockResponse())).not.toThrow()
  })
})

// ── sendEvent ────────────────────────────────────────────────────────

describe('sendEvent', () => {

  it('writes a correctly formatted SSE payload', () => {
    const written: string[] = []
    const res = makeMockResponse((chunk) => written.push(chunk))
    registerConnection('user-1', res)

    sendEvent('user-1', 'thinking', { message: 'Je relis nos échanges…' })

    expect(written).toHaveLength(1)
    expect(written[0]).toBe(
      'event: thinking\ndata: {"message":"Je relis nos échanges…"}\n\n'
    )
  })

  it('returns true when at least one connection received the event', () => {
    registerConnection('user-1', makeMockResponse())
    const result = sendEvent('user-1', 'recommendation', { content: 'test' })
    expect(result).toBe(true)
  })

  it('returns false when no connection is registered', () => {
    const result = sendEvent('user-no-connection', 'thinking', { message: 'test' })
    expect(result).toBe(false)
  })

  it('sends to all active connections for a userId', () => {
    const written1: string[] = []
    const written2: string[] = []
    registerConnection('user-1', makeMockResponse((c) => written1.push(c)))
    registerConnection('user-1', makeMockResponse((c) => written2.push(c)))

    sendEvent('user-1', 'recommendation', { content: 'test' })

    expect(written1).toHaveLength(1)
    expect(written2).toHaveLength(1)
  })

  it('removes a broken connection silently when write throws', () => {
    const brokenRes = {
      write: () => { throw new Error('socket closed') },
    } as unknown as ServerResponse

    registerConnection('user-1', brokenRes)

    // Ne doit pas planter
    expect(() => sendEvent('user-1', 'thinking', { message: 'test' })).not.toThrow()

    // La connexion cassée est nettoyée
    expect(hasConnection('user-1')).toBe(false)
  })

  it('does not send to other users', () => {
    const written: string[] = []
    registerConnection('user-A', makeMockResponse((c) => written.push(c)))
    registerConnection('user-B', makeMockResponse())

    sendEvent('user-A', 'thinking', { message: 'test' })

    expect(written).toHaveLength(1)
  })
})
