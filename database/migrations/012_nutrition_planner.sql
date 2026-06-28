-- Migration 012 — Nutrition Planner
--
-- Objectif : supprimer la charge mentale liée à l'organisation des repas.
-- VITA organise. VITA ne juge pas. Aucun score. Aucun objectif imposé.
--
-- Nouvelles tables :
--   A. meal_plans         — plan hebdomadaire
--   B. meal_plan_items    — recettes planifiées dans un créneau (jour × repas)
--   C. shopping_list_items — liste de courses consolidée depuis le plan
--   D. pantry_items        — ingrédients toujours disponibles (filtrés de la liste)
--
-- Prérequis : recipes + recipe_ingredients créés en migration 011.

BEGIN;

-- ── A. meal_plans ─────────────────────────────────────────────────────────────
--
-- Un plan par semaine et par utilisateur.
-- week_start est toujours un lundi (contrainte applicative, pas SQL).

CREATE TABLE meal_plans (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    week_start  DATE        NOT NULL,
    name        TEXT,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, week_start)
);

CREATE INDEX idx_meal_plans_user ON meal_plans (user_id, week_start DESC);

CREATE TRIGGER trg_meal_plans_updated_at
    BEFORE UPDATE ON meal_plans
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── B. meal_plan_items ────────────────────────────────────────────────────────
--
-- Chaque ligne = une recette assignée à un créneau de la semaine.
-- recipe_name est snapshotté pour résister à la suppression de la recette.
-- day_of_week : 0 = lundi … 6 = dimanche.

CREATE TABLE meal_plan_items (
    id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    meal_plan_id UUID        NOT NULL REFERENCES meal_plans(id) ON DELETE CASCADE,
    day_of_week  SMALLINT    NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    meal_slot    TEXT        NOT NULL CHECK (meal_slot IN ('lunch', 'dinner')),
    recipe_id    UUID        REFERENCES recipes(id) ON DELETE SET NULL,
    recipe_name  TEXT        NOT NULL,
    portions     NUMERIC(4,1) NOT NULL DEFAULT 1 CHECK (portions > 0),
    notes        TEXT,
    sort_order   SMALLINT    NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_meal_plan_items_plan ON meal_plan_items (meal_plan_id, day_of_week, meal_slot);

-- ── C. shopping_list_items ────────────────────────────────────────────────────
--
-- Générés automatiquement depuis les recettes planifiées.
-- Consolidés (pas de doublons), filtrés par le garde-manger.
-- Catégories : conforme à l'interface iOS (emojis dans l'app, pas ici).

CREATE TABLE shopping_list_items (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    meal_plan_id    UUID        NOT NULL REFERENCES meal_plans(id) ON DELETE CASCADE,
    ingredient_name TEXT        NOT NULL,
    quantity        NUMERIC(10, 2),
    unit            TEXT,
    category        TEXT        NOT NULL DEFAULT 'other'
                                CHECK (category IN (
                                    'produce', 'meat', 'fish', 'dairy',
                                    'pantry', 'frozen', 'beverages', 'spices', 'other'
                                )),
    is_checked      BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shopping_list_plan ON shopping_list_items (meal_plan_id, category, ingredient_name);

CREATE TRIGGER trg_shopping_list_items_updated_at
    BEFORE UPDATE ON shopping_list_items
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── D. pantry_items ───────────────────────────────────────────────────────────
--
-- Ingrédients que l'utilisateur a toujours à la maison.
-- Ils sont exclus de la liste de courses lors de sa génération.
-- Contrainte UNIQUE sur (user_id, LOWER(ingredient_name)) — pas de doublon.

CREATE TABLE pantry_items (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ingredient_name TEXT        NOT NULL,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_pantry_user_name ON pantry_items (user_id, LOWER(ingredient_name));

CREATE TRIGGER trg_pantry_items_updated_at
    BEFORE UPDATE ON pantry_items
    FOR EACH ROW EXECUTE FUNCTION update_energy_updated_at();

-- ── Ajout updated_at à recipes (oubli migration 011 — présent déjà via trigger) ─
-- Recipes et recipe_ingredients ont déjà updated_at + triggers depuis 011.
-- Rien à ajouter ici.

COMMIT;
