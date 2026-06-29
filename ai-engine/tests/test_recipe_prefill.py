"""Tests unitaires pour meal_planner/recipe_prefill.py."""
import json
import pytest
from unittest import mock

from meal_planner.recipe_prefill import (
    _build_prompt,
    _parse_response,
    RecipePrefillResult,
    PrefillIngredient,
    prefill_recipe,
)

# ── _build_prompt ──────────────────────────────────────────────────────────────

def test_build_prompt_contient_nom():
    prompt = _build_prompt("Lasagnes bolognaise", 6)
    assert "Lasagnes bolognaise" in prompt

def test_build_prompt_contient_portions():
    prompt = _build_prompt("Quiche lorraine", 4)
    assert "4" in prompt

def test_build_prompt_contient_champs_macros():
    prompt = _build_prompt("Poulet rôti", 4)
    for field in ("calories_per_serving", "protein_g_per_serving", "carbs_g_per_serving",
                  "fat_g_per_serving", "fiber_g_per_serving"):
        assert field in prompt

def test_build_prompt_contient_champs_ingredients():
    prompt = _build_prompt("Soupe", 2)
    assert "ingredients" in prompt

# ── _parse_response ────────────────────────────────────────────────────────────

_VALID_JSON = {
    "prep_minutes": 20,
    "cook_minutes": 45,
    "notes": "Recette familiale.",
    "calories_per_serving": 480,
    "protein_g_per_serving": 28.0,
    "carbs_g_per_serving": 42.0,
    "fat_g_per_serving": 22.0,
    "fiber_g_per_serving": 3.5,
    "ingredients": [
        {"name": "Pâtes à lasagnes", "quantity_g": 300, "sort_order": 0},
        {"name": "Bœuf haché",       "quantity_g": 500, "sort_order": 1},
        {"name": "Sauce tomate",     "quantity_g": 400, "sort_order": 2},
        {"name": "Béchamel",         "quantity_g": 300, "sort_order": 3},
    ],
}

def test_parse_response_happy_path():
    raw = json.dumps(_VALID_JSON)
    result = _parse_response(raw, "Lasagnes bolognaise", 6)
    assert isinstance(result, RecipePrefillResult)
    assert result.name == "Lasagnes bolognaise"
    assert result.servings == 6
    assert result.is_estimated is True
    assert result.calories_per_serving == 480
    assert result.prep_minutes == 20
    assert len(result.ingredients) == 4

def test_parse_response_ingredients_mappes():
    raw = json.dumps(_VALID_JSON)
    result = _parse_response(raw, "Lasagnes bolognaise", 6)
    names = [i.name for i in result.ingredients]
    assert "Bœuf haché" in names

def test_parse_response_sort_order_preservé():
    raw = json.dumps(_VALID_JSON)
    result = _parse_response(raw, "Lasagnes bolognaise", 6)
    # sort_order recalculé par position d'énumération (0,1,2,3)
    assert result.ingredients[0].sort_order == 0
    assert result.ingredients[3].sort_order == 3

def test_parse_response_markdown_code_block():
    raw = "```json\n" + json.dumps(_VALID_JSON) + "\n```"
    result = _parse_response(raw, "Test", 4)
    assert result.calories_per_serving == 480

def test_parse_response_markdown_sans_lang():
    raw = "```\n" + json.dumps(_VALID_JSON) + "\n```"
    result = _parse_response(raw, "Test", 4)
    assert result.name == "Test"

def test_parse_response_valeurs_nulles():
    data = {**_VALID_JSON, "calories_per_serving": None, "fiber_g_per_serving": None}
    result = _parse_response(json.dumps(data), "Test", 4)
    assert result.calories_per_serving is None
    assert result.fiber_g_per_serving is None

def test_parse_response_ingredients_vides():
    data = {**_VALID_JSON, "ingredients": []}
    result = _parse_response(json.dumps(data), "Test", 4)
    assert result.ingredients == []

def test_parse_response_ingredient_sans_quantite():
    data = {**_VALID_JSON, "ingredients": [
        {"name": "Sel", "quantity_g": None, "sort_order": 0},
    ]}
    result = _parse_response(json.dumps(data), "Test", 4)
    assert result.ingredients[0].quantity_g is None

