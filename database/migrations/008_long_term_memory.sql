-- Migration 008 — Long Term Memory Engine
--
-- Deux nouvelles tables pour le Sprint 3 :
--   vita_long_memories : mémoires longue durée, typées, avec consolidation IA.
--                        Distinctes de vita_memories (rule-based, court terme).
--   vita_reflections   : réflexions hebdomadaires générées par VITA.
--
-- Architecture embedding : colonne TEXT pour l'instant (JSON array sérialisé).
-- Prévue pour migration ultérieure vers pgvector ou Pinecone sans toucher
-- au code applicatif grâce à l'interface MemoryProvider.

BEGIN;

-- ── vita_long_memories ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS vita_long_memories (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Type sémantique — détermine la pertinence contextuelle lors du retrieval
    type        TEXT        NOT NULL
        CHECK (type IN (
            'person', 'project', 'habit', 'fear', 'motivation',
            'goal', 'value', 'health', 'work', 'family',
            'emotion', 'event', 'other'
        )),

    -- Résumé en une phrase, rédigé par Claude, du point de vue neutre
    -- ex : "Travaille comme graphiste freelance depuis 3 ans"
    -- ex : "A peur de décevoir les personnes qu'il aime"
    summary     TEXT        NOT NULL,

    -- Importance 1-5 : pilote le retrieval et la durée de vie
    -- 1 = anecdotique, 3 = normal, 5 = fondamental pour comprendre la personne
    importance  SMALLINT    NOT NULL DEFAULT 3
        CHECK (importance BETWEEN 1 AND 5),

    -- Confidence 0.0-1.0 : certitude de l'extraction (baisse si contradictions)
    confidence  FLOAT       NOT NULL DEFAULT 0.8
        CHECK (confidence BETWEEN 0.0 AND 1.0),

    -- Source de l'extraction
    source      TEXT        NOT NULL
        CHECK (source IN ('journal', 'chat', 'checkin', 'explicit')),
    source_id   UUID,       -- id de l'entrée source (nullable — peut venir de plusieurs)

    -- Dernière apparition dans une interaction — pilote la fraîcheur au retrieval
    last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Placeholder embedding — sera migré vers pgvector ou Pinecone
    -- Format attendu : '[-0.12, 0.34, ...]' (JSON array de floats)
    embedding   TEXT,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Retrieval principal : user_id + importance décroissante
CREATE INDEX IF NOT EXISTS idx_vita_long_memories_user_importance
    ON vita_long_memories (user_id, importance DESC, last_seen DESC);

-- Retrieval par type (ex : "donne-moi tous les goals de cet utilisateur")
CREATE INDEX IF NOT EXISTS idx_vita_long_memories_user_type
    ON vita_long_memories (user_id, type, importance DESC);

-- Fraîcheur : mémoires vues récemment en premier
CREATE INDEX IF NOT EXISTS idx_vita_long_memories_user_seen
    ON vita_long_memories (user_id, last_seen DESC);

-- Contrainte anti-doublon : le même résumé (tronqué à 200 chars) ne peut
-- exister deux fois pour le même utilisateur. La consolidation deduplication
-- passe par merge() et non par un double INSERT.
CREATE UNIQUE INDEX IF NOT EXISTS idx_vita_long_memories_user_summary
    ON vita_long_memories (user_id, LEFT(summary, 200));

-- Trigger updated_at
CREATE TRIGGER trg_vita_long_memories_updated_at
    BEFORE UPDATE ON vita_long_memories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── vita_reflections ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS vita_reflections (
    id           UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Texte de la réflexion — 300 mots max, généré par Claude
    content      TEXT  NOT NULL,

    -- Période couverte (typiquement lundi → dimanche)
    period_start DATE  NOT NULL,
    period_end   DATE  NOT NULL,

    -- Thèmes identifiés dans la semaine (pour filtrage futur)
    themes       JSONB NOT NULL DEFAULT '[]',

    -- Question profonde posée à la fin de la réflexion (peut être null)
    question     TEXT,

    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Une réflexion par semaine par utilisateur
    UNIQUE (user_id, period_start)
);

CREATE INDEX IF NOT EXISTS idx_vita_reflections_user_date
    ON vita_reflections (user_id, period_start DESC);

COMMIT;
