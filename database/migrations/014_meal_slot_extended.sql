-- Sprint 9.3 — Étendre meal_slot pour supporter petit-déjeuner et collation
-- §1 : VITA ne prescrit pas le rythme alimentaire.
-- L'utilisateur choisit entre 2, 3 ou 4 repas par jour.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM   information_schema.table_constraints
    WHERE  table_name      = 'meal_plan_items'
    AND    constraint_name = 'meal_plan_items_meal_slot_check'
  ) THEN
    ALTER TABLE meal_plan_items
      DROP CONSTRAINT meal_plan_items_meal_slot_check;
  END IF;
END $$;

ALTER TABLE meal_plan_items
  ADD CONSTRAINT meal_plan_items_meal_slot_check
  CHECK (meal_slot IN ('breakfast', 'lunch', 'dinner', 'snack'));
