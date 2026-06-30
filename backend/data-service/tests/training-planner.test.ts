import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('../src/db.js', () => ({
  query:    vi.fn(),
  queryOne: vi.fn(),
}))
vi.mock('../src/ai-client.js', () => ({
  requestTrainingPlan:  vi.fn(),
  requestSportDiscover: vi.fn(),
  AIEngineError: class AIEngineError extends Error {
    constructor(public status: number, public code: string, message: string) {
      super(message); this.name = 'AIEngineError'
    }
  },
}))

const { query, queryOne } = await import('../src/db.js') as {
  query: ReturnType<typeof vi.fn>
  queryOne: ReturnType<typeof vi.fn>
}
const { requestTrainingPlan, requestSportDiscover } = await import('../src/ai-client.js') as {
  requestTrainingPlan:  ReturnType<typeof vi.fn>
  requestSportDiscover: ReturnType<typeof vi.fn>
}

const makeApp = async () => {
  const Fastify = (await import('fastify')).default
  const jwt = (await import('@fastify/jwt')).default
  const { sportRoutes } = await import('../src/routes/sport.js')
  const app = Fastify()
  await app.register(jwt, { secret: 'test-secret' })
  app.addHook('onRequest', async (req) => {
    ;(req as any).user = { sub: 'user-uuid-123' }
  })
  await app.register(sportRoutes, { prefix: '/sport' })
  return app
}

const MOCK_PROFILE = {
  fitness_level:         'intermediate',
  preferred_activities:  ['Musculation', 'Course'],
  sessions_per_week:     3,
  session_duration_min:  45,
  available_days:        [1, 3, 5],
  context:               null,
  motivation:            null,
  attractive_activities: [],
  rejected_activities:   [],
  preferred_context:     [],
  apprehension_level:    'aucune',
  realistic_time_min:    null,
}

const MOCK_DISCOVER_RESPONSE = {
  options: [
    {
      name: 'Marche', why: 'Accessible à tous.', constraint_level: 'tres_faible',
      first_step: 'Une sortie de 15 min.', suggested_frequency: '3 fois par semaine',
      session_type: 'walk',
    },
    {
      name: 'Mobilité', why: 'Pour les articulations.', constraint_level: 'tres_faible',
      first_step: '10 min le matin.', suggested_frequency: '4 fois par semaine',
      session_type: 'mobility',
    },
    {
      name: 'Pilates', why: 'Renforcement en douceur.', constraint_level: 'faible',
      first_step: 'Un cours débutant.', suggested_frequency: '2 fois par semaine',
      session_type: 'mobility',
    },
  ],
  discovery_question: 'Laquelle te semble la plus réaliste pour commencer ?',
  used_claude: false,
}

const MOCK_AI_RESPONSE = {
  sessions: [
    { day_of_week: 1, activity_name: 'Musculation', session_type: 'strength', duration_min: 45, notes: null, sort_order: 0 },
    { day_of_week: 3, activity_name: 'Course',      session_type: 'cardio',   duration_min: 45, notes: null, sort_order: 1 },
    { day_of_week: 5, activity_name: 'Mobilité',    session_type: 'mobility', duration_min: 36, notes: null, sort_order: 2 },
  ],
  rationale:   'VITA a organisé 3 séances (Lun, Mer, Ven).',
  used_claude: false,
}

// ── POST /sport/training-planner/suggest ─────────────────────────────────────

