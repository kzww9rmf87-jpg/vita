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

export interface RecommendRequest {
  userId: string
  forceRefresh?: boolean
}

export interface RecommendResponse {
  content: string
  actionType: string
  agentSource: string
  confidence: number
}

export interface ChatRequest {
  userId: string
  message: string
  conversationId?: string
}

export interface ChatResponse {
  response: string
  conversationId: string
}

export interface DetectPatternsRequest {
  userId: string
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
    userId,
    forceRefresh,
  })
}

export async function sendChatMessage(
  userId: string,
  message: string,
  conversationId?: string
): Promise<ChatResponse> {
  return callAIEngine<ChatRequest, ChatResponse>('/chat', {
    userId,
    message,
    conversationId,
  })
}

export async function triggerPatternDetection(
  userId: string
): Promise<DetectPatternsResponse> {
  return callAIEngine<DetectPatternsRequest, DetectPatternsResponse>(
    '/detect-patterns',
    { userId }
  )
}
