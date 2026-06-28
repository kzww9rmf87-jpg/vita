// Client HTTP inter-services : data-service → ai-engine.
//
// Ce module est le seul endroit du data-service qui connaît l'URL et
// le token de l'ai-engine. Toutes les routes qui ont besoin de l'IA
// passent par ici — jamais de fetch direct vers ai-engine ailleurs.

const AI_ENGINE_URL = process.env.AI_ENGINE_URL ?? 'http://localhost:3003'
const AI_SERVICE_TOKEN = process.env.AI_SERVICE_TOKEN ?? ''

// Timeout généreux : Claude peut légitimement prendre jusqu'à 10s.
const TIMEOUT_MS = 15_000

export class AIEngineError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string
  ) {
    super(message)
    this.name = 'AIEngineError'
  }
}

// ── Types des contrats d'API avec l'ai-engine ──────────────────────
// Les noms de champs sont en snake_case : ils correspondent exactement
// aux modèles Pydantic de l'ai-engine (FastAPI). Ne pas modifier.

interface RecommendRequest {
  user_id: string
  force_refresh?: boolean
}

// Les champs correspondent exactement à ce que FastAPI sérialise (snake_case).
export interface RecommendResponse {
  content: string
  content_short: string | null
  action_type: string
  agent_source: string
  confidence: number
  actions: string[]
}

interface ChatRequest {
  user_id: string
  message: string
  conversation_id?: string
}

export interface ChatResponse {
  response: string
  conversationId: string
  contextCategories?: string[]
}

interface DetectPatternsRequest {
  user_id: string
}

export interface DetectPatternsResponse {
  patternsFound: number
  patterns: Array<{
    type: string
    description: string
    confidence: number
  }>
}

// ── Fonction de bas niveau ──────────────────────────────────────────

