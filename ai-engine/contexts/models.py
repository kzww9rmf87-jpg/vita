"""
Modèles de contextes uploadés — stubs pour le futur moteur multimodal.

Aucun OCR, aucune extraction image, aucune IA multimodale dans ce sprint.
Ces types définissent uniquement le contrat que le futur pipeline devra respecter.
"""
from __future__ import annotations
from enum import Enum
from typing import Optional
from pydantic import BaseModel


class UploadedContextType(str, Enum):
    menu_photo      = "menu_photo"       # photo d'un menu de restaurant
    dish_photo      = "dish_photo"       # photo d'un plat cuisiné
    training_pdf    = "training_pdf"     # programme d'entraînement PDF
    nutrition_pdf   = "nutrition_pdf"    # bilan/programme alimentaire PDF
    free_document   = "free_document"    # document libre


class UploadedContext(BaseModel):
    type:     UploadedContextType
    filename: str
    # raw_text sera rempli par le futur pipeline OCR/multimodal
    raw_text: Optional[str] = None


class ParsedNutritionContext(BaseModel):
    """Résultat du futur pipeline de parsing nutritionnel."""
    meals:           Optional[list] = None   # liste de repas détectés
    total_calories:  Optional[float] = None
    protein_g:       Optional[float] = None
    source_filename: Optional[str]  = None


class ParsedTrainingContext(BaseModel):
    """Résultat du futur pipeline de parsing de programme d'entraînement."""
    sessions:       Optional[list] = None   # séances détectées dans le PDF
    program_name:   Optional[str]  = None
    weeks_duration: Optional[int]  = None
    source_filename: Optional[str] = None
