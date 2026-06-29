/**
 * Nutrition — routes data-service.
 *
 * Trois niveaux :
 *   nutrition_daily  — totaux journaliers agrégés
 *   meals            — repas individuels dans la journée
 *   food_items       — catalogue d'aliments (recherche + création)
 *   recipes          — recettes utilisateur
 *
 * FONDATION seulement — aucun calcul de score, aucune analyse.
 * Auth : JWT obligatoire.
 */
import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { query, queryOne } from '../db.js'
import { requestRecipePrefill, AIEngineError } from '../ai-client.js'

// ── Schémas ───────────────────────────────────────────────────────────────────

const NutritionDailySchema = z.object({
  date:        z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  calories:    z.number().int().min(0).max(10000).optional(),
  proteinG:    z.number().min(0).max(1000).optional(),
  carbsG:      z.number().min(0).max(2000).optional(),
  fatG:        z.number().min(0).max(1000).optional(),
  fiberG:      z.number().min(0).max(200).optional(),
  waterMl:     z.number().int().min(0).max(10000).optional(),
  alcoholG:    z.number().min(0).max(500).optional(),
  caffeineMg:  z.number().int().min(0).max(3000).optional(),
  sodiumMg:    z.number().int().min(0).max(20000).optional(),
  supplements: z.array(z.string().max(100)).max(20).optional(),
  notes:       z.string().max(1000).optional(),
})

const MealSchema = z.object({
  date:         z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  eatenAt:      z.string().datetime().optional(),
  mealType:     z.enum(['breakfast', 'lunch', 'dinner', 'snack']).optional(),
  description:  z.string().min(1).max(500),
  calories:     z.number().int().min(0).max(5000).optional(),
  proteinG:     z.number().min(0).max(500).optional(),
  carbsG:       z.number().min(0).max(1000).optional(),
  fatG:         z.number().min(0).max(500).optional(),
  isRestaurant: z.boolean().optional(),
  notes:        z.string().max(500).optional(),
})

const FoodItemSchema = z.object({
  name:             z.string().min(1).max(200),
  brand:            z.string().max(200).optional(),
  caloriesPer100g:  z.number().int().min(0).max(1000).optional(),
  proteinPer100g:   z.number().min(0).max(100).optional(),
  carbsPer100g:     z.number().min(0).max(100).optional(),
  fatPer100g:       z.number().min(0).max(100).optional(),
  fiberPer100g:     z.number().min(0).max(100).optional(),
  micronutrients:   z.record(z.number()).optional(),
  barcode:          z.string().max(50).optional(),
})

const RecipeSchema = z.object({
  name:         z.string().min(1).max(200),
  description:  z.string().max(1000).optional(),
  servings:     z.number().int().min(1).max(100).default(1),
  prepMinutes:  z.number().int().min(0).max(480).optional(),
  cookMinutes:  z.number().int().min(0).max(480).optional(),
  notes:        z.string().max(1000).optional(),
  // Macros directes par portion (orientation planification — pas un score nutritionnel)
  calories:     z.number().int().min(0).max(5000).optional(),
  proteinG:     z.number().min(0).max(500).optional(),
  carbsG:       z.number().min(0).max(1000).optional(),
  fatG:         z.number().min(0).max(500).optional(),
  fiberG:       z.number().min(0).max(200).optional(),
  ingredients:  z.array(z.object({
    name:        z.string().min(1).max(200),
    quantityG:   z.number().min(0).max(10000).optional(),
    foodItemId:  z.string().uuid().optional(),
    sortOrder:   z.number().int().min(0).default(0),
  })).max(50).optional(),
})

// ── Routes ────────────────────────────────────────────────────────────────────

