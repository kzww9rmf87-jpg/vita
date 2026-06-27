import crypto from 'crypto'
import { query } from './db.js'

const ACCESS_TOKEN_TTL = '15m'
const REFRESH_TOKEN_TTL_DAYS = 30

export async function generateTokens(userId: string, userAgent?: string | string[]) {
  const refreshToken = crypto.randomBytes(64).toString('hex')
  const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex')
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000)

  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, device_info, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [
      userId,
      tokenHash,
      JSON.stringify({ userAgent: Array.isArray(userAgent) ? userAgent[0] : userAgent }),
      expiresAt,
    ]
  )

  return {
    accessToken: await signAccessToken(userId),
    refreshToken,
    expiresIn: 900,
  }
}

async function signAccessToken(userId: string): Promise<string> {
  const { SignJWT } = await import('jose')
  const secret = new TextEncoder().encode(process.env.JWT_SECRET!)
  return new SignJWT({ sub: userId, type: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('15m')
    .sign(secret)
}

export async function revokeRefreshToken(tokenHash: string): Promise<void> {
  await query(
    'UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1',
    [tokenHash]
  )
}