async function callAIEngine<TBody, TResponse>(
  path: string,
  body: TBody
): Promise<TResponse> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS)

  if (process.env.NODE_ENV !== 'production') {
    console.log('[ai-client] AI REQUEST', path, JSON.stringify(body, null, 2))
  }

  let response: Response
  try {
    response = await fetch(`${AI_ENGINE_URL}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Le token ne doit jamais apparaître dans les logs applicatifs.
        'X-Service-Token': AI_SERVICE_TOKEN,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    })
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      throw new AIEngineError(504, 'AI_ENGINE_TIMEOUT', `AI engine timed out after ${TIMEOUT_MS}ms`)
    }
    throw new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'AI engine is unreachable')
  } finally {
    clearTimeout(timer)
  }

  if (!response.ok) {
    let errorCode = 'AI_ENGINE_ERROR'
    try {
      const payload = await response.json() as { detail?: string; error?: string }
      errorCode = payload.detail ?? payload.error ?? errorCode
    } catch {
      // Corps non-JSON : on garde le code générique
    }
    throw new AIEngineError(response.status, errorCode, `AI engine returned ${response.status}`)
  }

  return response.json() as Promise<TResponse>
}

// ── API publique du client ──────────────────────────────────────────

export async function requestRecommendation(
  userId: string,
  forceRefresh = false
): Promise<RecommendResponse> {
  return callAIEngine<RecommendRequest, RecommendResponse>('/recommend', {
    user_id: userId,
    force_refresh: forceRefresh,
  })
}

export async function sendChatMessage(
  userId: string,
  message: string,
  conversationId?: string
): Promise<ChatResponse> {
  return callAIEngine<ChatRequest, ChatResponse>('/chat', {
    user_id: userId,
    message,
    conversation_id: conversationId,
  })
}

export async function triggerPatternDetection(
  userId: string
): Promise<DetectPatternsResponse> {
  return callAIEngine<DetectPatternsRequest, DetectPatternsResponse>(
    '/detect-patterns',
    { user_id: userId }
  )
}

interface JournalAnalyzeRequest {
  user_id: string
  content: string
  entry_id?: string
}

export interface JournalAnalysis {
  mood_label: string
  emotional_tone: string
  themes: string[]
  intensity: number
  valence: number
  vita_response: string
  safety_flag: boolean
  safety_severity: string | null
}

interface WeeklyReflectionRequest {
  user_id: string
  week_start?: string
}

export interface WeeklyReflectionAIResponse {
  id: string | null
  user_id: string
  content: string
  period_start: string
  period_end: string
  themes: string[]
  question: string | null
  created_at: string | null
}

export async function requestWeeklyReflection(
  userId: string,
  weekStart?: string
): Promise<WeeklyReflectionAIResponse | null> {
  return callAIEngine<WeeklyReflectionRequest, WeeklyReflectionAIResponse | null>(
    '/reflection/weekly',
    { user_id: userId, week_start: weekStart }
  )
}

// ── Daily Insight ──────────────────────────────────────────────────────────

interface DailyInsightRequest {
  user_id: string
  date?: string
}

export interface DailyInsightAIResponse {
  id: string
  user_id: string
  date: string
  climate: string
  summary: string
  drivers: string[]
  reflection: string
  question: string
  created_at: string
}

export async function requestDailyInsight(
  userId: string,
  date?: string
): Promise<DailyInsightAIResponse | null> {
  return callAIEngine<DailyInsightRequest, DailyInsightAIResponse | null>(
    '/daily-insight/generate',
    { user_id: userId, date }
  )
}

// ── Première Rencontre ────────────────────────────────────────────────────────

export interface FirstEncounterExchange {
  role: 'vita' | 'user'
  content: string
  topic: string | null
  created_at: string
}

export interface FirstEncounterSessionState {
  status: 'not_started' | 'in_progress' | 'completed'
  topic_index?: number
  exchange_count?: number
  exchanges?: FirstEncounterExchange[]
  portrait?: string
  completed_at?: string
  already_started?: boolean
  vita_opening?: string
  session_id?: string
}

export interface FirstEncounterMessageResponse {
  vita_response: string
  topic: string
  exchange_number: number
  is_complete: boolean
  portrait: string | null
}

export interface FirstEncounterCorrectionResponse {
  portrait: string
}

export async function getFirstEncounterSession(
  userId: string
): Promise<FirstEncounterSessionState> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS)

  let response: Response
  try {
    response = await fetch(`${AI_ENGINE_URL}/first-encounter/session/${encodeURIComponent(userId)}`, {
      method: 'GET',
      headers: { 'X-Service-Token': AI_SERVICE_TOKEN },
      signal: controller.signal,
    })
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      throw new AIEngineError(504, 'AI_ENGINE_TIMEOUT', `AI engine timed out after ${TIMEOUT_MS}ms`)
    }
    throw new AIEngineError(502, 'AI_ENGINE_UNREACHABLE', 'AI engine is unreachable')
  } finally {
    clearTimeout(timer)
  }

  if (!response.ok) {
    throw new AIEngineError(response.status, 'AI_ENGINE_ERROR', `AI engine returned ${response.status}`)
  }
  return response.json() as Promise<FirstEncounterSessionState>
}

export async function startFirstEncounter(
  userId: string
): Promise<FirstEncounterSessionState> {
  return callAIEngine<{ user_id: string }, FirstEncounterSessionState>(
    '/first-encounter/start',
    { user_id: userId }
  )
}

export async function sendFirstEncounterMessage(
  userId: string,
  content: string
): Promise<FirstEncounterMessageResponse> {
  return callAIEngine<{ user_id: string; content: string }, FirstEncounterMessageResponse>(
    '/first-encounter/message',
    { user_id: userId, content }
  )
}

export async function correctFirstEncounterPortrait(
  userId: string,
  correction: string
): Promise<FirstEncounterCorrectionResponse> {
  return callAIEngine<{ user_id: string; correction: string }, FirstEncounterCorrectionResponse>(
    '/first-encounter/correct',
    { user_id: userId, correction }
  )
}

export async function analyzeJournalEntry(
  userId: string,
  content: string,
  entryId?: string
): Promise<JournalAnalysis> {
  return callAIEngine<JournalAnalyzeRequest, JournalAnalysis>('/journal/analyze', {
    user_id: userId,
    content,
    entry_id: entryId,
  })
}
