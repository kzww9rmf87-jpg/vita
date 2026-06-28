-- Migration 011 — Domaine Énergie
--
-- Trois opérations :
--   A. Ajouter updated_at + triggers aux tables énergie existantes
--   B. Supprimer les tables de gamification (violation FOUNDING_PRINCIPLES)
--   C. Supprimer les colonnes de score de nutrition_daily (violation FOUNDING_PRINCIPLES)
--   D. Créer food_items, recipes, recipe_ingredients
--
-- NE PAS ajouter Apple Health ici — Sprint 8.
-- NE PAS ajouter d'analyse — Sprint 7 est uniquement les fondations.

BEGIN;

-- ── A. updated_at sur les tables énergie existantes ──────────────────────────

ALTER TABLE sleep_entries      ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE activity_sessions  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE nutrition_daily    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE meals               ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Fonction partagée pour les triggers updated_at du domaine énergie
CREATE OR REPLACE FUNCTION update_energy_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sleep_entries_updated_at
    BEFORE UPDATE ON sleep_entries
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

CREATE TRIGGER trg_activity_sessions_updated_at
    BEFORE UPDATE ON activity_sessions
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

CREATE TRIGGER trg_nutrition_daily_updated_at
    BEFORE UPDATE ON nutrition_daily
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

CREATE TRIGGER trg_meals_updated_at
    BEFORE UPDATE ON meals
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── B. Supprimer les tables de gamification ───────────────────────────────────
-- FOUNDING_PRINCIPLES.md : "Streaks et badges de gamification — Ne sera jamais construit"

DROP TABLE IF EXISTS user_achievements;
DROP TABLE IF EXISTS user_streaks;

-- ── C. Supprimer les colonnes de scoring de nutrition_daily ──────────────────
-- FOUNDING_PRINCIPLES.md : "Pas de score de santé"
-- Sprint 7 : "Aucun calcul intelligent. Aucun score."

ALTER TABLE nutrition_daily DROP COLUMN IF EXISTS quality_score;
ALTER TABLE nutrition_daily DROP COLUMN IF EXISTS adherence_score;

-- ── D. food_items ─────────────────────────────────────────────────────────────
--
-- Aliment de base du catalogue. Peut être un item système (user_id IS NULL)
-- ou créé par l'utilisateur. Les micronutriments sont extensibles via JSONB.

CREATE TABLE food_items (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        REFERENCES users(id) ON DELETE CASCADE,  -- null = item système
    name                TEXT        NOT NULL,
    brand               TEXT,
    -- Valeurs nutritionnelles pour 100 g
    calories_per_100g   SMALLINT,
    protein_per_100g    NUMERIC(5, 2),
    carbs_per_100g      NUMERIC(5, 2),
    fat_per_100g        NUMERIC(5, 2),
    fiber_per_100g      NUMERIC(5, 2),
    -- Micronutriments libres (vitamines, minéraux…)
    micronutrients      JSONB       NOT NULL DEFAULT '{}',
    -- Provenance
    source              TEXT        NOT NULL DEFAULT 'user'
                                    CHECK (source IN ('user', 'system', 'openfoodfacts')),
    barcode             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_food_items_name    ON food_items (LOWER(name));
CREATE INDEX idx_food_items_user    ON food_items (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_food_items_barcode ON food_items (barcode)  WHERE barcode IS NOT NULL;

CREATE TRIGGER trg_food_items_updated_at
    BEFORE UPDATE ON food_items
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── E. recipes ────────────────────────────────────────────────────────────────
--
-- Recette créée par l'utilisateur. Les totaux nutritionnels par portion
-- sont calculés à la saisie (par le data-service) à partir des ingrédients.

CREATE TABLE recipes (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    description     TEXT,
    servings        SMALLINT    NOT NULL DEFAULT 1 CHECK (servings > 0),
    -- Totaux par portion (calculés à la saisie, jamais par l'IA)
    calories        SMALLINT,
    protein_g       NUMERIC(5, 1),
    carbs_g         NUMERIC(5, 1),
    fat_g           NUMERIC(5, 1),
    fiber_g         NUMERIC(5, 1),
    prep_minutes    SMALLINT,
    cook_minutes    SMALLINT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recipes_user ON recipes (user_id, created_at DESC);

CREATE TRIGGER trg_recipes_updated_at
    BEFORE UPDATE ON recipes
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── F. recipe_ingredients ─────────────────────────────────────────────────────

CREATE TABLE recipe_ingredients (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_id       UUID        NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    food_item_id    UUID        REFERENCES food_items(id) ON DELETE SET NULL,
    name            TEXT        NOT NULL,   -- nom affiché même sans food_item lié
    quantity_g      NUMERIC(7, 2) NOT NULL CHECK (quantity_g > 0),
    sort_order      SMALLINT    NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients (recipe_id, sort_order);

CREATE TRIGGER trg_recipe_ingredients_updated_at
    BEFORE UPDATE ON recipe_ingredients
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

COMMIT;
