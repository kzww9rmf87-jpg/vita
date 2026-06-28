/**
 * GET /life-story
 *
 * Retourne les mémoires longue durée de l'utilisateur, groupées par mois.
 * Aucune stat, aucun score numérique exposé au client — uniquement le récit.
 */
import type { FastifyPluginAsync } from 'fastify'
import { query } from '../db.js'

const FRENCH_MONTHS = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
]

function monthLabel(isoMonth: string): string {
  const [year, monthStr] = isoMonth.split('-')
  const idx = parseInt(monthStr!, 10) - 1
  return `${FRENCH_MONTHS[idx] ?? isoMonth} ${year}`
}

export const lifeStoryRoutes: FastifyPluginAsync = async (app) => {
  // GET /life-story
  // Auth : JWT requis (hook global)
  // Response : { groups: LifeStoryGroup[] }
  app.get('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const rows = await query<{
      id: string
      type: string
      summary: string
      last_seen: Date
    }>(
      `SELECT id, type, summary, last_seen
       FROM vita_long_memories
       WHERE user_id = $1 AND importance >= 3
       ORDER BY last_seen DESC
       LIMIT 100`,
      [userId]
    )

    // Groupement par mois UTC (YYYY-MM)
    const groupMap = new Map<string, Array<{ id: string; type: string; summary: string; lastSeen: string }>>()
    for (const row of rows) {
      const d = row.last_seen instanceof Date ? row.last_seen : new Date(row.last_seen as unknown as string)
      const month = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
      if (!groupMap.has(month)) groupMap.set(month, [])
      groupMap.get(month)!.push({
        id: row.id,
        type: row.type,
        summary: row.summary,
        lastSeen: d.toISOString(),
      })
    }

    const groups = Array.from(groupMap.entries()).map(([month, memories]) => ({
      month,
      label: monthLabel(month),
      memories,
    }))

    return reply.send({ groups })
  })
}
