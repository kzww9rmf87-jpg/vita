/**
 * Stubs de contextes multimodaux — Sprint 12.1.
 *
 * Aucun OCR, aucune extraction image, aucune IA multimodale dans ce sprint.
 * Ces interfaces définissent le contrat que le futur pipeline devra respecter.
 * Importées dans ai-client.ts dès que le moteur adaptatif sera branché.
 */

export type UploadedContextType =
  | 'menu_photo'      // photo d'un menu de restaurant
  | 'dish_photo'      // photo d'un plat cuisiné
  | 'training_pdf'    // programme d'entraînement PDF
  | 'nutrition_pdf'   // bilan/programme alimentaire PDF
  | 'free_document'   // document libre

export interface UploadedContext {
  type:      UploadedContextType
  filename:  string
  raw_text?: string   // futur : texte extrait par OCR ou pipeline multimodal
}

export interface ParsedNutritionContext {
  meals?:           unknown[]
  total_calories?:  number
  protein_g?:       number
  source_filename?: string
}

export interface ParsedTrainingContext {
  sessions?:        unknown[]
  program_name?:    string
  weeks_duration?:  number
  source_filename?: string
}

// Contextes adaptatifs qui alimenteront le futur TrainingPlannerInput
export interface AdaptiveContexts {
  journal_context?:             Record<string, unknown>
  sleep_context?:               Record<string, unknown>
  nutrition_context?:           Record<string, unknown>
  meal_plan_context?:           Record<string, unknown>
  recovery_context?:            Record<string, unknown>
  uploaded_documents_context?:  UploadedContext[]
}
