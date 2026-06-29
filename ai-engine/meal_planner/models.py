from __future__ import annotations
from typing import Literal, Optional
from pydantic import BaseModel, Field


class RecipeForPlan(BaseModel):
    id: str
    name: str
    servings: int = Field(ge=1)
    prep_minutes: Optional[int] = None
    cook_minutes: Optional[int] = None

    @property
    def total_minutes(self) -> int:
        return (self.prep_minutes or 0) + (self.cook_minutes or 0)


class MealPlanInput(BaseModel):
    user_id: str
    recipes: list[RecipeForPlan] = Field(min_length=1)


MealSlotLiteral = Literal["breakfast", "lunch", "dinner", "snack"]


class MealSlot(BaseModel):
    day_of_week: int = Field(ge=0, le=6)   # 0 = lundi, 6 = dimanche
    meal_slot: MealSlotLiteral


class MealDistribution(BaseModel):
    recipe_id: str
    recipe_name: str
    day_of_week: int = Field(ge=0, le=6)
    meal_slot: MealSlotLiteral
    portions: float = Field(gt=0, default=1.0)
