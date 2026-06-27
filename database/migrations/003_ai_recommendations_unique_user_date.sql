-- Migration 003 : contrainte d'unicité (user_id, date) sur ai_recommendations
--
-- Contexte : ai_recommendations est une hypertable TimescaleDB partitionnée sur date.
-- Les contraintes UNIQUE sur une hypertable doivent inclure la colonne de partitionnement.
-- (user_id, date) satisfait cette exigence.
--
-- Effet : un seul enregistrement actif par utilisateur par jour.
-- Les INSERT … ON CONFLICT (user_id, date) DO UPDATE dans checkin.ts
-- et orchestrator.py deviennent valides.

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_recommendations_user_date_unique
    ON ai_recommendations (user_id, date);
