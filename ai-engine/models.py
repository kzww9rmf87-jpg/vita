from pydantic import BaseModel, Field
from typing import Optional, Literal
from datetime import date, datetime
from enum import Enum


class AgentSignal(BaseModel):
    agent: str
    signal_type: str
    description: str
    confidence: float = Field(ge=0, le=1)
    urgency: float = Field(ge=0, le=1, default=0.5)
    impact: float = Field(ge=0, le=1, default=0.5)
    data: dict = Field(default_factory=dict)


class Recommendation(BaseModel):
    content: str
    content_short: Optional[str] = None
    action_type: Literal["do", "adjust", "avoid", "rest", "celebrate"]
    agent_source: str
    reasoning: dict = Field(default_factory=dict)
    confidence: float
    actions: list[str] = Field(default_factory=list)


class UserContext(BaseModel):
    user_id: str
    date: date
    sleep: Optional[dict] = None
    activity_week: Optional[list[dict]] = None
    nutrition_week: Optional[list[dict]] = None
    checkin_morning: Optional[dict] = None
    checkin_evening: Optional[dict] = None
    patterns: list[dict] = Field(default_factory=list)
    profile: Optional[dict] = None
    snapshot: Optional[dict] = None
    conversation_history: list[dict] = Field(default_factory=list)


class FitnessLevel(str, Enum):
    beginner = "beginner"
    intermediate = "intermediate"
    advanced = "advanced"
    elite = "elite"


class SportProfile(BaseModel):
    id: str
    user_id: str
    fitness_level: FitnessLevel
    preferred_activities: list[str]
    sessions_per_week: int = Field(ge=1, le=14)
    session_duration_min: int = Field(ge=10, le=300)
    available_days: list[int]  # 0=dim … 6=sam
    context: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class TrainingPlanSession(BaseModel):
    id: str
    plan_id: str
    day_of_week: int = Field(ge=0, le=6)
    activity_name: str
    duration_min: int = Field(ge=5, le=300)
    notes: Optional[str] = None
    sort_order: int = 0


class TrainingPlan(BaseModel):
    id: str
    user_id: str
    name: str
    description: Optional[str] = None
    is_active: bool
    sessions: list[TrainingPlanSession] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class OrchestratorState(BaseModel):
    user_context: UserContext
    sport_signal: Optional[AgentSignal] = None
    nutrition_signal: Optional[AgentSignal] = None
    sleep_signal: Optional[AgentSignal] = None
    mental_signal: Optional[AgentSignal] = None
    health_signal: Optional[AgentSignal] = None
    final_recommendation: Optional[Recommendation] = None
    error: Optional[str] = None
