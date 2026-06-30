-- Migration 015 — Sport Foundation
-- Sprint 11 : profil sportif et plans d'entraînement
--
-- Nouvelles tables :
--   A. sport_profiles   — préférences sportives de l'utilisateur
--   B. training_plans   — plans hebdomadaires (modèle de semaine type)
--   C. training_plan_sessions — séances modèles dans un plan

BEGIN;

-- ── A. sport_profiles ────────────────────────────────────────────────────────
--
-- Une seule ligne par utilisateur (UNIQUE user_id).
-- Représente le contexte sportif : niveau, dispo, type d'activités préférées.
-- Aucun objectif chiffré imposé — cf. FOUNDING_PRINCIPLES.md §7.

CREATE TABLE sport_profiles (
    id                   UUID       PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id              UUID       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fitness_level        TEXT       NOT NULL DEFAULT 'beginner'
                                    CHECK (fitness_level IN ('beginner', 'intermediate', 'advanced', 'elite')),
    preferred_activities TEXT[]     NOT NULL DEFAULT '{}',
    sessions_per_week    SMALLINT   NOT NULL DEFAULT 3
                                    CHECK (sessions_per_week BETWEEN 1 AND 14),
    session_duration_min SMALLINT   NOT NULL DEFAULT 45
                                    CHECK (session_duration_min BETWEEN 10 AND 300),
    -- 0 = dimanche, 1 = lundi … 6 = samedi
    available_days       SMALLINT[] NOT NULL DEFAULT '{1,3,5}',
    -- Texte libre fourni par l'utilisateur : contexte, contraintes, historique
    context              TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id)
);

CREATE INDEX idx_sport_profiles_user ON sport_profiles (user_id);

CREATE TRIGGER trg_sport_profiles_updated_at
    BEFORE UPDATE ON sport_profiles
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── B. training_plans ────────────────────────────────────────────────────────
--
-- Un plan est une semaine type nommée.
-- Un seul plan peut être actif à la fois (is_active) — l'application
-- doit désactiver les autres avant d'en activer un.

CREATE TABLE training_plans (
    id          UUID       PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT       NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
    description TEXT,
    is_active   BOOLEAN    NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_training_plans_user ON training_plans (user_id, created_at DESC);

CREATE TRIGGER trg_training_plans_updated_at
    BEFORE UPDATE ON training_plans
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── C. training_plan_sessions ─────────────────────────────────────────────────
--
-- Chaque ligne représente une séance modèle planifiée un jour donné.
-- Plusieurs séances peuvent exister pour un même jour (e.g. matin + soir).

CREATE TABLE training_plan_sessions (
    id            UUID     PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id       UUID     NOT NULL REFERENCES training_plans(id) ON DELETE CASCADE,
    -- 0 = dimanche, 1 = lundi … 6 = samedi
    day_of_week   SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    activity_name TEXT     NOT NULL CHECK (char_length(activity_name) BETWEEN 1 AND 100),
    duration_min  SMALLINT NOT NULL DEFAULT 45 CHECK (duration_min BETWEEN 5 AND 300),
    notes         TEXT,
    sort_order    SMALLINT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_training_plan_sessions_plan
    ON training_plan_sessions (plan_id, day_of_week, sort_order);

COMMIT;
