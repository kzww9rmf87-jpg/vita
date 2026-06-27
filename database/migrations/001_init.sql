-- VITA — Schéma complet de la base de données
-- Migration 001 : initialisation
-- PostgreSQL 16 + TimescaleDB

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "timescaledb";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────
-- UTILISATEURS ET PROFILS
-- ─────────────────────────────────────────────

CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email           TEXT UNIQUE NOT NULL,
  email_verified  BOOLEAN NOT NULL DEFAULT false,
  password_hash   TEXT,
  provider        TEXT CHECK (provider IN ('email', 'apple', 'google')),
  provider_id     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE TABLE user_profiles (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  first_name            TEXT NOT NULL,
  birth_year            SMALLINT,
  sex                   TEXT CHECK (sex IN ('male', 'female', 'other', 'prefer_not')),
  height_cm             NUMERIC(5,1),
  weight_start_kg       NUMERIC(5,2),
  primary_goal          TEXT NOT NULL CHECK (primary_goal IN ('perform', 'lose_weight', 'recover', 'feel_better')),
  activity_level        SMALLINT NOT NULL DEFAULT 3 CHECK (activity_level BETWEEN 1 AND 5),
  wake_time             TIME,
  sleep_time            TIME,
  timezone              TEXT NOT NULL DEFAULT 'Europe/Paris',
  language              TEXT NOT NULL DEFAULT 'fr',
  units                 TEXT NOT NULL DEFAULT 'metric' CHECK (units IN ('metric', 'imperial')),
  onboarding_done_at    TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

-- Snapshot quotidien du profil (mises à jour auto)
CREATE TABLE user_snapshots (
  id                    UUID DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                  DATE NOT NULL,
  weight_kg             NUMERIC(5,2),
  waist_cm              NUMERIC(5,1),
  body_fat_pct          NUMERIC(4,1),
  fitness_level         TEXT CHECK (fitness_level IN ('beginner', 'intermediate', 'advanced', 'elite')),
  baseline_energy       NUMERIC(3,1),
  baseline_mood         NUMERIC(3,1),
  baseline_sleep_hours  NUMERIC(4,2),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, date)
);
SELECT create_hypertable('user_snapshots', 'date');

-- ─────────────────────────────────────────────
-- AUTHENTIFICATION
-- ─────────────────────────────────────────────

CREATE TABLE refresh_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  device_info JSONB,
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE integrations (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider      TEXT NOT NULL CHECK (provider IN (
                  'apple_health', 'google_fit', 'garmin', 'polar',
                  'whoop', 'oura', 'strava', 'myfitnesspal', 'withings'
                )),
  access_token  TEXT,
  refresh_token TEXT,
  token_expires_at TIMESTAMPTZ,
  scope         TEXT[],
  last_synced_at TIMESTAMPTZ,
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, provider)
);

-- ─────────────────────────────────────────────
-- SOMMEIL
-- ─────────────────────────────────────────────

CREATE TABLE sleep_entries (
  id                  UUID DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                DATE NOT NULL,
  bedtime             TIMESTAMPTZ,
  wake_time           TIMESTAMPTZ,
  duration_minutes    SMALLINT,
  quality_score       SMALLINT CHECK (quality_score BETWEEN 1 AND 5),
  awakenings          SMALLINT DEFAULT 0,
  energy_on_wake      SMALLINT CHECK (energy_on_wake BETWEEN 1 AND 5),
  hrv_ms              NUMERIC(6,2),
  rhr_bpm             SMALLINT,
  nap_duration_min    SMALLINT DEFAULT 0,
  source              TEXT NOT NULL DEFAULT 'manual'
                        CHECK (source IN ('manual', 'apple_health', 'google_fit', 'oura', 'whoop', 'garmin', 'polar')),
  raw_data            JSONB,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, date),
  UNIQUE (user_id, date)
);
SELECT create_hypertable('sleep_entries', 'date');

-- ─────────────────────────────────────────────
-- ACTIVITÉ PHYSIQUE
-- ─────────────────────────────────────────────

CREATE TABLE activity_types (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  category    TEXT NOT NULL CHECK (category IN ('strength', 'cardio', 'hiit', 'mobility', 'combat', 'walk', 'active_recovery', 'other')),
  met_value   NUMERIC(4,2)
);

