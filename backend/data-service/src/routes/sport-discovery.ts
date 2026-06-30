/**
 * Sport Discovery — routes data-service.
 *
 * Moteur de découverte conversationnel (Sprint 12.3).
 * VITA conduit un entretien 5-10 échanges, reformule, propose des activités.
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import {
  requestDiscoveryStart,
  requestDiscoveryMessage,
  requestDiscoveryReact,
  AIEngineError,
  type DiscoveryExchangePayload,
  type DiscoverySynthesisPayload,
  type ActivityProposalPayload,
} from '../ai-client.js'

// ── Schémas ───────────────────────────────────────────────────────────────────

const ExchangeSchema = z.object({
  role:    z.enum(['vita', 'user']),
  content: z.string().min(1).max(4000),
})

const SynthesisSchema = z.object({
  rapport_au_sport:       z.string().nullable().optional(),
  motivations:            z.array(z.string()).default([]),
  freins:                 z.array(z.string()).default([]),
  experiences_positives:  z.array(z.string()).default([]),
  experiences_negatives:  z.array(z.string()).default([]),
  contexte_prefere:       z.array(z.string()).default([]),
  contraintes:            z.array(z.string()).default([]),
  personnalite:           z.string().nullable().optional(),
  resume_valide:          z.string().nullable().optional(),
}).nullish()

const ActivityProposalSchema = z.object({
  name:             z.string().min(1).max(200),
  why_it_fits:      z.string().min(1).max(1000),
  first_step:       z.string().min(1).max(500),
  frequency:        z.string().min(1).max(200),
  constraint_level: z.enum(['tres_faible', 'faible', 'modere', 'eleve']),
})

const MessageBodySchema = z.object({
  user_message: z.string().min(1).max(4000),
  exchanges:    z.array(ExchangeSchema).max(40).default([]),
  status:       z.enum(['discovering', 'reformulating', 'proposing']).default('discovering'),
})

const ReactBodySchema = z.object({
  proposals:      z.array(ActivityProposalSchema).max(10),
  accepted_names: z.array(z.string()).max(10).default([]),
  refused_names:  z.array(z.string()).max(10).default([]),
  synthesis:      SynthesisSchema,
})

const ConfirmBodySchema = z.object({
  synthesis:    SynthesisSchema,
  exchanges:    z.array(ExchangeSchema).max(40).default([]),
})

// ── Helpers ───────────────────────────────────────────────────────────────────

function handleAIError(err: unknown): never {
  if (err instanceof AIEngineError) {
    if (err.status === 504) throw { statusCode: 504, code: 'AI_TIMEOUT',     message: 'AI engine timeout' }
    throw { statusCode: 502, code: 'AI_UNAVAILABLE', message: 'AI engine unavailable' }
  }
  throw err
}

// ── Routes ────────────────────────────────────────────────────────────────────

export const sportDiscoveryRoutes: FastifyPluginAsync = async (app) => {

  /**
   * POST /sport/discovery/start
   * Démarre ou reprend une session de découverte.
   * Si une session active existe déjà → retourne l'état existant.
   */
  app.post('/start', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    // Vérifie si une session active existe déjà
    const existing = await queryOne<{
      id: string
      status: string
      exchanges: DiscoveryExchangePayload[]
      synthesis: DiscoverySynthesisPayload | null
      proposals: ActivityProposalPayload[] | null
    }>(
      `SELECT id, status, exchanges, synthesis, proposals
       FROM discovery_sessions
       WHERE user_id = $1 AND domain = 'sport' AND status != 'completed'`,
      [userId]
    )

    if (existing) {
      return reply.send({
        already_started: true,
        session_id:      existing.id,
        status:          existing.status,
        exchanges:       existing.exchanges ?? [],
        synthesis:       existing.synthesis ?? null,
        proposals:       existing.proposals ?? [],
      })
    }

    // Démarre une nouvelle session — obtient le message d'ouverture
    let aiResult: { vita_opening: string; already_started: boolean }
    try {
      aiResult = await requestDiscoveryStart(userId, 'sport')
    } catch (err) {
      handleAIError(err)
    }

    // Crée la session en DB
    const vitaExchange: DiscoveryExchangePayload = { role: 'vita', content: aiResult.vita_opening }
    const row = await queryOne<{ id: string }>(
      `INSERT INTO discovery_sessions
         (user_id, domain, status, exchanges)
       VALUES ($1, 'sport', 'discovering', $2::jsonb)
       RETURNING id`,
      [userId, JSON.stringify([vitaExchange])]
    )

    return reply.code(201).send({
      already_started: false,
      session_id:      row!.id,
      status:          'discovering',
      vita_opening:    aiResult.vita_opening,
      exchanges:       [vitaExchange],
    })
  })

  /**
   * GET /sport/discovery/session
   * Retourne l'état courant de la session active (s'il en existe une).
   */
  app.get('/session', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const session = await queryOne<{
      id: string
      status: string
      exchanges: DiscoveryExchangePayload[]
      synthesis: DiscoverySynthesisPayload | null
      proposals: ActivityProposalPayload[] | null
      accepted_activities: string[] | null
      refused_activities: string[] | null
      created_at: string
      updated_at: string
    }>(
      `SELECT id, status, exchanges, synthesis, proposals,
              accepted_activities, refused_activities, created_at, updated_at
       FROM discovery_sessions
       WHERE user_id = $1 AND domain = 'sport'
       ORDER BY created_at DESC
       LIMIT 1`,
      [userId]
    )

    if (!session) {
      return reply.code(404).send({ error: 'NO_ACTIVE_SESSION' })
    }

    return reply.send({
      session_id:          session.id,
      status:              session.status,
      exchanges:           session.exchanges ?? [],
      synthesis:           session.synthesis ?? null,
      proposals:           session.proposals ?? [],
      accepted_activities: session.accepted_activities ?? [],
      refused_activities:  session.refused_activities ?? [],
      created_at:          session.created_at,
      updated_at:          session.updated_at,
    })
  })

  /**
   * POST /sport/discovery/message
   * Envoie un message utilisateur, reçoit la réponse VITA.
   * Persiste l'échange en DB et met à jour le statut.
   */
  app.post('/message', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const parse = MessageBodySchema.safeParse(req.body)
    if (!parse.success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR', details: parse.error.errors })
    }
    const { user_message, exchanges, status } = parse.data

    // Vérifie la session active
    const session = await queryOne<{ id: string; status: string }>(
      `SELECT id, status FROM discovery_sessions
       WHERE user_id = $1 AND domain = 'sport' AND status != 'completed'`,
      [userId]
    )
    if (!session) {
      return reply.code(404).send({ error: 'NO_ACTIVE_SESSION' })
    }

    // Appel AI
    let aiResult: {
      vita_response: string
      new_status: string
      synthesis: DiscoverySynthesisPayload | null
      proposals: ActivityProposalPayload[]
    }
    try {
      aiResult = await requestDiscoveryMessage(userId, 'sport', exchanges, user_message, status)
    } catch (err) {
      handleAIError(err)
    }

    // Mise à jour de la session : ajoute les 2 échanges, met à jour le statut
    const userExchange: DiscoveryExchangePayload = { role: 'user', content: user_message }
    const vitaExchange: DiscoveryExchangePayload = { role: 'vita', content: aiResult.vita_response }

    await query(
      `UPDATE discovery_sessions
       SET exchanges  = exchanges || $2::jsonb,
           status     = $3,
           synthesis  = COALESCE($4::jsonb, synthesis),
           updated_at = now()
       WHERE id = $1`,
      [
        session.id,
        JSON.stringify([userExchange, vitaExchange]),
        aiResult.new_status,
        aiResult.synthesis ? JSON.stringify(aiResult.synthesis) : null,
      ]
    )

    return reply.send({
      vita_response: aiResult.vita_response,
      new_status:    aiResult.new_status,
      synthesis:     aiResult.synthesis ?? null,
      proposals:     aiResult.proposals ?? [],
    })
  })

  /**
   * POST /sport/discovery/confirm
   * L'utilisateur valide la reformulation de VITA.
   * Déclenche la génération des propositions d'activités.
   */
  app.post('/confirm', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const parse = ConfirmBodySchema.safeParse(req.body)
    if (!parse.success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR', details: parse.error.errors })
    }
    const { synthesis, exchanges } = parse.data

    const session = await queryOne<{ id: string }>(
      `SELECT id FROM discovery_sessions
       WHERE user_id = $1 AND domain = 'sport' AND status != 'completed'`,
      [userId]
    )
    if (!session) {
      return reply.code(404).send({ error: 'NO_ACTIVE_SESSION' })
    }

    // Appel AI pour générer les propositions
    const confirmMessage = "J'ai bien compris. Merci pour ces précisions."
    let aiResult: {
      vita_response: string
      new_status: string
      synthesis: DiscoverySynthesisPayload | null
      proposals: ActivityProposalPayload[]
    }
    try {
      aiResult = await requestDiscoveryMessage(
        userId,
        'sport',
        exchanges as DiscoveryExchangePayload[],
        confirmMessage,
        'proposing',
      )
    } catch (err) {
      handleAIError(err)
    }

    // Persiste les propositions
    await query(
      `UPDATE discovery_sessions
       SET status     = 'proposing',
           synthesis  = COALESCE($2::jsonb, synthesis),
           proposals  = $3::jsonb,
           updated_at = now()
       WHERE id = $1`,
      [
        session.id,
        synthesis ? JSON.stringify(synthesis) : null,
        JSON.stringify(aiResult.proposals ?? []),
      ]
    )

    return reply.send({
      vita_response: aiResult.vita_response,
      new_status:    'proposing',
      proposals:     aiResult.proposals ?? [],
    })
  })

  /**
   * POST /sport/discovery/react
   * L'utilisateur accepte/refuse des propositions.
   * Met à jour accepted_activities / refused_activities en DB.
   * Si is_complete → écrit sport_identity et ferme la session.
   */
  app.post('/react', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const parse = ReactBodySchema.safeParse(req.body)
    if (!parse.success) {
      return reply.code(400).send({ error: 'VALIDATION_ERROR', details: parse.error.errors })
    }
    const { proposals, accepted_names, refused_names, synthesis } = parse.data

    const session = await queryOne<{
      id: string
      synthesis: DiscoverySynthesisPayload | null
      accepted_activities: string[]
      refused_activities:  string[]
    }>(
      `SELECT id, synthesis, accepted_activities, refused_activities FROM discovery_sessions
       WHERE user_id = $1 AND domain = 'sport' AND status != 'completed'`,
      [userId]
    )
    if (!session) {
      return reply.code(404).send({ error: 'NO_ACTIVE_SESSION' })
    }

    // Appel AI pour la réaction
    const effectiveSynthesis = (synthesis ?? session.synthesis) as DiscoverySynthesisPayload | null
    let aiResult: {
      vita_response: string
      new_proposals: ActivityProposalPayload[]
      is_complete: boolean
    }
    try {
      aiResult = await requestDiscoveryReact(
        userId,
        'sport',
        proposals as ActivityProposalPayload[],
        accepted_names,
        refused_names,
        effectiveSynthesis,
      )
    } catch (err) {
      handleAIError(err)
    }

    // Fusionne les activités du round courant avec celles déjà accumulées en DB.
    // Nécessaire pour les scénarios multi-rounds (is_complete=false puis true).
    const prevAccepted = session.accepted_activities ?? []
    const prevRefused  = session.refused_activities  ?? []
    const allAccepted = [...new Set([...prevAccepted, ...accepted_names])]
    const allRefused  = [...new Set([...prevRefused,  ...refused_names])]
      // Les activités acceptées ne peuvent pas aussi être refusées
      .filter(name => !allAccepted.includes(name))

    if (aiResult.is_complete) {
      // Ferme la session
      await query(
        `UPDATE discovery_sessions
         SET status               = 'completed',
             accepted_activities  = $2::jsonb,
             refused_activities   = $3::jsonb,
             updated_at           = now()
         WHERE id = $1`,
        [session.id, JSON.stringify(allAccepted), JSON.stringify(allRefused)]
      )

      // Écrit (ou met à jour) le sport_identity
      const synth = effectiveSynthesis
      await query(
        `INSERT INTO sport_identity
           (user_id, rapport_au_sport, motivations, freins, experiences_positives,
            experiences_negatives, personnalite, contexte_prefere, contraintes,
            activites_recommandees, activites_refusees, resume_valide, discovery_session_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
         ON CONFLICT (user_id) DO UPDATE SET
           rapport_au_sport       = EXCLUDED.rapport_au_sport,
           motivations            = EXCLUDED.motivations,
           freins                 = EXCLUDED.freins,
           experiences_positives  = EXCLUDED.experiences_positives,
           experiences_negatives  = EXCLUDED.experiences_negatives,
           personnalite           = EXCLUDED.personnalite,
           contexte_prefere       = EXCLUDED.contexte_prefere,
           contraintes            = EXCLUDED.contraintes,
           activites_recommandees = EXCLUDED.activites_recommandees,
           activites_refusees     = EXCLUDED.activites_refusees,
           resume_valide          = EXCLUDED.resume_valide,
           discovery_session_id   = EXCLUDED.discovery_session_id,
           updated_at             = now()`,
        [
          userId,
          synth?.rapport_au_sport ?? null,
          JSON.stringify(synth?.motivations ?? []),
          JSON.stringify(synth?.freins ?? []),
          JSON.stringify(synth?.experiences_positives ?? []),
          JSON.stringify(synth?.experiences_negatives ?? []),
          synth?.personnalite ?? null,
          JSON.stringify(synth?.contexte_prefere ?? []),
          JSON.stringify(synth?.contraintes ?? []),
          JSON.stringify(allAccepted),
          JSON.stringify(allRefused),
          synth?.resume_valide ?? null,
          session.id,
        ]
      )
    } else {
      // Accumule les activités acceptées/refusées au fil des rounds
      await query(
        `UPDATE discovery_sessions
         SET accepted_activities = $2::jsonb,
             refused_activities  = $3::jsonb,
             proposals           = $4::jsonb,
             updated_at          = now()
         WHERE id = $1`,
        [
          session.id,
          JSON.stringify(allAccepted),
          JSON.stringify(allRefused),
          JSON.stringify(aiResult.new_proposals ?? []),
        ]
      )
    }

    return reply.send({
      vita_response:  aiResult.vita_response,
      new_proposals:  aiResult.new_proposals ?? [],
      is_complete:    aiResult.is_complete,
    })
  })
}
