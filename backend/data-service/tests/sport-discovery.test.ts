import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))

vi.mock('../src/ai-client.js', () => ({
  requestDiscoveryStart:   vi.fn(),
  requestDiscoveryMessage: vi.fn(),
  requestDiscoveryReact:   vi.fn(),
  AIEngineError: class AIEngineError extends Error {
    constructor(public status: number, public code: string, message: string) {
      super(message); this.name = 'AIEngineError'
    }
  },
}))

const { query, queryOne } = await import('../src/db.js') as {
  query:    ReturnType<typeof vi.fn>
  queryOne: ReturnType<typeof vi.fn>
}

const {
  requestDiscoveryStart,
  requestDiscoveryMessage,
  requestDiscoveryReact,
  AIEngineError,
} = await import('../src/ai-client.js') as {
  requestDiscoveryStart:   ReturnType<typeof vi.fn>
  requestDiscoveryMessage: ReturnType<typeof vi.fn>
  requestDiscoveryReact:   ReturnType<typeof vi.fn>
  AIEngineError: new (status: number, code: string, msg: string) => Error & { status: number; code: string }
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { sportDiscoveryRoutes } = await import('../src/routes/sport-discovery.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(sportDiscoveryRoutes, { prefix: '/sport/discovery' })
  return app
}

const MOCK_SESSION = {
  id:                  'session-uuid-1',
  status:              'discovering',
  exchanges:           [{ role: 'vita', content: 'Bonjour !' }],
  synthesis:           null,
  proposals:           [],
  accepted_activities: [],
  refused_activities:  [],
  created_at:          '2026-01-01T00:00:00Z',
  updated_at:          '2026-01-01T00:00:00Z',
}

const MOCK_PROPOSALS = [
  {
    name:             'Randonnée',
    why_it_fits:      'Tu aimes la nature.',
    first_step:       'Une sortie de 2h le week-end.',
    frequency:        '1 fois par semaine',
    constraint_level: 'faible',
  },
  {
    name:             'Yoga',
    why_it_fits:      'Tu recherches du calme.',
    first_step:       'Un cours débutant en ligne.',
    frequency:        '2 fois par semaine',
    constraint_level: 'tres_faible',
  },
]

// ── POST /sport/discovery/start ───────────────────────────────────────────────

describe('POST /sport/discovery/start', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('201 — démarre une nouvelle session', async () => {
    ;(queryOne as any).mockResolvedValueOnce(null)  // pas de session existante
    ;(requestDiscoveryStart as any).mockResolvedValue({ vita_opening: 'Bonjour !', already_started: false })
    ;(queryOne as any).mockResolvedValueOnce({ id: 'session-uuid-1' })
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/start' })
    expect(res.statusCode).toBe(201)
    const body = res.json()
    expect(body.already_started).toBe(false)
    expect(body.vita_opening).toBe('Bonjour !')
    expect(body.session_id).toBe('session-uuid-1')
    expect(body.exchanges).toHaveLength(1)
    expect(body.exchanges[0].role).toBe('vita')
  })

  it('200 — retourne la session existante si active', async () => {
    ;(queryOne as any).mockResolvedValue(MOCK_SESSION)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/start' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.already_started).toBe(true)
    expect(body.session_id).toBe('session-uuid-1')
    expect(body.status).toBe('discovering')
    // N'appelle pas l'AI si session déjà active
    expect(requestDiscoveryStart).not.toHaveBeenCalled()
  })

  it('502 quand AI indisponible', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    ;(requestDiscoveryStart as any).mockRejectedValue(
      new (AIEngineError as any)(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/start' })
    expect(res.statusCode).toBe(502)
    expect(res.json().error ?? res.json().code).toMatch(/UNAVAILABLE|unreachable/i)
  })
})

// ── GET /sport/discovery/session ──────────────────────────────────────────────

describe('GET /sport/discovery/session', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('200 — retourne la session courante', async () => {
    ;(queryOne as any).mockResolvedValue(MOCK_SESSION)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sport/discovery/session' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.session_id).toBe('session-uuid-1')
    expect(body.status).toBe('discovering')
    expect(body.exchanges).toHaveLength(1)
  })

  it('404 — aucune session', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'GET', url: '/sport/discovery/session' })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NO_ACTIVE_SESSION')
  })
})

// ── POST /sport/discovery/message ─────────────────────────────────────────────

