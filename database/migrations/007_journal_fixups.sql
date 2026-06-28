-- Migration 007 — Correctifs journal intelligence
--
-- Applique à la DB existante (après 006 déjà exécuté) :
--   1. updated_at sur safety_flags (colonne + trigger)
--   2. valence sur journal_entries (colonne)
--   3. is_private NOT NULL DEFAULT TRUE (cohérence RGPD — défaut protecteur)
--   4. Renommage d'index pour respecter la convention idx_table_colonnes
--   5. Triggers updated_at pour journal_entries, emotional_memories, life_events

BEGIN;

-- ── 1. safety_flags : ajouter updated_at ─────────────────────────────────────

ALTER TABLE safety_flags
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE TRIGGER trg_safety_flags_updated_at
    BEFORE UPDATE ON safety_flags
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 2. journal_entries : ajouter valence ────────────────────────────────────

ALTER TABLE journal_entries
    ADD COLUMN IF NOT EXISTS valence FLOAT CHECK (valence BETWEEN -1.0 AND 1.0);

-- ── 3. journal_entries : is_private — rendre NOT NULL avec défaut TRUE ───────
-- Les entrées existantes (is_private = FALSE créé par défaut) restent telles quelles.
-- Les nouvelles entrées sans is_private explicite seront privées.
-- On ne modifie PAS les lignes existantes : l'utilisateur avait consenti à is_private=false.

ALTER TABLE journal_entries
    ALTER COLUMN is_private SET NOT NULL,
    ALTER COLUMN is_private SET DEFAULT TRUE;

-- ── 4. Renommage d'index pour respecter idx_table_colonnes ──────────────────

ALTER INDEX IF EXISTS idx_journal_entries_user_date    RENAME TO idx_journal_entries_user_created;
ALTER INDEX IF EXISTS idx_emotional_memories_user      RENAME TO idx_emotional_memories_user_seen;
ALTER INDEX IF EXISTS idx_safety_flags_user_unresolved RENAME TO idx_safety_flags_user_created;

-- ── 5. Triggers updated_at pour les trois tables ─────────────────────────────

CREATE TRIGGER trg_journal_entries_updated_at
    BEFORE UPDATE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_emotional_memories_updated_at
    BEFORE UPDATE ON emotional_memories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_life_events_updated_at
    BEFORE UPDATE ON life_events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

COMMIT;
