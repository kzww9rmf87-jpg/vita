-- Migration 005 : actions concrètes dans les recommandations IA
--
-- Stocke un tableau JSON de 3 actions quotidiennes générées par Claude
-- ou par le fallback rule-based. Nullable pour la compatibilité avec
-- les recommandations existantes (avant Sprint 2).

ALTER TABLE ai_recommendations
    ADD COLUMN IF NOT EXISTS actions_json jsonb;
