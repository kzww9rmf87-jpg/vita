import Fastify from 'fastify'
import cors from '@fastify/cors'
import jwt from '@fastify/jwt'
import { query } from './db.js'
import { sleepRoutes } from './routes/sleep.js'
import { activityRoutes } from './routes/activity.js'
import { nutritionRoutes } from './routes/nutrition.js'
import { checkinRoutes } from './routes/checkin.js'
import { dashboardRoutes } from './routes/dashboard.js'
import { eventsRoutes } from './routes/events.js'
import { chatRoutes } from './routes/chat.js'
import { profileRoutes } from './routes/profile.js'

async function main() {
  const app = Fastify({ logger: true })

  await app.register(cors, {
    origin: process.env.ALLOWED_ORIGINS?.split(',') ?? ['http://localhost:3000'],
    credentials: true,
  })
  await app.register(jwt, { secret: process.env.JWT_SECRET! })

  app.addHook('onRequest', async (req, reply) => {
    if ((req.routeOptions.config as unknown as Record<string, unknown>)?.['public']) return
    try {
      await req.jwtVerify()
    } catch {
      reply.status(401).send({ error: 'UNAUTHORIZED' })
    }
  })

  await app.register(sleepRoutes, { prefix: '/sleep' })
  await app.register(activityRoutes, { prefix: '/activity' })
  await app.register(nutritionRoutes, { prefix: '/nutrition' })
  await app.register(checkinRoutes, { prefix: '/checkin' })
  await app.register(dashboardRoutes, { prefix: '/dashboard' })
  await app.register(eventsRoutes, { prefix: '/dashboard' })
  await app.register(chatRoutes, { prefix: '/chat' })
  await app.register(profileRoutes, { prefix: '/profile' })

  app.get('/health', { config: { public: true } }, async () => ({
    status: 'ok', service: 'data',
  }))

  await query('SELECT 1')
  await app.listen({ port: Number(process.env.PORT ?? 3002), host: '0.0.0.0' })
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