INSERT INTO activity_types (name, category, met_value) VALUES
  ('Musculation', 'strength', 6.0),
  ('Course à pied', 'cardio', 8.0),
  ('Vélo', 'cardio', 7.5),
  ('Natation', 'cardio', 8.0),
  ('HIIT', 'hiit', 10.0),
  ('Yoga', 'mobility', 3.0),
  ('Mobilité', 'mobility', 2.5),
  ('Boxe', 'combat', 9.0),
  ('MMA', 'combat', 10.0),
  ('Marche', 'walk', 3.5),
  ('Récupération active', 'active_recovery', 2.0),
  ('Pilates', 'mobility', 3.5),
  ('Escalade', 'other', 8.0),
  ('Tennis', 'other', 7.0),
  ('Football', 'other', 8.0);

CREATE TABLE activity_sessions (
  id                UUID DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date              DATE NOT NULL,
  started_at        TIMESTAMPTZ,
  ended_at          TIMESTAMPTZ,
  activity_type_id  INT REFERENCES activity_types(id),
  activity_name     TEXT,
  duration_minutes  SMALLINT,
  calories_burned   SMALLINT,
  hr_avg_bpm        SMALLINT,
  hr_max_bpm        SMALLINT,
  hr_zones          JSONB,
  rpe               SMALLINT CHECK (rpe BETWEEN 1 AND 10),
  distance_meters   INT,
  steps             INT,
  notes             TEXT,
  planned           BOOLEAN NOT NULL DEFAULT false,
  completed         BOOLEAN NOT NULL DEFAULT true,
  source            TEXT NOT NULL DEFAULT 'manual',
  external_id       TEXT,
  raw_data          JSONB,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, date)
);
SELECT create_hypertable('activity_sessions', 'date');

CREATE TABLE exercise_sets (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id      UUID NOT NULL,
  exercise_name   TEXT NOT NULL,
  muscle_groups   TEXT[],
  set_number      SMALLINT NOT NULL,
  reps            SMALLINT,
  weight_kg       NUMERIC(6,2),
  duration_sec    SMALLINT,
  rest_sec        SMALLINT,
  tempo           TEXT,
  tut_sec         SMALLINT,
  rpe             SMALLINT CHECK (rpe BETWEEN 1 AND 10),
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE daily_steps (
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date      DATE NOT NULL,
  steps     INT NOT NULL,
  source    TEXT NOT NULL DEFAULT 'manual',
  PRIMARY KEY (user_id, date)
);

-- ─────────────────────────────────────────────
-- NUTRITION
-- ─────────────────────────────────────────────

CREATE TABLE nutrition_daily (
  id                UUID DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date              DATE NOT NULL,
  calories          SMALLINT,
  protein_g         NUMERIC(6,1),
  carbs_g           NUMERIC(6,1),
  fat_g             NUMERIC(6,1),
  fiber_g           NUMERIC(5,1),
  water_ml          SMALLINT,
  alcohol_g         NUMERIC(5,1),
  caffeine_mg       SMALLINT,
  sodium_mg         SMALLINT,
  quality_score     NUMERIC(3,1),
  adherence_score   NUMERIC(3,2),
  meal_type         JSONB,
  supplements       TEXT[],
  notes             TEXT,
  source            TEXT NOT NULL DEFAULT 'manual',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, date),
  UNIQUE (user_id, date)
);
SELECT create_hypertable('nutrition_daily', 'date');

CREATE TABLE meals (
  id              UUID DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  eaten_at        TIMESTAMPTZ,
  meal_type       TEXT CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  description     TEXT,
  calories        SMALLINT,
  protein_g       NUMERIC(5,1),
  carbs_g         NUMERIC(5,1),
  fat_g           NUMERIC(5,1),
  is_restaurant   BOOLEAN DEFAULT false,
  photo_url       TEXT,
  ai_analyzed     BOOLEAN DEFAULT false,
  ai_confidence   NUMERIC(3,2),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, date)
);
SELECT create_hypertable('meals', 'date');

-- ─────────────────────────────────────────────
-- CHECK-INS QUOTIDIENS
-- ─────────────────────────────────────────────

