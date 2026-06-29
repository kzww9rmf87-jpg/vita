/**
 * Nutrition Planner — routes meal-plan, shopping-list.
 *
 * Principe : VITA organise la semaine, jamais de jugement nutritionnel.
 * Aucun score. Aucun objectif imposé. Aucune recommandation.
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import { requestMealDistribution, requestSmartMealPlan } from '../ai-client.js'
import type { RecipeWithMacros, NutritionProfilePayload } from '../ai-client.js'

// ── Schémas ───────────────────────────────────────────────────────────────────

const MealPlanSchema = z.object({
  week_start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  weekStart:  z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  name:       z.string().max(200).optional(),
  notes:      z.string().max(1000).optional(),
}).refine(d => d.week_start != null || d.weekStart != null, {
  message: 'Required',
  path: ['week_start'],
})

const MealPlanItemSchema = z.object({
  day_of_week:  z.number().int().min(0).max(6),
  meal_slot:    z.enum(['lunch', 'dinner']),
  recipe_id:    z.string().uuid().optional(),
  recipe_name:  z.string().min(1).max(200),
  portions:     z.number().min(0.5).max(20).default(1),
  notes:        z.string().max(500).optional(),
  sort_order:   z.number().int().min(0).default(0),
})

const ShoppingItemPatchSchema = z.object({
  is_checked: z.boolean().optional(),
  isChecked:  z.boolean().optional(),
})

const DistributeSchema = z.object({
  recipe_ids: z.array(z.string().uuid()).min(1).optional(),
  recipeIds:  z.array(z.string().uuid()).min(1).optional(),
}).refine(d => d.recipe_ids != null || d.recipeIds != null, {
  message: 'Required',
  path: ['recipe_ids'],
})

// ── Catégorisation automatique des ingrédients ────────────────────────────────
// Heuristique par mots-clés français. Aucune IA — pure correspondance lexicale.

const CATEGORY_KEYWORDS: Record<string, string[]> = {
  produce:   ['légume', 'fruit', 'salade', 'tomate', 'oignon', 'carotte', 'courgette',
               'poivron', 'pomme', 'poire', 'fraise', 'citron', 'orange', 'banane',
               'aubergine', 'brocoli', 'épinard', 'champignon', 'avocat', 'concombre',
               'laitue', 'poireau', 'navet', 'radis', 'chou', 'artichaut', 'fenouil'],
  meat:      ['poulet', 'viande', 'bœuf', 'boeuf', 'porc', 'veau', 'agneau', 'jambon',
               'lardon', 'steak', 'canard', 'dinde', 'lapin', 'saucisse', 'merguez',
               'filet', 'escalope', 'côte', 'rôti', 'haché'],
  fish:      ['saumon', 'thon', 'cabillaud', 'crevette', 'morue', 'dorade', 'merlu',
               'sardine', 'maquereau', 'truite', 'bar', 'lieu', 'tilapia', 'sole',
               'homard', 'moule', 'huître', 'calmar', 'seiche', 'crabe'],
  dairy:     ['lait', 'fromage', 'yaourt', 'yogurt', 'beurre', 'crème', 'oeuf', 'œuf',
               'mozzarella', 'parmesan', 'ricotta', 'feta', 'emmental', 'gruyère',
               'camembert', 'brie', 'chèvre', 'mascarpone', 'comté', 'cheddar',
               'manchego', 'raclette', 'reblochon'],
  frozen:    ['surgelé', 'congelé'],
  beverages: ['eau', 'jus', 'vin', 'bière', 'café', 'thé', 'sirop', 'limonade',
               'sodas', 'soda', 'boisson'],
  spices:    ['sel', 'poivre', 'ail', 'épice', 'herbe', 'basilic', 'thym', 'romarin',
               'persil', 'coriandre', 'cumin', 'curry', 'paprika', 'cannelle',
               'muscade', 'laurier', 'origan', 'piment', 'safran', 'gingembre',
               'vanille', 'clou', 'anis', 'estragon', 'ciboulette', 'menthe'],
  pantry:    ['riz', 'pâtes', 'pasta', 'farine', 'huile', 'sucre', 'miel', 'sauce',
               'conserve', 'boîte', 'bocal', 'haricot', 'lentille', 'pois', 'vinaigre',
               'moutarde', 'ketchup', 'mayonnaise', 'pesto', 'pelé', 'coulis',
               'bouillon', 'cube', 'chapelure', 'biscotte', 'pain', 'céréale',
               'granola', 'flocon', 'avoine', 'quinoa', 'couscous', 'boulgour',
               'noix', 'amande', 'noisette', 'cacahuète', 'pistache', 'raisin sec'],
}

function categorize(name: string): string {
  const lower = name.toLowerCase()
  for (const [category, keywords] of Object.entries(CATEGORY_KEYWORDS)) {
    if (keywords.some(kw => lower.includes(kw))) return category
  }
  return 'other'
}

// ── Routes ────────────────────────────────────────────────────────────────────

export const mealPlanRoutes: FastifyPluginAsync = async (app) => {

  // ── Meal Plans ─────────────────────────────────────────────────────────────

  // POST / — Créer un plan pour une semaine
  app.post('/', async (req, reply) => {
    const parsed = MealPlanSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data
    const weekStart = body.week_start ?? body.weekStart!

    const row = await queryOne<{ id: string }>(
      `INSERT INTO meal_plans (user_id, week_start, name, notes)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, week_start) DO UPDATE SET
         name  = COALESCE(EXCLUDED.name, meal_plans.name),
         notes = COALESCE(EXCLUDED.notes, meal_plans.notes)
       RETURNING id`,
      [userId, weekStart, body.name ?? null, body.notes ?? null]
    )
    return reply.status(201).send({ id: row!.id })
  })

  // GET / — Liste des plans
  app.get('/', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const plans = await query(
      `SELECT id, week_start, name, notes, created_at
       FROM meal_plans
       WHERE user_id = $1
       ORDER BY week_start DESC
       LIMIT 52`,
      [userId]
    )
    return reply.send(plans)
  })

  // GET /:id — Détail d'un plan avec ses items
  app.get('/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const plan = await queryOne(
      `SELECT id, week_start, name, notes, created_at
       FROM meal_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    const items = await query(
      `SELECT mpi.id, mpi.day_of_week, mpi.meal_slot, mpi.recipe_id,
              mpi.recipe_name,
              mpi.portions::FLOAT     AS portions,
              mpi.notes, mpi.sort_order,
              r.calories,
              r.protein_g::FLOAT      AS protein_g,
              r.carbs_g::FLOAT        AS carbs_g,
              r.fat_g::FLOAT          AS fat_g,
              r.fiber_g::FLOAT        AS fiber_g
       FROM meal_plan_items mpi
       LEFT JOIN recipes r ON r.id = mpi.recipe_id
       WHERE mpi.meal_plan_id = $1
       ORDER BY mpi.day_of_week, mpi.meal_slot, mpi.sort_order`,
      [id]
    )
    return reply.send({ ...plan, items })
  })

  // DELETE /:id
  app.delete('/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const plan = await queryOne(
      `SELECT id FROM meal_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM meal_plans WHERE id = $1`, [id])
    return reply.status(204).send()
  })

  // ── Meal Plan Items ────────────────────────────────────────────────────────

  // POST /:id/items — Ajouter une recette au plan
  app.post('/:id/items', async (req, reply) => {
    const parsed = MealPlanItemSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const plan = await queryOne(
      `SELECT id FROM meal_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    const body = parsed.data
    const row = await queryOne<{ id: string }>(
      `INSERT INTO meal_plan_items
         (meal_plan_id, day_of_week, meal_slot, recipe_id, recipe_name,
          portions, notes, sort_order)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING id`,
      [
        id, body.day_of_week, body.meal_slot,
        body.recipe_id ?? null, body.recipe_name,
        body.portions, body.notes ?? null, body.sort_order,
      ]
    )
    return reply.status(201).send({ id: row!.id })
  })

  // PATCH /:id/items/:itemId — Déplacer ou modifier un item
  app.patch('/:id/items/:itemId', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id, itemId } = req.params as { id: string; itemId: string }

    const parsed = MealPlanItemSchema.partial().safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }

    const item = await queryOne(
      `SELECT mpi.id FROM meal_plan_items mpi
       JOIN meal_plans mp ON mp.id = mpi.meal_plan_id
       WHERE mpi.id = $1 AND mp.id = $2 AND mp.user_id = $3`,
      [itemId, id, userId]
    )
    if (!item) return reply.status(404).send({ error: 'NOT_FOUND' })

    const body = parsed.data
    const fields: string[] = []
    const values: unknown[] = [itemId]
    let idx = 2

    const addField = (col: string, val: unknown) => {
      if (val !== undefined) { fields.push(`${col} = $${idx++}`); values.push(val) }
    }

    addField('day_of_week',  body.day_of_week)
    addField('meal_slot',    body.meal_slot)
    addField('recipe_id',    body.recipe_id)
    addField('recipe_name',  body.recipe_name)
    addField('portions',     body.portions)
    addField('notes',        body.notes)
    addField('sort_order',   body.sort_order)

    if (fields.length === 0) return reply.status(400).send({ error: 'NO_FIELDS' })

    await query(
      `UPDATE meal_plan_items SET ${fields.join(', ')} WHERE id = $1`,
      values
    )
    return reply.status(200).send({ id: itemId })
  })

  // DELETE /:id/items/:itemId
  app.delete('/:id/items/:itemId', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id, itemId } = req.params as { id: string; itemId: string }

    const item = await queryOne(
      `SELECT mpi.id FROM meal_plan_items mpi
       JOIN meal_plans mp ON mp.id = mpi.meal_plan_id
       WHERE mpi.id = $1 AND mp.id = $2 AND mp.user_id = $3`,
      [itemId, id, userId]
    )
    if (!item) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM meal_plan_items WHERE id = $1`, [itemId])
    return reply.status(204).send()
  })

  // ── Distribution intelligente (AI Engine Sprint 9) ────────────────────────

  // POST /:id/distribute — L'agent planifie les recettes choisies sur la semaine
  // avec macros par créneau et profil nutritionnel optionnel.
  app.post('/:id/distribute', async (req, reply) => {
    const parsed = DistributeSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }
    const recipeIds = parsed.data.recipe_ids ?? parsed.data.recipeIds ?? []

    const plan = await queryOne(
      `SELECT id FROM meal_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    // Récupérer les recettes avec leurs macros
    const recipes = await query<RecipeWithMacros>(
      `SELECT id, name, servings, prep_minutes, cook_minutes,
              calories, protein_g, carbs_g, fat_g, fiber_g
       FROM recipes
       WHERE id = ANY($1) AND user_id = $2`,
      [recipeIds, userId]
    )
    if (recipes.length === 0) {
      return reply.status(400).send({ error: 'NO_RECIPES_FOUND' })
    }

    // Profil nutritionnel optionnel
    const profileRow = await queryOne<NutritionProfilePayload>(
      `SELECT objective, weight_kg, height_cm, age, sex,
              activity_level, meals_per_day, batch_cooking,
              cook_time_available, budget,
              allergies, intolerances, excluded_foods,
              target_calories, target_protein_g, target_carbs_g, target_fat_g, target_fiber_g
       FROM nutrition_profiles WHERE user_id = $1`,
      [userId]
    )

    // Garde-manger (pour exclure les ingrédients disponibles de la liste de courses)
    const pantryRows = await query<{ ingredient_name: string }>(
      `SELECT ingredient_name FROM pantry_items WHERE user_id = $1`,
      [userId]
    )
    const pantry = pantryRows.map(p => p.ingredient_name.toLowerCase().trim())

    // Appel AI Engine — agent intelligent Sprint 9
    let result
    try {
      result = await requestSmartMealPlan(userId, recipes, profileRow ?? null, pantry)
    } catch {
      return reply.status(503).send({ error: 'AI_ENGINE_UNAVAILABLE' })
    }

    // Supprimer les anciens items et insérer les nouveaux avec macros
    await query(`DELETE FROM meal_plan_items WHERE meal_plan_id = $1`, [id])

    for (const slot of result.slots) {
      await query(
        `INSERT INTO meal_plan_items
           (meal_plan_id, day_of_week, meal_slot, recipe_id, recipe_name, portions,
            calories, protein_g, carbs_g, fat_g, fiber_g)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [
          id, slot.day_of_week, slot.meal_slot, slot.recipe_id, slot.recipe_name, slot.portions,
          slot.calories ?? null, slot.protein_g ?? null,
          slot.carbs_g ?? null, slot.fat_g ?? null, slot.fiber_g ?? null,
        ]
      )
    }

    return reply.status(200).send({
      itemsCreated: result.slots.length,
      dayMacros:    result.day_macros,
      weekMacros:   result.week_macros,
      usedClaude:   result.used_claude,
    })
  })

  // ── Shopping List ──────────────────────────────────────────────────────────

  // POST /:id/shopping-list/generate — Générer depuis le plan courant
  app.post('/:id/shopping-list/generate', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const plan = await queryOne(
      `SELECT id FROM meal_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    // Récupérer tous les items du plan avec leurs ingrédients
    const items = await query<{
      recipe_id: string | null
      portions: number
      servings: number | null
    }>(
      `SELECT mpi.recipe_id, mpi.portions, r.servings
       FROM meal_plan_items mpi
       LEFT JOIN recipes r ON r.id = mpi.recipe_id
       WHERE mpi.meal_plan_id = $1 AND mpi.recipe_id IS NOT NULL`,
      [id]
    )

    // Pour chaque recette, récupérer les ingrédients et scaler par portions
    const ingredientMap = new Map<string, { quantity: number | null; unit: string | null }>()

    for (const item of items) {
      if (!item.recipe_id) continue
      const ratio = item.servings ? item.portions / item.servings : 1

      const ingredients = await query<{
        name: string; quantity_g: number | null
      }>(
        `SELECT name, quantity_g FROM recipe_ingredients WHERE recipe_id = $1 ORDER BY sort_order`,
        [item.recipe_id]
      )

      for (const ing of ingredients) {
        const key = ing.name.toLowerCase().trim()
        const existing = ingredientMap.get(key)
        const scaledQty = ing.quantity_g ? ing.quantity_g * ratio : null

        if (existing) {
          if (existing.quantity !== null && scaledQty !== null) {
            existing.quantity += scaledQty
          }
        } else {
          ingredientMap.set(key, {
            quantity: scaledQty,
            unit: scaledQty ? 'g' : null,
          })
        }
      }
    }

    // Récupérer les items du garde-manger de l'utilisateur
    const pantryItems = await query<{ ingredient_name: string }>(
      `SELECT ingredient_name FROM pantry_items WHERE user_id = $1`,
      [userId]
    )
    const pantryNames = new Set(pantryItems.map(p => p.ingredient_name.toLowerCase().trim()))

    // Supprimer la liste existante
    await query(`DELETE FROM shopping_list_items WHERE meal_plan_id = $1`, [id])

    // Insérer les nouveaux items (sauf garde-manger)
    let count = 0
    for (const [name, data] of ingredientMap.entries()) {
      if (pantryNames.has(name)) continue  // Filtré par le garde-manger

      const category = categorize(name)
      await query(
        `INSERT INTO shopping_list_items
           (meal_plan_id, ingredient_name, quantity, unit, category)
         VALUES ($1,$2,$3,$4,$5)`,
        [id, name, data.quantity, data.unit, category]
      )
      count++
    }

    return reply.status(200).send({ itemsGenerated: count })
  })

  // GET /:id/shopping-list — Récupérer la liste groupée par catégorie
  app.get('/:id/shopping-list', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const plan = await queryOne(
      `SELECT id FROM meal_plans WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!plan) return reply.status(404).send({ error: 'NOT_FOUND' })

    const items = await query(
      `SELECT id, ingredient_name,
              quantity::FLOAT AS quantity,
              unit, category, is_checked
       FROM shopping_list_items
       WHERE meal_plan_id = $1
       ORDER BY category, ingredient_name`,
      [id]
    )
    return reply.send(items)
  })

  // PATCH /:id/shopping-list/:itemId — Cocher/décocher un item
  app.patch('/:id/shopping-list/:itemId', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id, itemId } = req.params as { id: string; itemId: string }

    const parsed = ShoppingItemPatchSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }

    const item = await queryOne(
      `SELECT sli.id FROM shopping_list_items sli
       JOIN meal_plans mp ON mp.id = sli.meal_plan_id
       WHERE sli.id = $1 AND mp.id = $2 AND mp.user_id = $3`,
      [itemId, id, userId]
    )
    if (!item) return reply.status(404).send({ error: 'NOT_FOUND' })

    const isChecked = parsed.data.is_checked ?? parsed.data.isChecked
    if (isChecked !== undefined) {
      await query(
        `UPDATE shopping_list_items SET is_checked = $2 WHERE id = $1`,
        [itemId, isChecked]
      )
    }
    return reply.status(200).send({ id: itemId })
  })

  // DELETE /:id/shopping-list/:itemId
  app.delete('/:id/shopping-list/:itemId', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id, itemId } = req.params as { id: string; itemId: string }

    const item = await queryOne(
      `SELECT sli.id FROM shopping_list_items sli
       JOIN meal_plans mp ON mp.id = sli.meal_plan_id
       WHERE sli.id = $1 AND mp.id = $2 AND mp.user_id = $3`,
      [itemId, id, userId]
    )
    if (!item) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM shopping_list_items WHERE id = $1`, [itemId])
    return reply.status(204).send()
  })
}
