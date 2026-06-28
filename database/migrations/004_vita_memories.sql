-- Migration 004 : table vita_memories — mémoire personnelle durable de VITA
--
-- Stocke les faits importants appris sur un utilisateur, quelle que soit leur source.
-- Alimentation : rule-based (check-ins, sommeil, activité, patterns)
--                + claude-based (conversations, quand crédits disponibles).
--
-- Utilisée pour injecter du contexte dans le chat et les recommandations,
-- donnant à l'utilisateur le sentiment que VITA le connaît vraiment.

CREATE TABLE IF NOT EXISTS vita_memories (
    id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Contenu de la mémoire — phrase courte, rédigée du point de vue de VITA
    -- ex : "A mentionné vouloir courir un semi-marathon"
    -- ex : "Énergie systématiquement basse le lundi matin"
    -- ex : "A battu son record au développé couché le 2026-06-20"
    content          TEXT        NOT NULL,

    -- Catégorie pour le filtrage et la pertinence contextuelle
    category         TEXT        NOT NULL
        CHECK (category IN ('goal', 'achievement', 'preference', 'emotion', 'pattern', 'event', 'health')),

    -- Source : d'où vient cette mémoire
    source           TEXT        NOT NULL
        CHECK (source IN ('checkin', 'sleep', 'activity', 'conversation', 'pattern', 'nutrition')),
    source_id        TEXT,       -- conversation_id, session_id, etc. (nullable)

    -- Importance : 1=basse 2=normale 3=haute (priorité d'injection dans le contexte)
    importance       SMALLINT    NOT NULL DEFAULT 2
        CHECK (importance BETWEEN 1 AND 3),

    -- Durée de vie : null = permanent, sinon date d'expiration
    expires_at       TIMESTAMP WITH TIME ZONE,

    active           BOOLEAN     NOT NULL DEFAULT TRUE,
    remembered_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Index principal : récupérer les mémoires actives d'un utilisateur, triées par importance
CREATE INDEX IF NOT EXISTS idx_vita_memories_user_active
    ON vita_memories (user_id, active, importance DESC, remembered_at DESC);

-- Évite les doublons : une mémoire identique (même content) ne peut pas être insérée deux fois
-- pour le même utilisateur. ON CONFLICT DO NOTHING dans le code.
CREATE UNIQUE INDEX IF NOT EXISTS idx_vita_memories_user_content_unique
    ON vita_memories (user_id, content);
