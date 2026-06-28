"""
Configuration pytest — injecte les variables d'environnement minimales
pour que les tests unitaires s'exécutent sans fichier .env ni Docker.

Ces valeurs sont des stubs non fonctionnels (les tests qui appellent
réellement la DB ou l'API Anthropic utilisent des mocks).
"""
import os

# Injecte avant tout import de module applicatif
os.environ.setdefault("DATABASE_URL", "postgresql://vita:vita@localhost:5432/vita")
os.environ.setdefault("ANTHROPIC_API_KEY", "test-key-not-real")
os.environ.setdefault("AI_SERVICE_TOKEN", "test-token-not-real")
