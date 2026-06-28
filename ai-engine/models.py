from pydantic import BaseModel, Field
from typing import Optional, Literal
from datetime import date, datetime


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


class OrchestratorState(BaseModel):
    user_context: UserContext
    sport_signal: Optional[AgentSignal] = None
    nutrition_signal: Optional[AgentSignal] = None
    sleep_signal: Optional[AgentSignal] = None
    mental_signal: Optional[AgentSignal] = None
    health_signal: Optional[AgentSignal] = None
    final_recommendation: Optional[Recommendation] = None
    error: Optional[str] = None