export const nutritionRoutes: FastifyPluginAsync = async (app) => {

  // ── nutrition_daily ──────────────────────────────────────────────────────

  app.post('/', async (req, reply) => {
    const parsed = NutritionDailySchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    await query(
      `INSERT INTO nutrition_daily
         (user_id, date, calories, protein_g, carbs_g, fat_g, fiber_g,
          water_ml, alcohol_g, caffeine_mg, sodium_mg, supplements, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       ON CONFLICT (user_id, date) DO UPDATE SET
         calories    = EXCLUDED.calories,
         protein_g   = EXCLUDED.protein_g,
         carbs_g     = EXCLUDED.carbs_g,
         fat_g       = EXCLUDED.fat_g,
         fiber_g     = EXCLUDED.fiber_g,
         water_ml    = EXCLUDED.water_ml,
         alcohol_g   = EXCLUDED.alcohol_g,
         caffeine_mg = EXCLUDED.caffeine_mg,
         sodium_mg   = EXCLUDED.sodium_mg,
         supplements = EXCLUDED.supplements,
         notes       = EXCLUDED.notes`,
      [
        userId, body.date,
        body.calories ?? null, body.proteinG ?? null,
        body.carbsG ?? null, body.fatG ?? null,
        body.fiberG ?? null, body.waterMl ?? null,
        body.alcoholG ?? null, body.caffeineMg ?? null,
        body.sodiumMg ?? null, body.supplements ?? [],
        body.notes ?? null,
      ]
    )
    return reply.status(201).send({ date: body.date })
  })

  app.get('/history', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { days = '30' } = req.query as { days?: string }
    const daysInt = Math.min(365, Math.max(1, parseInt(days) || 30))

    const entries = await query(
      `SELECT date, calories, protein_g, carbs_g, fat_g, fiber_g,
              water_ml, alcohol_g, caffeine_mg, supplements, notes
       FROM nutrition_daily
       WHERE user_id = $1 AND date >= CURRENT_DATE - $2::INT
       ORDER BY date DESC`,
      [userId, daysInt]
    )
    return reply.send(entries)
  })

  app.delete('/daily/:date', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { date } = req.params as { date: string }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return reply.status(400).send({ error: 'INVALID_DATE' })
    }

    await query(
      `DELETE FROM nutrition_daily WHERE user_id = $1 AND date = $2`,
      [userId, date]
    )
    return reply.status(204).send()
  })

  // ── meals ────────────────────────────────────────────────────────────────

  app.post('/meals', async (req, reply) => {
    const parsed = MealSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    const row = await queryOne<{ id: string }>(
      `INSERT INTO meals
         (user_id, date, eaten_at, meal_type, description,
          calories, protein_g, carbs_g, fat_g, is_restaurant, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       RETURNING id`,
      [
        userId, body.date,
        body.eatenAt ?? null, body.mealType ?? null,
        body.description,
        body.calories ?? null, body.proteinG ?? null,
        body.carbsG ?? null, body.fatG ?? null,
        body.isRestaurant ?? false, body.notes ?? null,
      ]
    )
    return reply.status(201).send({ id: row!.id })
  })

  app.get('/meals', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { date } = req.query as { date?: string }

    const meals = await query(
      `SELECT id, date, eaten_at, meal_type, description,
              calories, protein_g, carbs_g, fat_g, is_restaurant, notes, created_at
       FROM meals
       WHERE user_id = $1
         AND ($2::DATE IS NULL OR date = $2::DATE)
       ORDER BY eaten_at ASC NULLS LAST, created_at ASC`,
      [userId, date ?? null]
    )
    return reply.send(meals)
  })

  app.delete('/meals/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const meal = await queryOne(
      `SELECT id FROM meals WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!meal) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM meals WHERE id = $1`, [id])
    return reply.status(204).send()
  })

  // ── food_items ───────────────────────────────────────────────────────────

  app.get('/food-items', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { q } = req.query as { q?: string }

    const items = await query(
      `SELECT id, name, brand, calories_per_100g, protein_per_100g,
              carbs_per_100g, fat_per_100g, fiber_per_100g, source, barcode
       FROM food_items
       WHERE (user_id = $1 OR user_id IS NULL)
         AND ($2::TEXT IS NULL OR LOWER(name) LIKE '%' || LOWER($2) || '%')
       ORDER BY source DESC, LOWER(name) ASC
       LIMIT 50`,
      [userId, q ?? null]
    )
    return reply.send(items)
  })

  app.post('/food-items', async (req, reply) => {
    const parsed = FoodItemSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    const row = await queryOne<{ id: string }>(
      `INSERT INTO food_items
         (user_id, name, brand, calories_per_100g, protein_per_100g,
          carbs_per_100g, fat_per_100g, fiber_per_100g,
          micronutrients, source, barcode)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'user',$10)
       RETURNING id`,
      [
        userId, body.name, body.brand ?? null,
        body.caloriesPer100g ?? null, body.proteinPer100g ?? null,
        body.carbsPer100g ?? null, body.fatPer100g ?? null,
        body.fiberPer100g ?? null,
        JSON.stringify(body.micronutrients ?? {}),
        body.barcode ?? null,
      ]
    )
    return reply.status(201).send({ id: row!.id })
  })

  app.delete('/food-items/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const item = await queryOne(
      `SELECT id FROM food_items WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!item) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM food_items WHERE id = $1`, [id])
    return reply.status(204).send()
  })

  // ── recipes ──────────────────────────────────────────────────────────────

  app.post('/recipes', async (req, reply) => {
    const parsed = RecipeSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const userId = (req.user as { sub: string }).sub
    const body = parsed.data

    // Calculer les totaux nutritionnels depuis les ingrédients connus
    let totalCalories = 0
    let totalProtein = 0
    let totalCarbs = 0
    let totalFat = 0
    let totalFiber = 0
    let hasNutritionData = false

    if (body.ingredients && body.ingredients.length > 0) {
      const foodItemIds = body.ingredients
        .filter(i => i.foodItemId)
        .map(i => i.foodItemId!)

      if (foodItemIds.length > 0) {
        const foodItems = await query<{
          id: string
          calories_per_100g: number | null
          protein_per_100g: number | null
          carbs_per_100g: number | null
          fat_per_100g: number | null
          fiber_per_100g: number | null
        }>(
          `SELECT id, calories_per_100g, protein_per_100g, carbs_per_100g,
                  fat_per_100g, fiber_per_100g
           FROM food_items WHERE id = ANY($1)`,
          [foodItemIds]
        )
        const foodMap = new Map(foodItems.map(f => [f.id, f]))

        for (const ing of body.ingredients) {
          if (!ing.foodItemId || !ing.quantityG) continue
          const fi = foodMap.get(ing.foodItemId)
          if (!fi) continue
          const ratio = ing.quantityG / 100
          if (fi.calories_per_100g != null) { totalCalories += fi.calories_per_100g * ratio; hasNutritionData = true }
          if (fi.protein_per_100g  != null) totalProtein += fi.protein_per_100g  * ratio
          if (fi.carbs_per_100g    != null) totalCarbs   += fi.carbs_per_100g    * ratio
          if (fi.fat_per_100g      != null) totalFat     += fi.fat_per_100g      * ratio
          if (fi.fiber_per_100g    != null) totalFiber   += fi.fiber_per_100g    * ratio
        }
      }
    }

    const servings = body.servings
    // Macros directes > calculées depuis les ingrédients
    const directMacros = body.calories != null || body.proteinG != null ||
                         body.carbsG   != null || body.fatG     != null
    const finalCalories = directMacros
      ? (body.calories ?? null)
      : (hasNutritionData ? Math.round(totalCalories / servings) : null)
    const finalProtein  = directMacros
      ? (body.proteinG ?? null)
      : (hasNutritionData ? Math.round(totalProtein / servings * 10) / 10 : null)
    const finalCarbs    = directMacros
      ? (body.carbsG ?? null)
      : (hasNutritionData ? Math.round(totalCarbs / servings * 10) / 10 : null)
    const finalFat      = directMacros
      ? (body.fatG ?? null)
      : (hasNutritionData ? Math.round(totalFat / servings * 10) / 10 : null)
    const finalFiber    = body.fiberG ?? (hasNutritionData ? Math.round(totalFiber / servings * 10) / 10 : null)

    const row = await queryOne<{ id: string }>(
      `INSERT INTO recipes
         (user_id, name, description, servings,
          calories, protein_g, carbs_g, fat_g, fiber_g,
          prep_minutes, cook_minutes, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       RETURNING id`,
      [
        userId, body.name, body.description ?? null, servings,
        finalCalories, finalProtein, finalCarbs, finalFat, finalFiber,
        body.prepMinutes ?? null, body.cookMinutes ?? null,
        body.notes ?? null,
      ]
    )
    const recipeId = row!.id

    if (body.ingredients && body.ingredients.length > 0) {
      for (const ing of body.ingredients) {
        await query(
          `INSERT INTO recipe_ingredients
             (recipe_id, food_item_id, name, quantity_g, sort_order)
           VALUES ($1,$2,$3,$4,$5)`,
          [recipeId, ing.foodItemId ?? null, ing.name, ing.quantityG, ing.sortOrder]
        )
      }
    }

    return reply.status(201).send({ id: recipeId })
  })

  app.get('/recipes', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub

    const recipes = await query(
      `SELECT id, name, description, servings, calories, protein_g, carbs_g,
              fat_g, fiber_g, prep_minutes, cook_minutes, created_at
       FROM recipes
       WHERE user_id = $1
       ORDER BY created_at DESC`,
      [userId]
    )
    return reply.send(recipes)
  })

  app.get('/recipes/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const recipe = await queryOne(
      `SELECT id, name, description, servings, calories, protein_g, carbs_g,
              fat_g, fiber_g, prep_minutes, cook_minutes, notes, created_at
       FROM recipes WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!recipe) return reply.status(404).send({ error: 'NOT_FOUND' })

    const ingredients = await query(
      `SELECT ri.id, ri.name, ri.quantity_g, ri.sort_order,
              fi.id AS food_item_id, fi.calories_per_100g, fi.protein_per_100g
       FROM recipe_ingredients ri
       LEFT JOIN food_items fi ON fi.id = ri.food_item_id
       WHERE ri.recipe_id = $1
       ORDER BY ri.sort_order, ri.created_at`,
      [id]
    )
    return reply.send({ ...recipe, ingredients })
  })

  // ── Prefill IA ─────────────────────────────────────────────────────────────

  const RecipePrefillSchema = z.object({
    recipeName: z.string().min(1).max(200),
    servings:   z.number().int().min(1).max(20).optional(),
  })

  app.post('/recipes/prefill', async (req, reply) => {
    const parsed = RecipePrefillSchema.safeParse(req.body)
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', details: parsed.error.flatten() })
    }
    const { recipeName, servings } = parsed.data

    try {
      const result = await requestRecipePrefill(recipeName, servings)
      return reply.send(result)
    } catch (err) {
      if (err instanceof AIEngineError) {
        const status = err.status >= 500 ? 503 : err.status
        return reply.status(status).send({ error: 'AI_ENGINE_UNAVAILABLE', message: err.message })
      }
      return reply.status(503).send({ error: 'AI_ENGINE_UNAVAILABLE' })
    }
  })

  app.delete('/recipes/:id', async (req, reply) => {
    const userId = (req.user as { sub: string }).sub
    const { id } = req.params as { id: string }

    const recipe = await queryOne(
      `SELECT id FROM recipes WHERE id = $1 AND user_id = $2`,
      [id, userId]
    )
    if (!recipe) return reply.status(404).send({ error: 'NOT_FOUND' })

    await query(`DELETE FROM recipes WHERE id = $1`, [id])
    return reply.status(204).send()
  })
}
