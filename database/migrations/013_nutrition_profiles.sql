-- Migration 013 — Profil nutritionnel utilisateur
--
-- Objectif : permettre à VITA de planifier de façon personnalisée.
-- Ce profil est un outil de CONFORT, pas de performance.
-- Les cibles sont des orientations internes — jamais des scores, jamais des objectifs
-- présentés à l'utilisateur comme des limites à ne pas dépasser.
--
-- FOUNDING_PRINCIPLES.md §7 :
--   "Jamais un journal de calories"
--   "Aucun jugement alimentaire"
--   "Pas de score de santé"
-- Ces cibles guident la planification, elles ne mesurent RIEN.

BEGIN;

CREATE TABLE nutrition_profiles (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- Objectif personnel (orientation, pas un régime imposé)
    objective           TEXT        NOT NULL DEFAULT 'maintain'
                                    CHECK (objective IN ('maintain', 'lose', 'gain', 'recompose')),

    -- Données anthropométriques (optionnelles — le profil fonctionne sans)
    weight_kg           NUMERIC(5,1) CHECK (weight_kg > 0),
    height_cm           SMALLINT     CHECK (height_cm > 0),
    age                 SMALLINT     CHECK (age BETWEEN 10 AND 120),
    sex                 TEXT         CHECK (sex IN ('male', 'female', 'other')),

    -- Niveau d'activité (pour le calcul TDEE)
    activity_level      TEXT        NOT NULL DEFAULT 'moderate'
                                    CHECK (activity_level IN (
                                        'sedentary', 'light', 'moderate', 'active', 'very_active'
                                    )),

    -- Préférences d'organisation
    meals_per_day       SMALLINT    NOT NULL DEFAULT 3 CHECK (meals_per_day BETWEEN 1 AND 6),
    batch_cooking       BOOLEAN     NOT NULL DEFAULT false,
    cook_time_available TEXT        CHECK (cook_time_available IN ('minimal', 'moderate', 'generous')),
    budget              TEXT        CHECK (budget IN ('low', 'medium', 'high')),

    -- Contraintes alimentaires (aucune validation médicale — déclaratives)
    allergies           TEXT[]      NOT NULL DEFAULT '{}',
    intolerances        TEXT[]      NOT NULL DEFAULT '{}',
    excluded_foods      TEXT[]      NOT NULL DEFAULT '{}',
    preferred_cuisines  TEXT[]      NOT NULL DEFAULT '{}',

    -- Cibles nutritionnelles journalières calculées par l'algorithme Harris-Benedict.
    -- Ces valeurs sont des orientations internes pour la planification.
    -- Elles ne sont JAMAIS présentées comme "objectifs à atteindre" dans l'UI.
    target_calories     SMALLINT,
    target_protein_g    NUMERIC(5,1),
    target_carbs_g      NUMERIC(5,1),
    target_fat_g        NUMERIC(5,1),
    target_fiber_g      NUMERIC(5,1),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_nutrition_profiles_user ON nutrition_profiles (user_id);

CREATE TRIGGER trg_nutrition_profiles_updated_at
    BEFORE UPDATE ON nutrition_profiles
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- Ajouter la colonne daily_macros sur meal_plan_items pour stocker les macros calculées
-- au moment de la planification (snapshot — résiste aux modifications de recette).
ALTER TABLE meal_plan_items
    ADD COLUMN IF NOT EXISTS calories   SMALLINT,
    ADD COLUMN IF NOT EXISTS protein_g  NUMERIC(5,1),
    ADD COLUMN IF NOT EXISTS carbs_g    NUMERIC(5,1),
    ADD COLUMN IF NOT EXISTS fat_g      NUMERIC(5,1),
    ADD COLUMN IF NOT EXISTS fiber_g    NUMERIC(5,1);

COMMIT;
