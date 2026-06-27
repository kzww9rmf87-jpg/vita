// Route SSE : GET /dashboard/events
//
// L'iOS se connecte à cette route après le check-in matinal.
// La connexion reste ouverte et reçoit :
//   event: thinking  → messages de raisonnement de VITA pendant la génération
//   event: recommendation → la recommandation finale
//   event: error     → si la génération échoue
//
// La connexion est maintenue vivante par des pings toutes les 30s
// (évite la fermeture par timeout des proxies/mobiles).

import type { FastifyPluginAsync } from 'fastify'
import { registerConnection, unregisterConnection } from '../sse-manager.js'

export const eventsRoutes: FastifyPluginAsync = async (app) => {

  // GET /dashboard/events
  app.get('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const res = reply.raw

    // Headers SSE standards
    // X-Accel-Buffering: no est requis pour que Nginx ne bufférise pas la réponse
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
    })

    // Commentaire initial SSE : établit la connexion sans émettre d'événement
    res.write(': connected\n\n')

    registerConnection(userId, res)

    // Ping toutes les 30s pour maintenir la connexion sur réseau mobile
    const keepAlive = setInterval(() => {
      try {
        res.write(': ping\n\n')
      } catch {
        clearInterval(keepAlive)
      }
    }, 30_000)

    req.raw.on('close', () => {
      clearInterval(keepAlive)
      unregisterConnection(userId, res)
      app.log.debug({ userId }, 'SSE connection closed')
    })

    // Fastify ne doit pas finaliser la réponse — on gère le stream manuellement
    return reply.hijack()
  })
}