CREATE TABLE daily_checkins (
  id              UUID DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('morning', 'evening')),
  energy          SMALLINT CHECK (energy BETWEEN 1 AND 5),
  mood            SMALLINT CHECK (mood BETWEEN 1 AND 5),
  stress          SMALLINT CHECK (stress BETWEEN 1 AND 5),
  motivation      SMALLINT CHECK (motivation BETWEEN 1 AND 5),
  pain_areas      TEXT[],
  pain_intensity  SMALLINT CHECK (pain_intensity BETWEEN 0 AND 10),
  libido          SMALLINT CHECK (libido BETWEEN 1 AND 5),
  concentration   SMALLINT CHECK (concentration BETWEEN 1 AND 5),
  special_event   TEXT,
  notes           TEXT,
  duration_sec    SMALLINT,
  completed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, date)
);
SELECT create_hypertable('daily_checkins', 'date');

-- ─────────────────────────────────────────────
-- MÉTRIQUES COMPLÉMENTAIRES
-- ─────────────────────────────────────────────

CREATE TABLE environmental_data (
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  weather         TEXT,
  temp_celsius    NUMERIC(4,1),
  screen_time_min SMALLINT,
  sun_exposure_min SMALLINT,
  work_hours      NUMERIC(4,1),
  travel          BOOLEAN DEFAULT false,
  PRIMARY KEY (user_id, date)
);

-- ─────────────────────────────────────────────
-- RECOMMANDATIONS IA
-- ─────────────────────────────────────────────

CREATE TABLE ai_recommendations (
  id              UUID DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date            DATE NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  agent_source    TEXT NOT NULL CHECK (agent_source IN (
                    'synthesis', 'sport', 'nutrition', 'sleep', 'mental', 'health'
                  )),
  content         TEXT NOT NULL,
  content_short   TEXT,
  action_type     TEXT CHECK (action_type IN ('do', 'adjust', 'avoid', 'rest', 'celebrate')),
  priority        SMALLINT NOT NULL DEFAULT 1,
  context_json    JSONB,
  reasoning       JSONB,
  completed       BOOLEAN,
  feedback_score  SMALLINT CHECK (feedback_score BETWEEN 1 AND 3),
  dismissed       BOOLEAN NOT NULL DEFAULT false,
  dismissed_at    TIMESTAMPTZ,
  PRIMARY KEY (id, date)
);
SELECT create_hypertable('ai_recommendations', 'date');

-- ─────────────────────────────────────────────
-- PATTERNS APPRIS
-- ─────────────────────────────────────────────

CREATE TABLE user_patterns (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  pattern_type          TEXT NOT NULL,
  description           TEXT NOT NULL,
  description_user      TEXT,
  variables             TEXT[],
  confidence            NUMERIC(4,3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  effect_size           NUMERIC(4,3),
  direction             TEXT CHECK (direction IN ('positive', 'negative', 'neutral')),
  first_detected_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_confirmed_at     TIMESTAMPTZ,
  confirmed_occurrences SMALLINT NOT NULL DEFAULT 1,
  active                BOOLEAN NOT NULL DEFAULT true,
  shown_to_user         BOOLEAN NOT NULL DEFAULT false,
  user_acknowledged     BOOLEAN,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- PROGRAMMES D'ENTRAÎNEMENT
-- ─────────────────────────────────────────────

CREATE TABLE training_programs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  goal            TEXT,
  weeks_total     SMALLINT NOT NULL,
  current_week    SMALLINT NOT NULL DEFAULT 1,
  sessions_per_week SMALLINT NOT NULL,
  started_at      DATE,
  ended_at        DATE,
  ai_generated    BOOLEAN NOT NULL DEFAULT false,
  active          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE program_sessions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_id      UUID NOT NULL REFERENCES training_programs(id) ON DELETE CASCADE,
  week_number     SMALLINT NOT NULL,
  day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
  name            TEXT NOT NULL,
  focus           TEXT,
  exercises       JSONB NOT NULL DEFAULT '[]',
  estimated_duration_min SMALLINT,
  completed_at    TIMESTAMPTZ,
  actual_session_id UUID
);

-- ─────────────────────────────────────────────
-- RAPPORTS PÉRIODIQUES
-- ─────────────────────────────────────────────

CREATE TABLE periodic_reports (
  id              UUID DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period_type     TEXT NOT NULL CHECK (period_type IN ('weekly', 'monthly', 'quarterly', 'annual')),
  period_start    DATE NOT NULL,
  period_end      DATE NOT NULL,
  generated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  content         JSONB NOT NULL,
  summary         TEXT,
  viewed_at       TIMESTAMPTZ,
  PRIMARY KEY (id, period_start)
);
SELECT create_hypertable('periodic_reports', 'period_start');

-- ─────────────────────────────────────────────
-- GAMIFICATION
-- ─────────────────────────────────────────────

CREATE TABLE user_streaks (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  streak_type     TEXT NOT NULL CHECK (streak_type IN (
                    'checkin', 'sleep', 'protein', 'activity', 'no_skip'
                  )),
  current_count   INT NOT NULL DEFAULT 0,
  best_count      INT NOT NULL DEFAULT 0,
  last_updated    DATE NOT NULL DEFAULT CURRENT_DATE,
  UNIQUE (user_id, streak_type)
);

CREATE TABLE user_achievements (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_key       TEXT NOT NULL,
  earned_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notified        BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (user_id, badge_key)
);

CREATE TABLE user_xp (
  user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  total_xp        INT NOT NULL DEFAULT 0,
  level           SMALLINT NOT NULL DEFAULT 1,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- CONVERSATIONS IA
-- ─────────────────────────────────────────────

CREATE TABLE conversations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at TIMESTAMPTZ
);

CREATE TABLE messages (
  id              UUID DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content         TEXT NOT NULL,
  agent_used      TEXT,
  tokens_used     INT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, created_at)
);
SELECT create_hypertable('messages', 'created_at');

