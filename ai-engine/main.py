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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=settings.port)
