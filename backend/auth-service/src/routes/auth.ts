import type { FastifyPluginAsync } from 'fastify'
import bcrypt from 'bcryptjs'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import { generateTokens, revokeRefreshToken } from '../tokens.js'

const RegisterSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  firstName: z.string().min(1).max(50),
})

const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
})

const RefreshSchema = z.object({
  refreshToken: z.string(),
})

export const authRoutes: FastifyPluginAsync = async (app) => {

  app.post('/register', async (req, reply) => {
    const body = RegisterSchema.parse(req.body)

    const existing = await queryOne(
      'SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL',
      [body.email.toLowerCase()]
    )
    if (existing) {
      return reply.status(409).send({ error: 'EMAIL_TAKEN' })
    }

    const passwordHash = await bcrypt.hash(body.password, 12)

    const [user] = await query<{ id: string }>(
      `INSERT INTO users (email, password_hash, provider)
       VALUES ($1, $2, 'email')
       RETURNING id`,
      [body.email.toLowerCase(), passwordHash]
    )

    // primary_goal est obligatoire en base. On fixe 'feel_better' à l'inscription —
    // valeur générique qui sera remplacée par le vrai choix pendant l'onboarding.
    await query(
      `INSERT INTO user_profiles (user_id, first_name, primary_goal)
       VALUES ($1, $2, 'feel_better')`,
      [user.id, body.firstName]
    )

    const tokens = await generateTokens(user.id, req.headers['user-agent'])
    return reply.status(201).send(tokens)
  })

  app.post('/login', async (req, reply) => {
    const body = LoginSchema.parse(req.body)

    const user = await queryOne<{ id: string; password_hash: string }>(
      'SELECT id, password_hash FROM users WHERE email = $1 AND deleted_at IS NULL',
      [body.email.toLowerCase()]
    )

    if (!user || !user.password_hash) {
      return reply.status(401).send({ error: 'INVALID_CREDENTIALS' })
    }

    const valid = await bcrypt.compare(body.password, user.password_hash)
    if (!valid) {
      return reply.status(401).send({ error: 'INVALID_CREDENTIALS' })
    }

    const tokens = await generateTokens(user.id, req.headers['user-agent'])
    return reply.send(tokens)
  })

  app.post('/refresh', async (req, reply) => {
    const { refreshToken } = RefreshSchema.parse(req.body)

    const crypto = await import('crypto')
    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex')

    const record = await queryOne<{ user_id: string; expires_at: string }>(
      `SELECT user_id, expires_at FROM refresh_tokens
       WHERE token_hash = $1 AND revoked_at IS NULL`,
      [tokenHash]
    )

    if (!record || new Date(record.expires_at) < new Date()) {
      return reply.status(401).send({ error: 'INVALID_REFRESH_TOKEN' })
    }

    await revokeRefreshToken(tokenHash)
    const tokens = await generateTokens(record.user_id, req.headers['user-agent'])
    return reply.send(tokens)
  })

  app.post('/logout', { onRequest: [app.authenticate] }, async (req, reply) => {
    const { refreshToken } = RefreshSchema.parse(req.body)

    const crypto = await import('crypto')
    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex')
    await revokeRefreshToken(tokenHash)

    return reply.send({ success: true })
  })

  app.delete('/account', { onRequest: [app.authenticate] }, async (req, reply) => {
    const userId = (req.user as { id: string }).id
    await query(
      'UPDATE users SET deleted_at = NOW() WHERE id = $1',
      [userId]
    )
    await query(
      'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1',
      [userId]
    )
    return reply.send({ success: true, message: 'Account will be fully purged within 72 hours' })
  })
}

