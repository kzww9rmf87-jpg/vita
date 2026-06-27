-- Suppression des tables de gamification.
--
-- Ces tables violent l'Article 7 de FOUNDING_PRINCIPLES.md :
-- "VITA ne gamifie jamais la santé. Pas de streaks, pas de badges,
-- pas de points, pas de niveaux, pas de comparaisons."
--
-- La gamification transforme un comportement de soin en obligation
-- et crée une relation de dépendance plutôt que de compréhension.
-- Ces tables n'ont pas leur place dans VITA, même désactivées.

BEGIN;

DROP TABLE IF EXISTS user_achievements CASCADE;
DROP TABLE IF EXISTS user_streaks CASCADE;
DROP TABLE IF EXISTS user_xp CASCADE;

COMMIT;