describe('POST /sport/discovery/message', () => {
  beforeEach(() => { vi.clearAllMocks() })

  const validBody = {
    user_message: "J'ai pratiqué la natation pendant des années.",
    exchanges:    [{ role: 'vita', content: 'Bonjour !' }],
    status:       'discovering',
  }

  it('200 — retourne la réponse VITA et reste en discovering', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-uuid-1', status: 'discovering' })
    ;(query as any).mockResolvedValue({})
    ;(requestDiscoveryMessage as any).mockResolvedValue({
      vita_response: 'La natation, ça te manque ?',
      new_status:    'discovering',
      synthesis:     null,
      proposals:     [],
    })
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/message', payload: validBody })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.vita_response).toBe('La natation, ça te manque ?')
    expect(body.new_status).toBe('discovering')
    expect(body.synthesis).toBeNull()
  })

  it('200 — passe en reformulating avec synthesis', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-uuid-1', status: 'discovering' })
    ;(query as any).mockResolvedValue({})
    ;(requestDiscoveryMessage as any).mockResolvedValue({
      vita_response: 'Si j\'ai bien compris...',
      new_status:    'reformulating',
      synthesis:     {
        rapport_au_sport: 'positif mais intermittent',
        motivations:      ['bien-être'],
        freins:           ['manque de temps'],
        experiences_positives: ['natation'],
        experiences_negatives: [],
        contexte_prefere: ['seul'],
        contraintes:      [],
        personnalite:     null,
        resume_valide:    'Si j\'ai bien compris...',
      },
      proposals: [],
    })
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/message', payload: validBody })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.new_status).toBe('reformulating')
    expect(body.synthesis).not.toBeNull()
    expect(body.synthesis.motivations).toContain('bien-être')
  })

  it('400 — message vide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/sport/discovery/message',
      payload: { user_message: '', exchanges: [], status: 'discovering' },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('404 — aucune session active', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/message', payload: validBody })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NO_ACTIVE_SESSION')
  })

  it('502 — AI indisponible', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-uuid-1', status: 'discovering' })
    ;(requestDiscoveryMessage as any).mockRejectedValue(
      new (AIEngineError as any)(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/message', payload: validBody })
    expect(res.statusCode).toBe(502)
  })
})

// ── POST /sport/discovery/react ───────────────────────────────────────────────

describe('POST /sport/discovery/react', () => {
  beforeEach(() => { vi.clearAllMocks() })

  const validBody = {
    proposals:      MOCK_PROPOSALS,
    accepted_names: ['Randonnée'],
    refused_names:  ['Yoga'],
    synthesis:      null,
  }

  it('200 — accepte une activité et termine la session', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-uuid-1', synthesis: null })
    ;(query as any).mockResolvedValue({})
    ;(requestDiscoveryReact as any).mockResolvedValue({
      vita_response:  'Super ! La randonnée est un excellent choix.',
      new_proposals:  [],
      is_complete:    true,
    })
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/react', payload: validBody })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.is_complete).toBe(true)
    expect(body.vita_response).toContain('randonnée')
    // Doit appeler query 2x : UPDATE session + UPSERT sport_identity
    expect(query).toHaveBeenCalledTimes(2)
  })

  it('200 — nouvelles propositions si refus partiel', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-uuid-1', synthesis: null })
    ;(query as any).mockResolvedValue({})
    ;(requestDiscoveryReact as any).mockResolvedValue({
      vita_response:  'Pas de problème. Et si on essayait la marche nordique ?',
      new_proposals:  [{
        name: 'Marche nordique', why_it_fits: 'Accessible.',
        first_step: 'Location de bâtons.', frequency: '2 fois/semaine',
        constraint_level: 'faible',
      }],
      is_complete: false,
    })
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/sport/discovery/react',
      payload: { ...validBody, accepted_names: [], refused_names: ['Randonnée', 'Yoga'] },
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.is_complete).toBe(false)
    expect(body.new_proposals).toHaveLength(1)
    expect(body.new_proposals[0].name).toBe('Marche nordique')
    // session mise à jour mais pas fermée, pas d'upsert sport_identity
    expect(query).toHaveBeenCalledTimes(1)
  })

  it('400 — constraint_level invalide', async () => {
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/sport/discovery/react',
      payload: {
        proposals: [{ ...MOCK_PROPOSALS[0], constraint_level: 'ultra_easy' }],
        accepted_names: [],
        refused_names:  [],
        synthesis:      null,
      },
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('404 — aucune session active', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/react', payload: validBody })
    expect(res.statusCode).toBe(404)
    expect(res.json().error).toBe('NO_ACTIVE_SESSION')
  })

  it('502 — AI indisponible', async () => {
    ;(queryOne as any).mockResolvedValue({ id: 'session-uuid-1', synthesis: null })
    ;(requestDiscoveryReact as any).mockRejectedValue(
      new (AIEngineError as any)(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/discovery/react', payload: validBody })
    expect(res.statusCode).toBe(502)
  })
})
