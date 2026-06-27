#!/usr/bin/env node
/**
 * Runner de migrations SQL pour VITA.
 *
 * Comportement :
 * - Lit tous les fichiers *.sql de database/migrations/ dans l'ordre numérique
 * - Maintient une table schema_migrations pour ne jamais rejouer une migration
 * - Une migration échouée arrête le processus immédiatement (exit 1)
 * - Idempotent : peut être lancé plusieurs fois sans effet si tout est déjà appliqué
 *
 * Usage : node database/migrate.js
 * Variable d'environnement requise : DATABASE_URL
 */

'use strict'

const { Pool } = require('pg')
const fs = require('node:fs')
const path = require('node:path')

const DATABASE_URL = process.env.DATABASE_URL
if (!DATABASE_URL) {
  console.error('[migrate] FATAL: DATABASE_URL environment variable is not set')
  process.exit(1)
}

const pool = new Pool({ connectionString: DATABASE_URL })

async function run() {
  const client = await pool.connect()

  try {
    // Crée la table de suivi si elle n'existe pas encore
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename   TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `)

    // Charge les migrations déjà appliquées
    const { rows: applied } = await client.query(
      'SELECT filename FROM schema_migrations ORDER BY filename'
    )
    const appliedSet = new Set(applied.map((r) => r.filename))

    // Rattrapage : si schema_migrations est vide mais que les tables existent déjà
    // (initialisation via docker-entrypoint-initdb.d ou migration manuelle antérieure),
    // marquer toutes les migrations trouvées comme appliquées sans les rejouer.
    if (appliedSet.size === 0) {
      const { rows: tableCheck } = await client.query(`
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'users' LIMIT 1
      `)
      if (tableCheck.length > 0) {
        const migrationsDir = path.join(__dirname, 'migrations')
        const allFiles = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()
        console.log('[migrate] Tables already exist — recording existing migrations without re-applying them')
        await client.query('BEGIN')
        try {
          for (const filename of allFiles) {
            await client.query(
              'INSERT INTO schema_migrations (filename) VALUES ($1) ON CONFLICT DO NOTHING',
              [filename]
            )
            console.log(`[migrate] ✓ (skipped) ${filename}`)
          }
          await client.query('COMMIT')
        } catch (err) {
          await client.query('ROLLBACK')
          throw err
        }
        console.log('[migrate] Nothing to migrate — database is up to date')
        return
      }
    }

    // Récupère les fichiers .sql dans l'ordre numérique
    const migrationsDir = path.join(__dirname, 'migrations')
    const files = fs
      .readdirSync(migrationsDir)
      .filter((f) => f.endsWith('.sql'))
      .sort()

    const pending = files.filter((f) => !appliedSet.has(f))

    if (pending.length === 0) {
      console.log('[migrate] Nothing to migrate — database is up to date')
      return
    }

    for (const filename of pending) {
      const filepath = path.join(migrationsDir, filename)
      const sql = fs.readFileSync(filepath, 'utf8')

      console.log(`[migrate] Applying ${filename}...`)

      // Chaque migration est atomique : si elle échoue, on rollback et on arrête
      await client.query('BEGIN')
      try {
        await client.query(sql)
        await client.query(
          'INSERT INTO schema_migrations (filename) VALUES ($1)',
          [filename]
        )
        await client.query('COMMIT')
        console.log(`[migrate] v ${filename}`)
      } catch (err) {
        await client.query('ROLLBACK')
        console.error(`[migrate] FAILED on ${filename}:`, err.message)
        process.exit(1)
      }
    }

    console.log(`[migrate] Done — ${pending.length} migration(s) applied`)
  } finally {
    client.release()
    await pool.end()
  }
}

run().catch((err) => {
  console.error('[migrate] Unexpected error:', err.message)
  process.exit(1)
})
