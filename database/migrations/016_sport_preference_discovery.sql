-- Migration 016 — Sport Preference Discovery
-- Sprint 12.2 : enrichissement du profil sportif pour la découverte de préférences
--
-- Nouveaux champs sur sport_profiles :
--   motivation           — objectif de départ déclaré
--   attractive_activities — activités qui semblent attirantes (depuis la découverte VITA)
--   rejected_activities   — activités à ne jamais proposer
--   preferred_context     — contexte préféré (seul, groupe, dehors, maison, salle)
--   apprehension_level    — niveau d'appréhension face à l'activité physique
--   realistic_time_min    — temps réaliste disponible par séance (minutes)

BEGIN;

ALTER TABLE sport_profiles
    ADD COLUMN IF NOT EXISTS motivation            TEXT
        CHECK (motivation IN (
            'bouger_un_peu', 'reprendre_confiance', 'ameliorer_energie',
            'perdre_poids', 'preparer_sport'
        )),
    ADD COLUMN IF NOT EXISTS attractive_activities TEXT[]   NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS rejected_activities   TEXT[]   NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS preferred_context     TEXT[]   NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS apprehension_level    TEXT     NOT NULL DEFAULT 'aucune'
        CHECK (apprehension_level IN ('aucune', 'legere', 'moderee', 'elevee')),
    ADD COLUMN IF NOT EXISTS realistic_time_min    SMALLINT
        CHECK (realistic_time_min BETWEEN 10 AND 120);

COMMIT;
