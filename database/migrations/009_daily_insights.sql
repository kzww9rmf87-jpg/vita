-- 009_daily_insights.sql
-- Daily Insight Engine : synthèse quotidienne interprétative de VITA.
--
-- Chaque ligne représente la compréhension de VITA pour un jour donné.
-- Jamais un score — une interprétation du vécu.
-- Idempotent : UNIQUE(user_id, date) garantit une seule génération par jour.

BEGIN;

CREATE TABLE daily_insights (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date        DATE          NOT NULL,
  climate     TEXT          NOT NULL CHECK (climate IN (
                              'CALM', 'CONSTRUCTIVE', 'DEMANDING', 'RECOVERY',
                              'UNCERTAIN', 'ENERGIZED', 'REFLECTIVE',
                              'TRANSITION', 'BALANCED'
                            )),
  summary     TEXT          NOT NULL,    -- 1 phrase, max 35 mots
  drivers     TEXT[]        NOT NULL DEFAULT '{}',  -- 2–5 facteurs
  reflection  TEXT          NOT NULL,   -- paragraphe descriptif, max 120 mots
  question    TEXT          NOT NULL,   -- 1 question, max 25 mots
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT daily_insights_user_date_unique UNIQUE (user_id, date)
);

CREATE INDEX idx_daily_insights_user_date ON daily_insights (user_id, date DESC);

-- Trigger updated_at automatique
CREATE OR REPLACE FUNCTION update_daily_insights_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_daily_insights_updated_at
  BEFORE UPDATE ON daily_insights
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_insights_updated_at();

COMMIT;
