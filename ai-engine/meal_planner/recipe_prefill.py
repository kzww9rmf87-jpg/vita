"""
Génère une ébauche de recette à partir de son nom.
Toutes les valeurs nutritionnelles sont des estimations — jamais des valeurs certifiées.
"""
from __future__ import annotations
import json
import re
from typing import Optional
import anthropic
from pydantic import BaseModel

from config import get_settings

_client: Optional[anthropic.AsyncAnthropic] = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = anthropic.AsyncAnthropic(api_key=get_settings().anthropic_api_key)
    return _client


class PrefillIngredient(BaseModel):
    name: str
    quantity_g: Optional[float] = None
    sort_order: int = 0


class RecipePrefillResult(BaseModel):
    name: str
    servings: int
    prep_minutes: Optional[int] = None
    cook_minutes: Optional[int] = None
    notes: Optional[str] = None
    calories_per_serving: Optional[int] = None
    protein_g_per_serving: Optional[float] = None
    carbs_g_per_serving: Optional[float] = None
    fat_g_per_serving: Optional[float] = None
    fiber_g_per_serving: Optional[float] = None
    ingredients: list[PrefillIngredient] = []
    is_estimated: bool = True


_SYSTEM = (
    "Tu es un assistant culinaire. Quand on te donne un nom de recette tu fournis "
    "une ébauche structurée en JSON.\n"
    "Règles :\n"
    "- Les quantités d'ingrédients sont pour la recette entière (toutes portions).\n"
    "- Les macros sont PAR PORTION.\n"
    "- Toutes les valeurs nutritionnelles sont des estimations moyennes.\n"
    "- Pas de jugement alimentaire (ne dis jamais qu'une recette est \"trop\" quoi que ce soit).\n"
    "- Réponds UNIQUEMENT avec du JSON valide, sans texte avant ni après."
)


def _build_prompt(recipe_name: str, servings: int) -> str:
    return (
        f"Pré-remplis cette fiche recette :\n"
        f"Nom : {recipe_name}\n"
        f"Portions : {servings}\n\n"
        "Réponds avec ce JSON (toutes les valeurs numériques ou null) :\n"
        "{\n"
        '  "prep_minutes": <int ou null>,\n'
        '  "cook_minutes": <int ou null>,\n'
        '  "notes": <string court ou null>,\n'
        '  "calories_per_serving": <int ou null>,\n'
        '  "protein_g_per_serving": <float ou null>,\n'
        '  "carbs_g_per_serving": <float ou null>,\n'
        '  "fat_g_per_serving": <float ou null>,\n'
        '  "fiber_g_per_serving": <float ou null>,\n'
        '  "ingredients": [\n'
        '    {"name": "<nom>", "quantity_g": <float ou null>, "sort_order": <int>},\n'
        "    ...\n"
        "  ]\n"
        "}"
    )


def _parse_response(raw: str, recipe_name: str, servings: int) -> RecipePrefillResult:
    """Extrait le JSON de la réponse Claude (supporte les blocs markdown)."""
    text = raw.strip()
    match = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if match:
        text = match.group(1).strip()

    data = json.loads(text)  # lève json.JSONDecodeError si invalide

    ingredients = [
        PrefillIngredient(
            name=str(ing["name"]),
            quantity_g=ing.get("quantity_g"),
            sort_order=i,
        )
        for i, ing in enumerate(data.get("ingredients", []))
        if ing.get("name")
    ]

    return RecipePrefillResult(
        name=recipe_name,
        servings=servings,
        prep_minutes=data.get("prep_minutes"),
        cook_minutes=data.get("cook_minutes"),
        notes=data.get("notes"),
        calories_per_serving=data.get("calories_per_serving"),
        protein_g_per_serving=data.get("protein_g_per_serving"),
        carbs_g_per_serving=data.get("carbs_g_per_serving"),
        fat_g_per_serving=data.get("fat_g_per_serving"),
        fiber_g_per_serving=data.get("fiber_g_per_serving"),
        ingredients=ingredients,
        is_estimated=True,
    )


async def prefill_recipe(recipe_name: str, servings: int = 4) -> RecipePrefillResult:
    """
    Génère une ébauche de recette via Claude (model_fast).
    Retourne toujours is_estimated=True — les valeurs sont indicatives.
    """
    message = await _get_client().messages.create(
        model=get_settings().model_fast,
        max_tokens=1024,
        system=_SYSTEM,
        messages=[{"role": "user", "content": _build_prompt(recipe_name, servings)}],
    )

    raw = message.content[0].text
    return _parse_response(raw, recipe_name, servings)
