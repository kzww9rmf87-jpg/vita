-- Migration 006 — Journal intime intelligent
--
-- Tables : journal_entries, emotional_memories, life_events, safety_flags
--
-- Contraintes de conception :
--   • Aucun contenu brut de message en clair en dehors de journal_entries.
--   • safety_flags.excerpt est limité à 200 caractères : suffisant pour la
--     relecture clinique, pas suffisant pour reconstituer le contexte complet.
--   • Toutes les tables ont CASCADE DELETE sur user_id.
--   • RGPD : suppression de l'utilisateur entraîne suppression de toutes les données.

BEGIN;

-- ── Journal entries ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS journal_entries (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Contenu utilisateur
    content         TEXT NOT NULL,

    -- Analyse émotionnelle produite par l'AI engine
    mood_label      TEXT,                     -- joie, tristesse, anxiété, colère, fatigue, fierté, neutre
    emotional_tone  TEXT,                     -- positif, négatif, ambivalent, neutre
    themes          JSONB DEFAULT '[]',        -- ["travail", "famille", "santé", …]
    intensity       SMALLINT CHECK (intensity BETWEEN 1 AND 10),
    valence         FLOAT CHECK (valence BETWEEN -1.0 AND 1.0),

    -- Réponse VITA
    vita_response   TEXT,

    -- Vie privée — défaut TRUE : une entrée est privée sauf décision explicite contraire
    is_private      BOOLEAN NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_user_created
    ON journal_entries (user_id, created_at DESC);

-- ── Mémoire émotionnelle ─────────────────────────────────────────────────────
--
-- Résumé évolutif par thème. Une ligne par (user, theme).
-- Mise à jour après chaque entrée de journal qui touche ce thème.

CREATE TABLE IF NOT EXISTS emotional_memories (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    theme             TEXT NOT NULL,          -- thème détecté (travail, famille, santé, …)
    summary           TEXT,                  -- phrase de synthèse mise à jour par l'AI
    valence           FLOAT CHECK (valence BETWEEN -1.0 AND 1.0), -- -1 très négatif → +1 très positif
    recurrence_count  INTEGER DEFAULT 1,
    last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confidence        FLOAT DEFAULT 0.5 CHECK (confidence BETWEEN 0.0 AND 1.0),

    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, theme)
);

CREATE INDEX IF NOT EXISTS idx_emotional_memories_user_seen
    ON emotional_memories (user_id, last_seen_at DESC);

-- ── Événements de vie ────────────────────────────────────────────────────────
--
-- Moments significatifs détectés ou déclarés explicitement.
-- Servent de contexte long-terme pour la personnalisation.

CREATE TABLE IF NOT EXISTS life_events (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    event_type       TEXT NOT NULL,            -- rupture, promotion, deuil, déménagement, naissance, …
    title            TEXT NOT NULL,
    description      TEXT,
    emotional_weight FLOAT CHECK (emotional_weight BETWEEN -1.0 AND 1.0),
    event_date       DATE,
    source           TEXT DEFAULT 'journal',   -- journal | checkin | explicit

    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_life_events_user_date
    ON life_events (user_id, event_date DESC NULLS LAST);

-- ── Signaux de sécurité ──────────────────────────────────────────────────────
--
-- Détection de signaux de crise (idéations, désespoir, etc.)
-- Jamais exposé à l'iOS — usage interne et supervision humaine uniquement.
-- excerpt : 200 chars max pour permettre relecture sans reconstituer le contexte.

CREATE TABLE IF NOT EXISTS safety_flags (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    source      TEXT NOT NULL DEFAULT 'journal',  -- journal | checkin | chat
    severity    TEXT NOT NULL DEFAULT 'low',       -- low | medium | high | critical
    category    TEXT NOT NULL,                     -- ideation_passive | ideation_active | self_harm | crisis | hopelessness
    excerpt     TEXT CHECK (char_length(excerpt) <= 200),
    resolved    BOOLEAN DEFAULT FALSE,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- updated_at permet d'auditer quand un flag a été résolu
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_safety_flags_user_created
    ON safety_flags (user_id, created_at DESC)
    WHERE resolved = FALSE;

COMMIT;