def test_parse_response_ingredient_sans_nom_ignore():
    data = {**_VALID_JSON, "ingredients": [
        {"name": "",    "quantity_g": 100, "sort_order": 0},
        {"name": "Sel", "quantity_g": 5,   "sort_order": 1},
    ]}
    result = _parse_response(json.dumps(data), "Test", 4)
    assert len(result.ingredients) == 1
    assert result.ingredients[0].name == "Sel"

def test_parse_response_json_invalide_leve_exception():
    with pytest.raises(json.JSONDecodeError):
        _parse_response("pas du JSON", "Test", 4)

def test_parse_response_is_estimated_toujours_true():
    result = _parse_response(json.dumps(_VALID_JSON), "Test", 4)
    assert result.is_estimated is True

# ── prefill_recipe ─────────────────────────────────────────────────────────────

def _make_mock_message(content: str):
    msg = mock.MagicMock()
    msg.content = [mock.MagicMock()]
    msg.content[0].text = content
    return msg


@pytest.mark.asyncio
async def test_prefill_recipe_appelle_claude():
    with mock.patch("meal_planner.recipe_prefill._get_client") as mock_get_client:
        client = mock.AsyncMock()
        mock_get_client.return_value = client
        client.messages.create = mock.AsyncMock(
            return_value=_make_mock_message(json.dumps(_VALID_JSON))
        )
        result = await prefill_recipe("Lasagnes bolognaise", 6)
        assert result.name == "Lasagnes bolognaise"
        assert result.servings == 6
        client.messages.create.assert_called_once()


@pytest.mark.asyncio
async def test_prefill_recipe_passe_model_fast():
    with mock.patch("meal_planner.recipe_prefill._get_client") as mock_get_client, \
         mock.patch("meal_planner.recipe_prefill.get_settings") as mock_settings:
        settings = mock.MagicMock()
        settings.model_fast = "claude-haiku-test"
        settings.anthropic_api_key = "test-key"
        mock_settings.return_value = settings

        client = mock.AsyncMock()
        mock_get_client.return_value = client
        client.messages.create = mock.AsyncMock(
            return_value=_make_mock_message(json.dumps(_VALID_JSON))
        )
        await prefill_recipe("Test", 4)
        call_kwargs = client.messages.create.call_args.kwargs
        assert call_kwargs["model"] == "claude-haiku-test"


@pytest.mark.asyncio
async def test_prefill_recipe_max_tokens_suffisant():
    with mock.patch("meal_planner.recipe_prefill._get_client") as mock_get_client:
        client = mock.AsyncMock()
        mock_get_client.return_value = client
        client.messages.create = mock.AsyncMock(
            return_value=_make_mock_message(json.dumps(_VALID_JSON))
        )
        await prefill_recipe("Test", 4)
        call_kwargs = client.messages.create.call_args.kwargs
        assert call_kwargs["max_tokens"] >= 512


@pytest.mark.asyncio
async def test_prefill_recipe_is_estimated_true():
    with mock.patch("meal_planner.recipe_prefill._get_client") as mock_get_client:
        client = mock.AsyncMock()
        mock_get_client.return_value = client
        client.messages.create = mock.AsyncMock(
            return_value=_make_mock_message(json.dumps(_VALID_JSON))
        )
        result = await prefill_recipe("Test", 4)
        assert result.is_estimated is True


@pytest.mark.asyncio
async def test_prefill_recipe_propage_exception_claude():
    with mock.patch("meal_planner.recipe_prefill._get_client") as mock_get_client:
        client = mock.AsyncMock()
        mock_get_client.return_value = client
        client.messages.create = mock.AsyncMock(side_effect=Exception("API error"))
        with pytest.raises(Exception, match="API error"):
            await prefill_recipe("Test", 4)


@pytest.mark.asyncio
async def test_prefill_recipe_propage_json_invalide():
    with mock.patch("meal_planner.recipe_prefill._get_client") as mock_get_client:
        client = mock.AsyncMock()
        mock_get_client.return_value = client
        client.messages.create = mock.AsyncMock(
            return_value=_make_mock_message("Désolé, je ne peux pas traiter ça.")
        )
        with pytest.raises(json.JSONDecodeError):
            await prefill_recipe("Test", 4)