describe('POST /sport/training-planner/suggest', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('200 with default profile when no sport profile exists', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    ;(requestTrainingPlan as any).mockResolvedValue(MOCK_AI_RESPONSE)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/suggest' })
    expect(res.statusCode).toBe(200)
    expect(res.json().hasProfile).toBe(false)
  })

  it('uses default profile values when no profile exists', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    ;(requestTrainingPlan as any).mockResolvedValue(MOCK_AI_RESPONSE)
    const app = await makeApp()
    await app.inject({ method: 'POST', url: '/sport/training-planner/suggest' })
    expect(requestTrainingPlan).toHaveBeenCalledWith(
      'user-uuid-123',
      expect.objectContaining({
        fitness_level:         'beginner',
        sessions_per_week:     3,
        available_days:        [1, 3, 5],
        attractive_activities: [],
        rejected_activities:   [],
        apprehension_level:    'aucune',
      })
    )
  })

  it('returns 200 with camelCase sessions and rationale', async () => {
    ;(queryOne as any).mockResolvedValue(MOCK_PROFILE)
    ;(requestTrainingPlan as any).mockResolvedValue(MOCK_AI_RESPONSE)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/suggest' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.rationale).toBe('VITA a organisé 3 séances (Lun, Mer, Ven).')
    expect(body.sessions).toHaveLength(3)
    expect(body.sessions[0]).toMatchObject({
      dayOfWeek:    1,
      activityName: 'Musculation',
      sessionType:  'strength',
      durationMin:  45,
    })
    expect(body.usedClaude).toBe(false)
    expect(body.hasProfile).toBe(true)
  })

  it('passes profile fields including sprint 12.2 fields to AI engine', async () => {
    ;(queryOne as any).mockResolvedValue(MOCK_PROFILE)
    ;(requestTrainingPlan as any).mockResolvedValue(MOCK_AI_RESPONSE)
    const app = await makeApp()
    await app.inject({ method: 'POST', url: '/sport/training-planner/suggest' })
    expect(requestTrainingPlan).toHaveBeenCalledWith(
      'user-uuid-123',
      expect.objectContaining({
        fitness_level:         'intermediate',
        sessions_per_week:     3,
        available_days:        [1, 3, 5],
        attractive_activities: [],
        rejected_activities:   [],
        apprehension_level:    'aucune',
      })
    )
  })

  it('502 when AI engine is unreachable', async () => {
    const { AIEngineError } = await import('../src/ai-client.js') as any
    ;(queryOne as any).mockResolvedValue(MOCK_PROFILE)
    ;(requestTrainingPlan as any).mockRejectedValue(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/suggest' })
    expect(res.statusCode).toBe(502)
    expect(res.json().error).toBe('AI_UNAVAILABLE')
  })

  it('504 on AI timeout', async () => {
    const { AIEngineError } = await import('../src/ai-client.js') as any
    ;(queryOne as any).mockResolvedValue(MOCK_PROFILE)
    ;(requestTrainingPlan as any).mockRejectedValue(
      new AIEngineError(504, 'AI_ENGINE_TIMEOUT', 'timeout')
    )
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/suggest' })
    expect(res.statusCode).toBe(504)
    expect(res.json().error).toBe('AI_TIMEOUT')
  })
})

// ── POST /sport/training-planner/discover ────────────────────────────────────

describe('POST /sport/training-planner/discover', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('200 with options when profile exists', async () => {
    ;(queryOne as any).mockResolvedValue(MOCK_PROFILE)
    ;(requestSportDiscover as any).mockResolvedValue(MOCK_DISCOVER_RESPONSE)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/discover', payload: {} })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.options).toHaveLength(3)
    expect(body.discovery_question).toBe('Laquelle te semble la plus réaliste pour commencer ?')
    expect(body.options[0].name).toBe('Marche')
  })

  it('200 with defaults when no profile', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    ;(requestSportDiscover as any).mockResolvedValue(MOCK_DISCOVER_RESPONSE)
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/discover', payload: {} })
    expect(res.statusCode).toBe(200)
    // Doit appeler discover avec fitness_level par défaut
    expect(requestSportDiscover).toHaveBeenCalledWith(
      'user-uuid-123',
      expect.objectContaining({ fitness_level: 'beginner' })
    )
  })

  it('merges profile rejected_activities with override', async () => {
    const profileWithRejected = { ...MOCK_PROFILE, rejected_activities: ['HIIT'] }
    ;(queryOne as any).mockResolvedValue(profileWithRejected)
    ;(requestSportDiscover as any).mockResolvedValue(MOCK_DISCOVER_RESPONSE)
    const app = await makeApp()
    await app.inject({
      method: 'POST', url: '/sport/training-planner/discover',
      payload: { rejected_activities: ['Musculation'] },
    })
    // L'override remplace — ce sont les rejected du body qui sont envoyés
    expect(requestSportDiscover).toHaveBeenCalledWith(
      'user-uuid-123',
      expect.objectContaining({ rejected_activities: ['Musculation'] })
    )
  })

  it('body override takes priority over profile fields', async () => {
    ;(queryOne as any).mockResolvedValue(MOCK_PROFILE)
    ;(requestSportDiscover as any).mockResolvedValue(MOCK_DISCOVER_RESPONSE)
    const app = await makeApp()
    await app.inject({
      method: 'POST', url: '/sport/training-planner/discover',
      payload: { fitness_level: 'advanced', apprehension_level: 'legere' },
    })
    expect(requestSportDiscover).toHaveBeenCalledWith(
      'user-uuid-123',
      expect.objectContaining({ fitness_level: 'advanced', apprehension_level: 'legere' })
    )
  })

  it('400 on invalid body', async () => {
    ;(queryOne as any).mockResolvedValue(null)
    const app = await makeApp()
    const res = await app.inject({
      method: 'POST', url: '/sport/training-planner/discover',
      payload: { fitness_level: 'ultra_elite' },  // valeur invalide
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('VALIDATION_ERROR')
  })

  it('502 when AI engine unavailable', async () => {
    const { AIEngineError } = await import('../src/ai-client.js') as any
    ;(queryOne as any).mockResolvedValue(null)
    ;(requestSportDiscover as any).mockRejectedValue(
      new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'unreachable')
    )
    const app = await makeApp()
    const res = await app.inject({ method: 'POST', url: '/sport/training-planner/discover', payload: {} })
    expect(res.statusCode).toBe(502)
    expect(res.json().error).toBe('AI_UNAVAILABLE')
  })
})
