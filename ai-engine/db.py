"""
Pool de connexions partagé pour l'ai-engine.

Pourquoi asyncpg plutôt que psycopg2 :
- asyncpg est nativement async : aucun blocage de la boucle d'événements FastAPI
- Pool partagé : les connexions sont réutilisées entre les requêtes
- psycopg2 dans une coroutine async bloquait tous les workers simultanément

Usage :
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT ...", arg1, arg2)

    redis = await get_redis()
    await redis.get("key")
"""
import asyncpg
import redis.asyncio as aioredis
from config import get_settings

_pool: asyncpg.Pool | None = None
_redis: aioredis.Redis | None = None


async def init_pool() -> None:
    """Initialise le pool asyncpg. Appelé une seule fois au démarrage."""
    global _pool
    settings = get_settings()
    _pool = await asyncpg.create_pool(
        settings.database_url,
        min_size=2,
        max_size=10,
        command_timeout=30,
    )


async def close_pool() -> None:
    """Ferme le pool proprement à l'arrêt du serveur."""
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


async def get_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("DB pool not initialized — init_pool() must be called at startup")
    return _pool


async def init_redis() -> None:
    """Initialise le client Redis async. Appelé une seule fois au démarrage."""
    global _redis
    settings = get_settings()
    _redis = aioredis.from_url(settings.redis_url, decode_responses=True)


async def close_redis() -> None:
    """Ferme la connexion Redis proprement."""
    global _redis
    if _redis:
        await _redis.aclose()
        _redis = None


async def get_redis() -> aioredis.Redis:
    if _redis is None:
        raise RuntimeError("Redis not initialized — init_redis() must be called at startup")
    return _redis
