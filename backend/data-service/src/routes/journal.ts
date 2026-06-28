/**
 * Routes journal intime intelligent.
 *
 * POST /journal/entry    — Sauvegarde + analyse (renvoie réponse VITA en streaming futur, sync pour l'instant)
 * GET  /journal/recent   — Dernières entrées (contenu inclus, car l'utilisateur consulte son propre journal)
 * GET  /journal/timeline — Entrées formatées pour la Timeline (titre anonymisé, sans contenu brut)
 * GET  /journal/memories — Mémoires émotionnelles (thèmes, valence, résumé)
 *
 * Principe de séparation des données :
 *   /recent   → contenu complet (usage privé iOS)
 *   /timeline → titre uniquement, jamais le contenu brut (usage Timeline)
 *   /memories → résumés anonymisés (usage contexte AI)
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query } from '../db.js'
import { analyzeJournalEntry, AIEngineError } from '../ai-client.js'

const EntrySchema = z.object({
  content: z.string().min(1).max(10_000),
  // Défaut TRUE : une entrée est privée sauf décision explicite de l'utilisateur.
  // Principe du moindre risque : mieux vaut over-protéger que sous-protéger des données intimes.
  isPrivate: z.boolean().optional().default(true),
})

const DateQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD').optional(),
})

const LimitQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(50).optional().default(20),
})

export const journalRoutes: FastifyPluginAsync = async (app) => {

  // ── POST /journal/entry ─────────────────────────────────────────────────
  // Sauvegarde le contenu, déclenche l'analyse IA, retourne la réponse VITA.
  app.post('/entry', async (req, reply) => {
    const result = EntrySchema.safeParse(req.body)
    if (!result.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: result.error.flatten() })
    }

    const userId = (req.user as { sub: string }).sub
    const { content, isPrivate } = result.data

    // ── 1. Insert sans analyse (pour avoir l'id) ──────────────────────────
    const rows = await query<{ id: string }>(
      `INSERT INTO journal_entries (user_id, content, is_private)
       VALUES ($1, $2, $3) RETURNING id`,
      [userId, content, isPrivate]
    )
    const entryId = rows[0]!.id

    // ── 2. Analyse IA ─────────────────────────────────────────────────────
    let analysis: {
      mood_label: string
      emotional_tone: string
      themes: string[]
      intensity: number
      valence: number
      vita_response: string
      safety_flag: boolean
      safety_severity: string | null
    } | null = null

    try {
      analysis = await analyzeJournalEntry(userId, content, entryId)
    } catch (err) {
      if (err instanceof AIEngineError) {
        app.log.warn({ err, userId }, 'AI engine unavailable for journal analysis')
      } else {
        app.log.error({ err, userId }, 'Unexpected error during journal analysis')
      }
    }

    // ── 3. Update avec l'analyse ──────────────────────────────────────────
    if (analysis) {
      await query(
        `UPDATE journal_entries
         SET mood_label     = $1,
             emotional_tone = $2,
             themes         = $3::jsonb,
             intensity      = $4,
             vita_response  = $5,
             updated_at     = NOW()
         WHERE id = $6 AND user_id = $7`,
        [
          analysis.mood_label,
          analysis.emotional_tone,
          JSON.stringify(analysis.themes),
          analysis.intensity,
          analysis.vita_response,
          entryId,
          userId,
        ]
      )
    }

    return reply.status(201).send({
      id: entryId,
      vitaResponse: analysis?.vita_response ?? null,
      moodLabel: analysis?.mood_label ?? null,
      themes: analysis?.themes ?? [],
    })
  })

  // ── GET /journal/recent ─────────────────────────────────────────────────
  // GET /journal/recent?limit=20
  // Returns: journal_entries[] avec contenu complet (usage privé iOS uniquement)
  // Errors: 400 si limit invalide
  // Auth: JWT requis
  app.get('/recent', async (req, reply) => {
    const parsed = LimitQuerySchema.safeParse(req.query)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const parsedLimit = parsed.data.limit

    const entries = await query<{
      id: string
      content: string
      mood_label: string | null
      emotional_tone: string | null
      themes: unknown
      intensity: number | null
      vita_response: string | null
      is_private: boolean
      created_at: string
    }>(
      `SELECT id, content, mood_label, emotional_tone, themes, intensity,
              vita_response, is_private, created_at
       FROM journal_entries
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [userId, parsedLimit]
    )

    return reply.send(entries)
  })

  // ── GET /journal/timeline ───────────────────────────────────────────────
  // GET /journal/timeline?date=YYYY-MM-DD
  // Returns: entrées anonymisées (sans contenu brut) pour une date donnée
  // Errors: 400 si date invalide
  // Auth: JWT requis
  app.get('/timeline', async (req, reply) => {
    const parsed = DateQuerySchema.safeParse(req.query)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const date = parsed.data.date ?? new Date().toISOString().split('T')[0]

    const entries = await query<{
      id: string
      mood_label: string | null
      themes: unknown
      intensity: number | null
      created_at: string
    }>(
      `SELECT id, mood_label, themes, intensity, created_at
       FROM journal_entries
       WHERE user_id = $1 AND created_at::date = $2::date
       ORDER BY created_at ASC`,
      [userId, date]
    )

    return reply.send(entries)
  })

  // ── GET /journal/memories ───────────────────────────────────────────────
  // Thèmes émotionnels récurrents de l'utilisateur.
  app.get('/memories', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const memories = await query<{
      id: string
      theme: string
      summary: string | null
      valence: number | null
      recurrence_count: number
      last_seen_at: string
      confidence: number
    }>(
      `SELECT id, theme, summary, valence::FLOAT8 AS valence,
              recurrence_count::INT AS recurrence_count,
              last_seen_at, confidence::FLOAT8 AS confidence
       FROM emotional_memories
       WHERE user_id = $1
       ORDER BY last_seen_at DESC
       LIMIT 20`,
      [userId]
    )

    return reply.send(memories)
  })
}
