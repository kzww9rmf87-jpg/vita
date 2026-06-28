"""
API FastAPI pour le moteur IA VITA.
Exposée sur le port 3003, consommée par le data-service via HTTP interne.
"""
from contextlib import asynccontextmanager
from datetime import date
from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel
from typing import Optional

from orchestrator import generate_daily_recommendation
from config import get_settings
from db import init_pool, close_pool, init_redis, close_redis
from memory.pattern_detector import detect_patterns
from memory.weekly_report import generate_weekly_report
from memory.memory_manager import extract_and_store
from chat import handle_chat_message
from journal import analyze_and_respond
from memory.reflection import generate_weekly_reflection
from daily_insight import generate_daily_insight
from first_encounter import (
    get_session_state,
    start_first_encounter,
    send_message as send_first_encounter_message,
    apply_portrait_correction,
)
from meal_planner import MealPlanInput, MealPlanner

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialise et ferme les connexions au démarrage/arrêt du serveur."""
    await init_pool()
    await init_redis()
    yield
    await close_pool()
    await close_redis()


app = FastAPI(title="VITA AI Engine", version="0.1.0", lifespan=lifespan)


def verify_service_token(x_service_token: str = Header(...)) -> bool:
    """Authentification inter-services (token partagé)."""
    if x_service_token != settings.ai_service_token:
        raise HTTPException(status_code=401, detail="Invalid service token")
    return True


class RecommendationRequest(BaseModel):
    user_id: str
    date: Optional[date] = None


class ChatRequest(BaseModel):
    user_id: str
    message: str
    conversation_id: Optional[str] = None


class PatternRequest(BaseModel):
    user_id: str


class ReportRequest(BaseModel):
    user_id: str
    period: str = "weekly"
    period_start: date


class JournalRequest(BaseModel):
    user_id: str
    content: str
    entry_id: Optional[str] = None


@app.get("/health")
async def health():
    return {"status": "ok", "service": "ai-engine"}


@app.post("/recommend")
async def get_recommendation(
    req: RecommendationRequest,
    _: bool = Depends(verify_service_token),
):
    """Génère ou récupère la recommandation du jour."""
    try:
        result = await generate_daily_recommendation(req.user_id, req.date)

        # Extraction des mémoires en arrière-plan — ne bloque pas la réponse
        import asyncio
        asyncio.ensure_future(extract_and_store(req.user_id))

        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/chat")
async def chat(
    req: ChatRequest,
    _: bool = Depends(verify_service_token),
):
    """Interface conversationnelle — questions naturelles sur la santé."""
    try:
        response = await handle_chat_message(req.user_id, req.message, req.conversation_id)
        return response
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/detect-patterns")
async def run_pattern_detection(
    req: PatternRequest,
    _: bool = Depends(verify_service_token),
):
    """Lance la détection de patterns sur les données de l'utilisateur."""
    try:
        patterns = await detect_patterns(req.user_id)
        return {"patterns_found": len(patterns), "patterns": patterns}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/report")
async def generate_report(
    req: ReportRequest,
    _: bool = Depends(verify_service_token),
):
    """Génère un rapport périodique (hebdo/mensuel/trimestriel/annuel)."""
    try:
        report = await generate_weekly_report(req.user_id, req.period_start)
        return report
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/journal/analyze")
async def analyze_journal(
    req: JournalRequest,
    _: bool = Depends(verify_service_token),
):
    """Analyse une entrée de journal et retourne l'analyse émotionnelle + réponse VITA."""
    try:
        result = await analyze_and_respond(req.user_id, req.content, req.entry_id)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class DailyInsightRequest(BaseModel):
    user_id: str
    date: Optional[date] = None


@app.post("/daily-insight/generate")
async def generate_insight(
    req: DailyInsightRequest,
    _: bool = Depends(verify_service_token),
):
    """
    Génère (ou retourne) l'insight quotidien pour un utilisateur.
    Idempotent : retourne l'existant sans régénération si déjà présent.
    Retourne null si aucune donnée disponible pour ce jour.
    """
    try:
        result = await generate_daily_insight(req.user_id, req.date)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class ReflectionRequest(BaseModel):
    user_id: str
    week_start: Optional[date] = None


@app.post("/reflection/weekly")
async def weekly_reflection(
    req: ReflectionRequest,
    _: bool = Depends(verify_service_token),
):
    """Génère (ou retourne None si déjà générée) la réflexion hebdomadaire de l'utilisateur."""
    try:
        result = await generate_weekly_reflection(req.user_id, req.week_start)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class FirstEncounterStartRequest(BaseModel):
    user_id: str


class FirstEncounterMessageRequest(BaseModel):
    user_id: str
    content: str


class FirstEncounterCorrectionRequest(BaseModel):
    user_id: str
    correction: str


@app.get("/first-encounter/session/{user_id}")
async def first_encounter_session(
    user_id: str,
    _: bool = Depends(verify_service_token),
):
    """Retourne l'état courant de la session Première Rencontre."""
    try:
        return await get_session_state(user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/first-encounter/start")
async def first_encounter_start(
    req: FirstEncounterStartRequest,
    _: bool = Depends(verify_service_token),
):
    """Démarre la Première Rencontre et retourne le message d'ouverture."""
    try:
        return await start_first_encounter(req.user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/first-encounter/message")
async def first_encounter_message(
    req: FirstEncounterMessageRequest,
    _: bool = Depends(verify_service_token),
):
    """Traite un message utilisateur et retourne la réponse VITA."""
    try:
        return await send_first_encounter_message(req.user_id, req.content)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/first-encounter/correct")
async def first_encounter_correct(
    req: FirstEncounterCorrectionRequest,
    _: bool = Depends(verify_service_token),
):
    """Applique une correction au portrait et retourne le portrait révisé."""
    try:
        return await apply_portrait_correction(req.user_id, req.correction)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/meal-planner/distribute")
async def meal_planner_distribute(
    req: MealPlanInput,
    _: bool = Depends(verify_service_token),
):
    """
    Répartit les recettes choisies sur 14 créneaux (7 jours × lunch/dinner).
    Aucune analyse nutritionnelle — pure logique d'organisation.
    """
    planner = MealPlanner()
    distribution = planner.distribute(req.recipes)
    return [item.model_dump() for item in distribution]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=settings.port)
