-- Migration 010 — Première Rencontre
--
-- La Première Rencontre est la conversation initiale entre VITA et l'utilisateur.
-- Ce n'est pas un onboarding : c'est une conversation naturelle, profonde, IA-pilotée.
-- À la fin, VITA génère un portrait intime de la personne.
--
-- Tables :
--   first_encounter_sessions  : une session par utilisateur, état de la conversation
--   first_encounter_exchanges : historique des échanges (vita / user)

BEGIN;

-- ── Sessions ─────────────────────────────────────────────────────────────────

CREATE TABLE first_encounter_sessions (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Statut de la conversation
    status          TEXT        NOT NULL DEFAULT 'in_progress'
                                CHECK (status IN ('in_progress', 'completed')),

    -- Indice du thème courant (0-11 pour les 12 thèmes)
    topic_index     INTEGER     NOT NULL DEFAULT 0,

    -- Nombre total d'échanges (user messages uniquement)
    exchange_count  INTEGER     NOT NULL DEFAULT 0,

    -- Portrait généré à la fin — max 500 mots, texte fluide
    portrait_text   TEXT,

    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Une seule Première Rencontre par utilisateur
    CONSTRAINT first_encounter_sessions_user_unique UNIQUE (user_id)
);

CREATE INDEX idx_first_encounter_sessions_user
    ON first_encounter_sessions (user_id);

-- ── Échanges ──────────────────────────────────────────────────────────────────

CREATE TABLE first_encounter_exchanges (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id  UUID        NOT NULL REFERENCES first_encounter_sessions(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Auteur du message
    role        TEXT        NOT NULL CHECK (role IN ('vita', 'user')),

    -- Contenu brut — jamais tronqué, jamais loggué
    content     TEXT        NOT NULL,

    -- Thème associé à cet échange (topic slug, ex : "valeurs")
    topic       TEXT,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_first_encounter_exchanges_session
    ON first_encounter_exchanges (session_id, created_at ASC);

CREATE INDEX idx_first_encounter_exchanges_user
    ON first_encounter_exchanges (user_id, created_at DESC);

-- ── Trigger updated_at ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_first_encounter_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_first_encounter_sessions_updated_at
    BEFORE UPDATE ON first_encounter_sessions
    FOR EACH ROW EXECUTE FUNCTION update_first_encounter_sessions_updated_at();

COMMIT;
