/**
 * Timeline VITA — journal quotidien chronologique.
 *
 * Agrège en une seule requête UNION ALL tous les événements de la journée :
 * check-ins, recommandations, conversations, sport, sommeil, nutrition.
 *
 * Chaque événement expose uniquement ce dont l'iOS a besoin pour l'afficher.
 * Les métadonnées brutes sont en `meta` pour un usage futur (détail, widgets…).
 *
 * Extensibilité : ajouter un nouveau type = ajouter un SELECT dans l'UNION.
 * Le contrat de réponse (id, type, time, title, subtitle, icon, color_key, meta)
 * est stable et versionnnable indépendamment des sources.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query } from '../db.js'

const DateQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD').optional(),
})

export const timelineRoutes: FastifyPluginAsync = async (app) => {

  // GET /timeline?date=YYYY-MM-DD
  // Returns: TimelineEvent[] chronologique pour une date
  // Errors: 400 si date invalide (format non-YYYY-MM-DD)
  // Auth: JWT requis
  app.get('/', async (req, reply) => {
    const parsed = DateQuerySchema.safeParse(req.query)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const date = parsed.data.date ?? new Date().toISOString().split('T')[0]

    const events = await query<{
      id: string
      type: string
      time: string
      title: string
      subtitle: string | null
      icon: string
      color_key: string
      meta: Record<string, unknown>
    }>(
      `
      -- ── Check-ins ────────────────────────────────────────────────────────────
      SELECT
        'checkin-' || id::text                                        AS id,
        'checkin'                                                     AS type,
        COALESCE(
          completed_at,
          date::timestamptz + CASE type
            WHEN 'morning' THEN interval '7 hours'
            ELSE                 interval '21 hours'
          END
        )                                                             AS time,
        CASE type
          WHEN 'morning' THEN 'Check-in du matin'
          ELSE                'Check-in du soir'
        END                                                           AS title,
        CONCAT(
          'Énergie ', energy, '/5',
          CASE WHEN stress IS NOT NULL
            THEN CONCAT(' · Stress ', stress, '/5') ELSE '' END
        )                                                             AS subtitle,
        CASE type
          WHEN 'morning' THEN 'sun.max.fill'
          ELSE                'moon.stars.fill'
        END                                                           AS icon,
        'accent'                                                      AS color_key,
        jsonb_build_object(
          'energy', energy, 'mood', mood, 'stress', stress,
          'checkin_type', type
        )                                                             AS meta
      FROM daily_checkins
      WHERE user_id = $1 AND date = $2::date

      UNION ALL

      -- ── Recommandations IA ───────────────────────────────────────────────────
      SELECT
        'reco-' || id::text                                           AS id,
        'recommendation'                                              AS type,
        created_at                                                    AS time,
        'Recommandation VITA'                                         AS title,
        LEFT(content, 100)                                            AS subtitle,
        'brain.head.profile'                                          AS icon,
        'vita'                                                        AS color_key,
        jsonb_build_object(
          'action_type',  action_type,
          'agent_source', agent_source,
          'actions',      COALESCE(actions_json, '[]'::jsonb)
        )                                                             AS meta
      FROM ai_recommendations
      WHERE user_id = $1 AND date = $2::date AND dismissed = false

      UNION ALL

      -- ── Conversations VITA (groupées par jour) ────────────────────────────────
      SELECT
        'conv-' || DATE(MIN(created_at))::text                        AS id,
        'conversation'                                                AS type,
        MIN(created_at)                                               AS time,
        'Conversation avec VITA'                                      AS title,
        CONCAT(
          COUNT(*)::text, ' message',
          CASE WHEN COUNT(*) > 1 THEN 's' ELSE '' END
        )                                                             AS subtitle,
        'message.fill'                                                AS icon,
        'purple'                                                      AS color_key,
        jsonb_build_object('message_count', COUNT(*))                 AS meta
      FROM messages
      WHERE user_id = $1
        AND created_at::date = $2::date
        AND role = 'user'
      GROUP BY DATE(created_at)
      HAVING COUNT(*) > 0

      UNION ALL

      -- ── Séances de sport ─────────────────────────────────────────────────────
      SELECT
        'activity-' || id::text                                       AS id,
        'activity'                                                    AS type,
        COALESCE(started_at, created_at,
                 date::timestamptz + interval '18 hours')             AS time,
        COALESCE(activity_name, 'Séance')                             AS title,
        CONCAT(
          COALESCE(duration_minutes::text || ' min', ''),
          CASE WHEN rpe IS NOT NULL
            THEN CONCAT(' · RPE ', rpe, '/10') ELSE '' END,
          CASE WHEN calories_burned IS NOT NULL
            THEN CONCAT(' · ', calories_burned, ' kcal') ELSE '' END
        )                                                             AS subtitle,
        'dumbbell.fill'                                               AS icon,
        'activity'                                                    AS color_key,
        jsonb_build_object(
          'duration_minutes', duration_minutes,
          'rpe',              rpe,
          'calories_burned',  calories_burned
        )                                                             AS meta
      FROM activity_sessions
      WHERE user_id = $1 AND date = $2::date

      UNION ALL

      -- ── Sommeil ──────────────────────────────────────────────────────────────
      -- Affiché à l'heure du réveil (ou 07h par défaut)
      SELECT
        'sleep-' || id::text                                          AS id,
        'sleep'                                                       AS type,
        COALESCE(wake_time,
                 date::timestamptz + interval '7 hours')              AS time,
        'Sommeil'                                                     AS title,
        CONCAT(
          ROUND((duration_minutes / 60.0)::NUMERIC, 1), 'h',
          CASE WHEN quality_score IS NOT NULL
            THEN CONCAT(' · Qualité ', quality_score, '/5') ELSE '' END
        )                                                             AS subtitle,
        'moon.fill'                                                   AS icon,
        'sleep'                                                       AS color_key,
        jsonb_build_object(
          'duration_minutes', duration_minutes,
          'quality_score',    quality_score,
          'energy_on_wake',   energy_on_wake
        )                                                             AS meta
      FROM sleep_entries
      WHERE user_id = $1 AND date = $2::date

      UNION ALL

      -- ── Nutrition ────────────────────────────────────────────────────────────
      SELECT
        'nutrition-' || id::text                                      AS id,
        'nutrition'                                                   AS type,
        COALESCE(created_at, date::timestamptz + interval '12 hours') AS time,
        'Nutrition'                                                   AS title,
        CONCAT(
          COALESCE(calories::text || ' kcal', ''),
          CASE WHEN protein_g IS NOT NULL
            THEN CONCAT(' · ', ROUND(protein_g::NUMERIC), 'g protéines') ELSE '' END
        )                                                             AS subtitle,
        'fork.knife'                                                  AS icon,
        'nutrition'                                                   AS color_key,
        jsonb_build_object(
          'calories',        calories,
          'protein_g',       protein_g,
          'adherence_score', adherence_score
        )                                                             AS meta
      FROM nutrition_daily
      WHERE user_id = $1 AND date = $2::date

      UNION ALL

      -- ── Climat intérieur du jour ──────────────────────────────────────────────
      -- Affiché en tête de timeline : synthèse interprétative, jamais le contenu brut.
      -- Le summary est court (max 35 mots), sans risque d'exposition de données sensibles.
      SELECT
        'insight-' || id::text                                        AS id,
        'daily_insight'                                               AS type,
        created_at                                                    AS time,
        CONCAT(
          CASE climate
            WHEN 'CALM'         THEN 'Calme'
            WHEN 'CONSTRUCTIVE' THEN 'Constructive'
            WHEN 'DEMANDING'    THEN 'Exigeante'
            WHEN 'RECOVERY'     THEN 'Récupération'
            WHEN 'UNCERTAIN'    THEN 'Incertaine'
            WHEN 'ENERGIZED'    THEN 'Dynamisée'
            WHEN 'REFLECTIVE'   THEN 'Réflexive'
            WHEN 'TRANSITION'   THEN 'En transition'
            WHEN 'BALANCED'     THEN 'Équilibrée'
            ELSE                     climate
          END
        )                                                             AS title,
        LEFT(summary, 100)                                            AS subtitle,
        CASE climate
          WHEN 'CALM'         THEN 'cloud.fill'
          WHEN 'CONSTRUCTIVE' THEN 'leaf.fill'
          WHEN 'DEMANDING'    THEN 'bolt.fill'
          WHEN 'RECOVERY'     THEN 'moon.fill'
          WHEN 'UNCERTAIN'    THEN 'wind'
          WHEN 'ENERGIZED'    THEN 'sun.max.fill'
          WHEN 'REFLECTIVE'   THEN 'sparkles'
          WHEN 'TRANSITION'   THEN 'arrow.triangle.turn.up.right.circle.fill'
          WHEN 'BALANCED'     THEN 'circle.grid.2x2.fill'
          ELSE                     'sparkles'
        END                                                           AS icon,
        'vita'                                                        AS color_key,
        jsonb_build_object('climate', climate, 'drivers', drivers)    AS meta
      FROM daily_insights
      WHERE user_id = $1 AND date = $2::date

      UNION ALL

      -- ── Entrées de journal (titre anonymisé — jamais le contenu brut) ─────────
      SELECT
        'journal-' || id::text                                        AS id,
        'journal'                                                     AS type,
        created_at                                                    AS time,
        COALESCE(
          INITCAP(mood_label),
          'Entrée de journal'
        )                                                             AS title,
        CASE
          WHEN themes IS NOT NULL AND jsonb_array_length(themes) > 0
            THEN CONCAT(
              (themes ->> 0),
              CASE WHEN jsonb_array_length(themes) > 1
                THEN CONCAT(', ', (themes ->> 1)) ELSE '' END
            )
          ELSE NULL
        END                                                           AS subtitle,
        'book.fill'                                                   AS icon,
        'purple'                                                      AS color_key,
        jsonb_build_object(
          'intensity',      intensity,
          'emotional_tone', emotional_tone
        )                                                             AS meta
      FROM journal_entries
      WHERE user_id = $1
        AND created_at::date = $2::date
        AND is_private = false

      ORDER BY time ASC NULLS LAST
      `,
      [userId, date]
    )

    return reply.send(events)
  })
}
