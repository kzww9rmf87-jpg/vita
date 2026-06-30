// Client HTTP inter-services : data-service → ai-engine.
//
// Ce module est le seul endroit du data-service qui connaît l'URL et
// le token de l'ai-engine. Toutes les routes qui ont besoin de l'IA
// passent par ici — jamais de fetch direct vers ai-engine ailleurs.

const AI_ENGINE_URL = process.env.AI_ENGINE_URL ?? 'http://localhost:3003'
const AI_SERVICE_TOKEN = process.env.AI_SERVICE_TOKEN ?? ''

// Timeout standard : Claude conversation ~5-10s.
const TIMEOUT_MS = 15_000
// Timeout étendu pour les routes qui enchaînent plusieurs appels Claude (ex: portrait).
const TIMEOUT_MS_LONG = 45_000

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
  body: TBody,
  timeoutMs = TIMEOUT_MS
): Promise<TResponse> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)

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
      throw new AIEngineError(504, 'AI_ENGINE_TIMEOUT', `AI engine timed out after ${timeoutMs}ms`)
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
  // Timeout étendu : le dernier message peut déclencher la génération du portrait
  // (2 appels Claude consécutifs), ce qui peut prendre 20-30s.
  return callAIEngine<{ user_id: string; content: string }, FirstEncounterMessageResponse>(
    '/first-encounter/message',
    { user_id: userId, content },
    TIMEOUT_MS_LONG
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

// ── Meal Planner ──────────────────────────────────────────────────────────────

interface MealDistributionRequest {
  user_id: string
  recipes: Array<{
    id: string
    name: string
    servings: number
    prep_minutes: number | null
    cook_minutes: number | null
  }>
}

export interface MealDistributionItem {
  recipe_id: string
  recipe_name: string
  day_of_week: number
  meal_slot: 'lunch' | 'dinner'
  portions: number
}

export async function requestMealDistribution(
  userId: string,
  recipes: Array<{
    id: string
    name: string
    servings: number
    prep_minutes: number | null
    cook_minutes: number | null
  }>
): Promise<MealDistributionItem[]> {
  return callAIEngine<MealDistributionRequest, MealDistributionItem[]>(
    '/meal-planner/distribute',
    { user_id: userId, recipes }
  )
}

// ── Meal Planner Agent (Sprint 9) ─────────────────────────────────────────────

export interface RecipeWithMacros {
  id:           string
  name:         string
  servings:     number
  prep_minutes: number | null
  cook_minutes: number | null
  calories:     number | null
  protein_g:    number | null
  carbs_g:      number | null
  fat_g:        number | null
  fiber_g:      number | null
}

export interface NutritionProfilePayload {
  objective:           string
  weight_kg?:          number | null
  height_cm?:          number | null
  age?:                number | null
  sex?:                string | null
  activity_level:      string
  meals_per_day:       number
  batch_cooking:       boolean
  cook_time_available?: string | null
  budget?:             string | null
  allergies:           string[]
  intolerances:        string[]
  excluded_foods:      string[]
  target_calories?:    number | null
  target_protein_g?:   number | null
  target_carbs_g?:     number | null
  target_fat_g?:       number | null
  target_fiber_g?:     number | null
}

export interface PlannedSlotMacros {
  recipe_id:   string
  recipe_name: string
  day_of_week: number
  meal_slot:   'lunch' | 'dinner'
  portions:    number
  calories:    number | null
  protein_g:   number | null
  carbs_g:     number | null
  fat_g:       number | null
  fiber_g:     number | null
}

export interface DayMacros {
  day_of_week: number
  calories:    number | null
  protein_g:   number | null
  carbs_g:     number | null
  fat_g:       number | null
  fiber_g:     number | null
}

export interface SmartMealPlanResponse {
  slots:       PlannedSlotMacros[]
  day_macros:  DayMacros[]
  week_macros: DayMacros
  used_claude: boolean
}

// Contexte sportif journalier passé au MealPlannerAgent (Sprint 13).
// Correspond à ActivityDayContext dans l'ai-engine (meal_planner/models.py).
export interface ActivityDayContext {
  day_of_week:        number
  load_level:         'rest' | 'light' | 'moderate' | 'demanding'
  total_duration_min: number
  dominant_type:      string
}

export async function requestSmartMealPlan(
  userId: string,
  recipes: RecipeWithMacros[],
  profile: NutritionProfilePayload | null,
  pantry: string[],
  activitySchedule?: ActivityDayContext[],
): Promise<SmartMealPlanResponse> {
  return callAIEngine<object, SmartMealPlanResponse>(
    '/meal-planner/plan',
    { user_id: userId, recipes, profile, pantry, activity_schedule: activitySchedule ?? null },
    TIMEOUT_MS_LONG  // peut appeler Claude pour le raffinement
  )
}

export interface NutritionTargets {
  target_calories:  number | null
  target_protein_g: number | null
  target_carbs_g:   number | null
  target_fat_g:     number | null
  target_fiber_g:   number | null
}

export async function calculateNutritionTargets(
  profile: {
    objective:      string
    weight_kg:      number
    height_cm:      number
    age:            number
    sex:            string
    activity_level: string
  }
): Promise<NutritionTargets> {
  return callAIEngine<object, NutritionTargets>(
    '/meal-planner/calculate-targets',
    profile
  )
}

// ── Recipe Prefill (Sprint 9.2) ───────────────────────────────────────────────

export interface PrefillIngredient {
  name:       string
  quantity_g: number | null
  sort_order: number
}

export interface RecipePrefillResult {
  name:                    string
  servings:                number
  prep_minutes:            number | null
  cook_minutes:            number | null
  notes:                   string | null
  calories_per_serving:    number | null
  protein_g_per_serving:   number | null
  carbs_g_per_serving:     number | null
  fat_g_per_serving:       number | null
  fiber_g_per_serving:     number | null
  ingredients:             PrefillIngredient[]
  is_estimated:            true
}

export async function requestRecipePrefill(
  recipeName: string,
  servings?: number,
): Promise<RecipePrefillResult> {
  // Génération Claude (haiku) : ~5-10s — timeout standard suffit.
  return callAIEngine<{ recipe_name: string; servings?: number }, RecipePrefillResult>(
    '/meal-planner/recipe-prefill',
    { recipe_name: recipeName, servings },
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

// ── Training Planner (Sprint 12) ──────────────────────────────────────────────

export interface SportProfilePayload {
  fitness_level:         string
  preferred_activities:  string[]
  sessions_per_week:     number
  session_duration_min:  number
  available_days:        number[]
  context:               string | null
  // Sprint 12.2 — préférences découverte
  motivation?:            string
  attractive_activities?: string[]
  rejected_activities?:   string[]
  preferred_context?:     string[]
  apprehension_level?:    string
  realistic_time_min?:    number | null
}

export interface PlannedSessionAI {
  day_of_week:   number
  activity_name: string
  session_type:  string
  duration_min:  number
  notes:         string | null
  sort_order:    number
}

export interface TrainingWeekPlanResponse {
  sessions:    PlannedSessionAI[]
  rationale:   string
  used_claude: boolean
}

// ── Sport Discover (Sprint 12.2) ──────────────────────────────────────────────

export interface SportDiscoverPayload {
  fitness_level:         string
  motivation?:           string
  attractive_activities: string[]
  rejected_activities:   string[]
  preferred_context:     string[]
  apprehension_level:    string
  realistic_time_min?:   number
  context?:              string
}

export interface ActivityOptionResponse {
  name:                string
  why:                 string
  constraint_level:    string
  first_step:          string
  suggested_frequency: string
  session_type:        string
}

export interface SportDiscoverResponse {
  options:            ActivityOptionResponse[]
  discovery_question: string
  used_claude:        boolean
}

export async function requestSportDiscover(
  userId: string,
  payload: SportDiscoverPayload,
): Promise<SportDiscoverResponse> {
  return callAIEngine<object, SportDiscoverResponse>(
    '/training-planner/discover',
    { user_id: userId, ...payload },
    TIMEOUT_MS_LONG,
  )
}

// ── Discovery Engine ──────────────────────────────────────────────────────────

export interface DiscoveryExchangePayload {
  role: 'vita' | 'user'
  content: string
}

export interface DiscoverySynthesisPayload {
  rapport_au_sport:       string | null
  motivations:            string[]
  freins:                 string[]
  experiences_positives:  string[]
  experiences_negatives:  string[]
  contexte_prefere:       string[]
  contraintes:            string[]
  personnalite:           string | null
  resume_valide:          string | null
}

export interface ActivityProposalPayload {
  name:             string
  why_it_fits:      string
  first_step:       string
  frequency:        string
  constraint_level: string
}

export interface DiscoveryStartResponse {
  vita_opening:    string
  already_started: boolean
}

export interface DiscoveryMessageResponse {
  vita_response: string
  new_status:    string
  synthesis:     DiscoverySynthesisPayload | null
  proposals:     ActivityProposalPayload[]
}

export interface DiscoveryReactResponse {
  vita_response:  string
  new_proposals:  ActivityProposalPayload[]
  is_complete:    boolean
}

export async function requestDiscoveryStart(
  userId: string,
  domain = 'sport',
): Promise<DiscoveryStartResponse> {
  return callAIEngine<object, DiscoveryStartResponse>(
    '/discovery/start',
    { user_id: userId, domain },
  )
}

export async function requestDiscoveryMessage(
  userId: string,
  domain: string,
  exchanges: DiscoveryExchangePayload[],
  userMessage: string,
  status: string,
): Promise<DiscoveryMessageResponse> {
  return callAIEngine<object, DiscoveryMessageResponse>(
    '/discovery/message',
    {
      user_id:      userId,
      domain,
      exchanges,
      user_message: userMessage,
      status,
    },
    TIMEOUT_MS_LONG,
  )
}

export async function requestDiscoveryReact(
  userId: string,
  domain: string,
  proposals: ActivityProposalPayload[],
  acceptedNames: string[],
  refusedNames: string[],
  synthesis: DiscoverySynthesisPayload | null,
): Promise<DiscoveryReactResponse> {
  return callAIEngine<object, DiscoveryReactResponse>(
    '/discovery/react',
    {
      user_id:       userId,
      domain,
      proposals,
      accepted_names: acceptedNames,
      refused_names:  refusedNames,
      synthesis,
    },
    TIMEOUT_MS_LONG,
  )
}

export async function requestTrainingPlan(
  userId: string,
  sportProfile: SportProfilePayload,
  options: {
    hasSleepIssue?:  boolean
    isHighEnergy?:   boolean
    equipment?:      string[]
    painAreas?:      string[]
    preferOutdoors?: boolean
  } = {}
): Promise<TrainingWeekPlanResponse> {
  return callAIEngine<object, TrainingWeekPlanResponse>(
    '/training-planner/plan',
    {
      user_id:         userId,
      sport_profile:   sportProfile,
      has_sleep_issue: options.hasSleepIssue  ?? false,
      is_high_energy:  options.isHighEnergy   ?? false,
      equipment:       options.equipment      ?? [],
      pain_areas:      options.painAreas      ?? [],
      prefer_outdoors: options.preferOutdoors ?? false,
    },
    TIMEOUT_MS_LONG,
  )
}
