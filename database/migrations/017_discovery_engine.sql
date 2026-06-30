-- Migration 017 — Discovery Engine (Sprint 12.3)
--
-- Tables génériques pour le moteur de découverte conversationnel.
-- Le domaine 'sport' est le premier à l'utiliser.
-- L'architecture est conçue pour accueillir : nutrition, sommeil, mental, etc.
--
-- discovery_sessions  : une session par utilisateur × domaine (actif ou complété)
-- sport_identity      : résultat de la découverte sport (profil riche non-formulaire)

BEGIN;

-- ── Sessions de découverte conversationnelle ───────────────────────────────────

CREATE TABLE IF NOT EXISTS discovery_sessions (
    id         UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    domain     TEXT    NOT NULL
        CHECK (domain IN ('sport')),
    status     TEXT    NOT NULL DEFAULT 'discovering'
        CHECK (status IN ('discovering', 'reformulating', 'proposing', 'completed')),

    -- Historique des échanges (VITA + utilisateur)
    exchanges  JSONB   NOT NULL DEFAULT '[]',

    -- Synthèse générée lors de la reformulation
    synthesis  JSONB,

    -- Propositions d'activités
    proposals  JSONB,

    -- Activités acceptées/refusées par l'utilisateur
    accepted_activities JSONB NOT NULL DEFAULT '[]',
    refused_activities  JSONB NOT NULL DEFAULT '[]',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un seul entretien actif par utilisateur × domaine
CREATE UNIQUE INDEX IF NOT EXISTS discovery_sessions_active_unique
    ON discovery_sessions (user_id, domain)
    WHERE status != 'completed';

-- ── Identité sportive ──────────────────────────────────────────────────────────
-- Résultat de la découverte sport. Remplace (et enrichit) les champs formulaire.
-- Un enregistrement par utilisateur, mis à jour à chaque nouvelle découverte.

CREATE TABLE IF NOT EXISTS sport_identity (
    id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- Représentation narrative
    rapport_au_sport        TEXT,          -- relation globale à l'activité physique
    motivations             JSONB NOT NULL DEFAULT '[]',    -- motivations profondes
    freins                  JSONB NOT NULL DEFAULT '[]',    -- obstacles déclarés
    experiences_positives   JSONB NOT NULL DEFAULT '[]',   -- ce qui a fonctionné
    experiences_negatives   JSONB NOT NULL DEFAULT '[]',   -- ce qui a échoué
    personnalite            TEXT,          -- profil de personnalité sportive perçu
    contexte_prefere        JSONB NOT NULL DEFAULT '[]',   -- seul/groupe/dehors/salle/…
    contraintes             JSONB NOT NULL DEFAULT '[]',   -- temps, argent, mobilité, …
    activites_recommandees  JSONB NOT NULL DEFAULT '[]',   -- proposées et acceptées
    activites_refusees      JSONB NOT NULL DEFAULT '[]',   -- refusées explicitement
    resume_valide           TEXT,          -- synthèse validée par l'utilisateur

    -- Lien vers la session d'origine
    discovery_session_id    UUID REFERENCES discovery_sessions(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
