from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    database_url: str
    redis_url: str = "redis://localhost:6379"
    anthropic_api_key: str
    pinecone_api_key: str = ""
    pinecone_index: str = "vita-patterns"
    ai_service_token: str
    port: int = 3003

    model_analysis: str = "claude-sonnet-4-6"
    model_fast: str = "claude-haiku-4-5-20251001"
    max_tokens_recommendation: int = 300
    max_tokens_analysis: int = 1000

    class Config:
        env_file = ".env"


@lru_cache
def get_settings() -> Settings:
    return Settings()