-- ─────────────────────────────────────────────
-- INDEX POUR LES PERFORMANCES
-- ─────────────────────────────────────────────

CREATE INDEX idx_sleep_user_date ON sleep_entries (user_id, date DESC);
CREATE INDEX idx_activity_user_date ON activity_sessions (user_id, date DESC);
CREATE INDEX idx_nutrition_user_date ON nutrition_daily (user_id, date DESC);
CREATE INDEX idx_checkins_user_date ON daily_checkins (user_id, date DESC, type);
CREATE INDEX idx_recommendations_user_date ON ai_recommendations (user_id, date DESC);
CREATE INDEX idx_patterns_user_active ON user_patterns (user_id, active, confidence DESC);
CREATE INDEX idx_users_email ON users (email) WHERE deleted_at IS NULL;
CREATE INDEX idx_exercise_sets_session ON exercise_sets (session_id);

-- ─────────────────────────────────────────────
-- FONCTIONS UTILITAIRES
-- ─────────────────────────────────────────────

-- Mise à jour automatique de updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Vue pratique : données de la semaine courante par utilisateur
CREATE VIEW user_week_summary AS
SELECT
  u.id AS user_id,
  COUNT(DISTINCT se.date) AS sleep_days,
  AVG(se.duration_minutes)::NUMERIC(5,1) AS avg_sleep_min,
  AVG(se.quality_score)::NUMERIC(3,1) AS avg_sleep_quality,
  COUNT(DISTINCT act.date) AS activity_days,
  SUM(act.duration_minutes) AS total_activity_min,
  AVG(nd.calories)::INT AS avg_calories,
  AVG(nd.protein_g)::NUMERIC(5,1) AS avg_protein_g,
  COUNT(DISTINCT dc.date) AS checkin_days,
  AVG(dc.energy)::NUMERIC(3,1) AS avg_energy,
  AVG(dc.mood)::NUMERIC(3,1) AS avg_mood,
  AVG(dc.stress)::NUMERIC(3,1) AS avg_stress
FROM users u
LEFT JOIN sleep_entries se ON se.user_id = u.id
  AND se.date >= CURRENT_DATE - INTERVAL '7 days'
LEFT JOIN activity_sessions act ON act.user_id = u.id
  AND act.date >= CURRENT_DATE - INTERVAL '7 days'
LEFT JOIN nutrition_daily nd ON nd.user_id = u.id
  AND nd.date >= CURRENT_DATE - INTERVAL '7 days'
LEFT JOIN daily_checkins dc ON dc.user_id = u.id
  AND dc.date >= CURRENT_DATE - INTERVAL '7 days'
  AND dc.type = 'morning'
WHERE u.deleted_at IS NULL
GROUP BY u.id;
