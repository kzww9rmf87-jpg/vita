"""
La Première Rencontre — moteur conversationnel IA.

Conversation naturelle et profonde entre VITA et l'utilisateur.
Ce n'est PAS un onboarding : c'est une vraie rencontre.

Flux :
  1. start_first_encounter(user_id) → crée la session + génère le message d'ouverture
  2. send_message(user_id, user_content) → traite le message, génère la réponse VITA
     → extrait des mémoires longue durée
     → si is_complete : génère le portrait
  3. apply_portrait_correction(user_id, correction) → affine le portrait
  4. get_session_state(user_id) → état courant pour l'iOS

Claude est utilisé pour la génération de réponse ET l'extraction de mémoires
dans le même appel (un seul appel par message utilisateur).
"""
from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional

import anthropic

from config import get_settings
from db import get_pool

logger = logging.getLogger(__name__)
settings = get_settings()
_client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)


# ── Constantes ────────────────────────────────────────────────────────────────

# Types valides dans vita_long_memories — miroir exact de la contrainte SQL
_VALID_MEMORY_TYPES = frozenset({
    "person", "project", "habit", "fear", "motivation",
    "goal", "value", "health", "work", "family",
    "emotion", "event", "other",
})

# Nombre minimum d'échanges avant que VITA puisse clore la rencontre
_MIN_EXCHANGES_BEFORE_CLOSE = 8

# Topics de la conversation (ordre naturel — VITA s'adapte)
TOPICS = [
    "situation_actuelle",
    "valeurs",
    "personnes_importantes",
    "santé",
    "travail_études",
    "projets",
    "habitudes",
    "sources_énergie",
    "difficultés",
    "objectifs",
    "fonctionnement_personnel",
    "attentes_vita",
]

# Message d'ouverture — statique, chaleureux, sans pression
OPENING_MESSAGE = (
    "Bonjour. Je suis contente que tu sois là.\n\n"
    "Je voudrais te connaître mieux — pas à travers des formulaires, "
    "mais à travers une vraie conversation. On peut prendre le temps qu'il faut. "
    "Si un sujet te semble trop personnel, dis-le moi simplement et on passera à autre chose.\n\n"
    "Pour commencer : comment décrirais-tu la période que tu traverses en ce moment ?"
)

# ── Prompts ───────────────────────────────────────────────────────────────────

_CONVERSATION_SYSTEM_PROMPT = """
Tu es VITA, un Témoin Bienveillant. Tu rencontres cet utilisateur pour la première fois,
dans le cadre de "La Première Rencontre".

MISSION
Mener une conversation naturelle et profonde pour construire une première représentation
de la personne. À la fin, tu rédigeras un portrait intime d'elle.

PRINCIPES ABSOLUS
— Jamais plus d'une question à la fois
— Jamais une liste de questions
— Toujours s'adapter à ce qui vient d'être dit (rebondir, approfondir si pertinent)
— Ton calme, curieux, bienveillant, jamais intrusif
— Si l'utilisateur répond "Je préfère ne pas répondre" ou "On verra plus tard" : accepter sans insister, passer à autre chose
— Jamais de jugement, jamais de conseil non sollicité
— Jamais de score, jamais de note, jamais de "bien" ou "bravo"

THÈMES À EXPLORER (dans l'ordre naturel, selon la conversation)
1. situation_actuelle — La période traversée en ce moment
2. valeurs — Ce qui compte vraiment, les convictions profondes
3. personnes_importantes — Les relations qui comptent
4. santé — Ressenti global, énergie, vitalité
5. travail_études — Contexte professionnel ou académique
6. projets — Ce qui occupe l'esprit, les initiatives en cours
7. habitudes — Routines, rythmes de vie
8. sources_énergie — Ce qui ressource, ce qui donne de la joie
9. difficultés — Ce qui pèse en ce moment
10. objectifs — Où l'utilisateur veut aller
11. fonctionnement_personnel — Comment il/elle fonctionne, ce qui l'aide ou l'entrave
12. attentes_vita — Ce que l'utilisateur attend de VITA

DURÉE
10 à 15 échanges. La conversation doit être naturelle, pas exhaustive.
Tu peux clore la rencontre quand :
— Au moins 8 échanges ont eu lieu (exchange_count >= 8 dans le contexte)
— Au moins 5 thèmes différents ont été abordés
— Tu as une représentation suffisante pour écrire un portrait

FORMAT DE RÉPONSE OBLIGATOIRE
Réponds UNIQUEMENT en JSON valide, sans markdown, sans commentaires :
{
  "response": "ta réponse à l'utilisateur (1 à 3 phrases, toujours une question en fin)",
  "topic": "le thème courant parmi les 12 ci-dessus",
  "is_complete": false,
  "memories": [
    {"content": "fait significatif à retenir", "type": "goal", "importance": 3}
  ]
}

TYPES DE MÉMOIRE AUTORISÉS
person, project, habit, fear, motivation, goal, value, health, work, family, emotion, event, other

IMPORTANCE
1 = information générale
2 = information significative
3 = information très importante (objectif de vie, difficulté majeure, valeur fondamentale)

Règles pour les mémoires :
— Ne stocker que ce qui est concret et significatif
— 0 à 3 mémoires par échange utilisateur
— Ne pas dupliquer ce qui a déjà été capturé
— Le content est une phrase nominale en français ("Travaille comme...", "Souhaite...", "A peur de...")

is_complete = true UNIQUEMENT quand les conditions de clôture sont réunies.
Quand is_complete = true, la "response" est le message de transition vers le portrait
(ex : "Je crois avoir saisi quelque chose d'essentiel de toi. Je vais maintenant
composer ma première impression — quelques instants...")
"""

_PORTRAIT_SYSTEM_PROMPT = """
Tu es VITA, un Témoin Bienveillant. Tu viens de terminer ta Première Rencontre.

Rédige "Mon Premier Portrait" : un texte fluide et chaleureux de 400 à 500 mots
qui capture l'essence de cette personne telle que tu l'as comprise à travers
la conversation.

RÈGLES ABSOLUES
— Jamais de liste, jamais de tirets, jamais de sous-titres
— Texte fluide, en paragraphes connectés
— Maximum 500 mots
— Toujours des formulations prudentes et humbles :
  "Il me semble...", "J'ai l'impression que...", "Tu sembles...",
  "Ce que j'ai perçu...", "Si j'ai bien compris..."
— JAMAIS "Tu es..." (affirmatif définitif sur la personnalité)
— Évoquer au moins : forces perçues, valeurs, projets, priorités, difficultés, ressources
— Ton : chaleureux, précis, humble, bienveillant
— Langue : français
— Pas de conclusion en mode "coach" ou en mode conseil

Commence directement par le portrait, sans titre ni introduction.
"""

_CORRECTION_SYSTEM_PROMPT = """
Tu es VITA, un Témoin Bienveillant. L'utilisateur vient de lire son premier portrait
et te donne une correction ou un complément.

Ton rôle : intégrer cette correction dans le portrait existant.

RÈGLES
— Respecter toutes les règles du portrait original (ton, formulations, format)
— Intégrer la correction naturellement (pas de "Comme tu me l'as précisé...")
— Retourner UNIQUEMENT le portrait révisé complet (400-500 mots)
— Même format : texte fluide, paragraphes, sans listes ni titres
"""


# ── Fonctions publiques ───────────────────────────────────────────────────────

async def get_session_state(user_id: str) -> dict:
    """
    Retourne l'état courant de la session Première Rencontre.
    Utilisé par GET /first-encounter/session dans le data-service.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        session = await conn.fetchrow(
            """
            SELECT id::text, status, topic_index, exchange_count, portrait_text,
                   completed_at::text, created_at::text
            FROM first_encounter_sessions
            WHERE user_id = $1
            """,
            user_id,
        )
        if not session:
            return {"status": "not_started"}

        if session["status"] == "completed":
            return {
                "status": "completed",
                "portrait": session["portrait_text"],
                "completed_at": session["completed_at"],
            }

        # In progress — charger les échanges
        exchanges = await conn.fetch(
            """
            SELECT role, content, topic, created_at::text
            FROM first_encounter_exchanges
            WHERE session_id = $1
            ORDER BY created_at ASC
            """,
            session["id"],
        )
        return {
            "status": "in_progress",
            "topic_index": session["topic_index"],
            "exchange_count": session["exchange_count"],
            "exchanges": [
                {
                    "role": e["role"],
                    "content": e["content"],
                    "topic": e["topic"],
                    "created_at": e["created_at"],
                }
                for e in exchanges
            ],
        }


async def start_first_encounter(user_id: str) -> dict:
    """
    Crée la session et retourne le message d'ouverture de VITA.
    Idempotent : si la session existe déjà, retourne l'état courant.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        # Vérifier si une session existe
        existing = await conn.fetchrow(
            "SELECT id::text, status FROM first_encounter_sessions WHERE user_id = $1",
            user_id,
        )
        if existing:
            state = await get_session_state(user_id)
            return {"already_started": True, **state}

        # Créer la session
        session_row = await conn.fetchrow(
            """
            INSERT INTO first_encounter_sessions (user_id, status, topic_index, exchange_count)
            VALUES ($1, 'in_progress', 0, 0)
            RETURNING id::text
            """,
            user_id,
        )
        session_id = session_row["id"]

        # Persister le message d'ouverture
        await conn.execute(
            """
            INSERT INTO first_encounter_exchanges (session_id, user_id, role, content, topic)
            VALUES ($1, $2, 'vita', $3, $4)
            """,
            session_id, user_id, OPENING_MESSAGE, "situation_actuelle",
        )

        return {
            "already_started": False,
            "status": "in_progress",
            "vita_opening": OPENING_MESSAGE,
            "session_id": session_id,
        }


async def send_message(user_id: str, user_content: str) -> dict:
    """
    Traite un message utilisateur et retourne la réponse de VITA.

    Flux :
      1. Stocker le message utilisateur
      2. Charger l'historique
      3. Appeler Claude (réponse + mémoires)
      4. Stocker les mémoires dans vita_long_memories
      5. Stocker la réponse VITA
      6. Si is_complete : générer le portrait
      7. Retourner le résultat
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        session = await conn.fetchrow(
            """
            SELECT id::text, status, exchange_count, topic_index
            FROM first_encounter_sessions
            WHERE user_id = $1
            """,
            user_id,
        )
        if not session:
            raise ValueError(f"No first encounter session for user {user_id}")
        if session["status"] == "completed":
            raise ValueError(f"First encounter already completed for user {user_id}")

        session_id = session["id"]
        exchange_count = session["exchange_count"]
        topic_index = session["topic_index"]

        # 1. Stocker le message utilisateur
        await conn.execute(
            """
            INSERT INTO first_encounter_exchanges (session_id, user_id, role, content, topic)
            VALUES ($1, $2, 'user', $3, $4)
            """,
            session_id, user_id, user_content, TOPICS[min(topic_index, len(TOPICS) - 1)],
        )
        exchange_count += 1

        # 2. Charger l'historique complet
        exchanges = await conn.fetch(
            """
            SELECT role, content, topic
            FROM first_encounter_exchanges
            WHERE session_id = $1
            ORDER BY created_at ASC
            """,
            session_id,
        )

        # 3. Appeler Claude
        ai_result = await _call_claude_conversation(
            exchanges=list(exchanges),
            exchange_count=exchange_count,
        )

        vita_response: str = ai_result["response"]
        topic: str = ai_result.get("topic", TOPICS[min(topic_index, len(TOPICS) - 1)])
        is_complete: bool = ai_result.get("is_complete", False)
        raw_memories: list = ai_result.get("memories", [])

        # 4. Stocker les mémoires
        await _store_long_memories(conn, user_id, raw_memories)

        # 5. Stocker la réponse VITA
        new_topic_index = _topic_to_index(topic, topic_index)
        await conn.execute(
            """
            INSERT INTO first_encounter_exchanges (session_id, user_id, role, content, topic)
            VALUES ($1, $2, 'vita', $3, $4)
            """,
            session_id, user_id, vita_response, topic,
        )

        # 6. Si is_complete : générer le portrait
        portrait: str | None = None
        if is_complete and exchange_count >= _MIN_EXCHANGES_BEFORE_CLOSE:
            portrait = await _generate_portrait(user_id, list(exchanges) + [
                {"role": "user", "content": user_content, "topic": topic},
                {"role": "vita", "content": vita_response, "topic": topic},
            ])
            await conn.execute(
                """
                UPDATE first_encounter_sessions
                SET status = 'completed',
                    exchange_count = $1,
                    topic_index = $2,
                    portrait_text = $3,
                    completed_at = NOW()
                WHERE id = $4
                """,
                exchange_count, new_topic_index, portrait, session_id,
            )
        else:
            await conn.execute(
                """
                UPDATE first_encounter_sessions
                SET exchange_count = $1, topic_index = $2
                WHERE id = $3
                """,
                exchange_count, new_topic_index, session_id,
            )

        logger.info(
            "[first_encounter] user=%s exchange=%d topic=%s is_complete=%s",
            user_id, exchange_count, topic, is_complete,
        )

        return {
            "vita_response": vita_response,
            "topic": topic,
            "exchange_number": exchange_count,
            "is_complete": is_complete and exchange_count >= _MIN_EXCHANGES_BEFORE_CLOSE,
            "portrait": portrait,
        }


async def apply_portrait_correction(user_id: str, correction: str) -> dict:
    """
    L'utilisateur corrige ou complète le portrait.
    Génère un portrait révisé et met à jour la session.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        session = await conn.fetchrow(
            "SELECT id::text, portrait_text FROM first_encounter_sessions WHERE user_id = $1",
            user_id,
        )
        if not session or not session["portrait_text"]:
            raise ValueError(f"No completed portrait for user {user_id}")

        portrait_text: str = session["portrait_text"]

        # Générer le portrait corrigé
        msg = await _client.messages.create(
            model=settings.model_analysis,
            max_tokens=800,
            system=_CORRECTION_SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": (
                        f"Voici le portrait actuel :\n\n{portrait_text}\n\n"
                        f"Voici la correction de l'utilisateur :\n\n{correction}"
                    ),
                }
            ],
        )
        revised = msg.content[0].text.strip()

        # Mettre à jour la DB
        await conn.execute(
            "UPDATE first_encounter_sessions SET portrait_text = $1 WHERE id = $2",
            revised, session["id"],
        )

        return {"portrait": revised}


# ── Fonctions internes ────────────────────────────────────────────────────────

async def _call_claude_conversation(exchanges: list, exchange_count: int) -> dict:
    """
    Appel Claude pour générer la prochaine réponse VITA.
    Retourne : {response, topic, is_complete, memories}
    """
    # Construire le contexte échanges → messages Claude
    messages = []
    for ex in exchanges:
        role = "assistant" if ex["role"] == "vita" else "user"
        messages.append({"role": role, "content": ex["content"]})

    # Ajouter le contexte (exchange_count) dans le system
    system_with_context = (
        _CONVERSATION_SYSTEM_PROMPT
        + f"\n\n[Contexte interne : exchange_count = {exchange_count}]"
    )

    try:
        msg = await _client.messages.create(
            model=settings.model_analysis,
            max_tokens=600,
            system=system_with_context,
            messages=messages,
        )
        raw = msg.content[0].text.strip()
        return _parse_conversation_response(raw)
    except Exception as exc:
        logger.error("[first_encounter] Claude error: %s", exc)
        # Fallback : réponse neutre, pas de mémoires
        return {
            "response": "Je t'écoute. Qu'est-ce qui est important pour toi en ce moment ?",
            "topic": "situation_actuelle",
            "is_complete": False,
            "memories": [],
        }


def _parse_conversation_response(raw: str) -> dict:
    """
    Parse la réponse JSON de Claude.
    Gère le JSON dans markdown (```json ... ```) et les champs manquants.
    """
    # Extraire JSON si dans un bloc markdown
    match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.DOTALL)
    if match:
        raw = match.group(1)
    else:
        # Chercher le premier { ... } valide
        m2 = re.search(r"\{.*\}", raw, re.DOTALL)
        if m2:
            raw = m2.group(0)

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {
            "response": "Je t'écoute. Qu'est-ce qui est important pour toi en ce moment ?",
            "topic": "situation_actuelle",
            "is_complete": False,
            "memories": [],
        }

    # Valider et nettoyer
    response = str(data.get("response", "")).strip()
    if not response:
        response = "Je t'écoute. Qu'est-ce qui te tient à cœur ?"

    topic = str(data.get("topic", "situation_actuelle")).strip()
    if topic not in TOPICS:
        topic = "situation_actuelle"

    is_complete = bool(data.get("is_complete", False))

    memories = _validate_memories(data.get("memories", []))

    return {
        "response": response[:1000],  # Sécurité : max 1000 chars
        "topic": topic,
        "is_complete": is_complete,
        "memories": memories,
    }


def _validate_memories(raw: object) -> list[dict]:
    """
    Valide et filtre la liste de mémoires retournée par Claude.
    """
    if not isinstance(raw, list):
        return []

    validated = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        content = str(item.get("content", "")).strip()
        if not content or len(content) < 5:
            continue
        mem_type = str(item.get("type", "other")).lower()
        if mem_type not in _VALID_MEMORY_TYPES:
            mem_type = "other"
        importance_raw = item.get("importance", 2)
        try:
            importance = max(1, min(5, int(importance_raw)))
        except (TypeError, ValueError):
            importance = 2

        validated.append({
            "content": content[:500],  # Tronquer à la limite DB
            "type": mem_type,
            "importance": importance,
        })

    return validated[:5]  # Max 5 mémoires par échange


async def _store_long_memories(conn, user_id: str, memories: list[dict]) -> None:
    """
    Persiste les mémoires dans vita_long_memories.
    Source = 'explicit' (l'utilisateur a dit cela explicitement).
    ON CONFLICT DO NOTHING : la contrainte unique (user_id, LEFT(summary,200)) gère les doublons.
    """
    for m in memories:
        try:
            await conn.execute(
                """
                INSERT INTO vita_long_memories
                    (user_id, type, summary, importance, confidence, source)
                VALUES ($1, $2, $3, $4, $5, 'explicit')
                ON CONFLICT (user_id, LEFT(summary, 200)) DO NOTHING
                """,
                user_id, m["type"], m["content"], m["importance"], 0.9,
            )
        except Exception as exc:
            # Log sans crasher — une mémoire ratée ne doit pas bloquer la conversation
            logger.warning("[first_encounter] memory store error: %s", exc)


async def _generate_portrait(user_id: str, exchanges: list) -> str:
    """
    Génère le portrait intime de l'utilisateur à partir de l'historique complet.
    """
    # Construire le résumé de la conversation pour le portrait
    conversation_summary = "\n".join(
        f"{'VITA' if ex['role'] == 'vita' else 'Utilisateur'}: {ex['content']}"
        for ex in exchanges
        if ex.get("content")
    )

    try:
        msg = await _client.messages.create(
            model=settings.model_analysis,
            max_tokens=900,
            system=_PORTRAIT_SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": (
                        "Voici la conversation complète de la Première Rencontre :\n\n"
                        f"{conversation_summary}\n\n"
                        "Rédige maintenant le portrait de cette personne."
                    ),
                }
            ],
        )
        portrait = msg.content[0].text.strip()
        # Sécurité : tronquer à 3000 chars (large marge pour 500 mots)
        return portrait[:3000]
    except Exception as exc:
        logger.error("[first_encounter] portrait generation error: %s", exc)
        return (
            "Il me semble avoir commencé à te connaître à travers cette conversation. "
            "Je n'ai pas pu composer ton portrait complet pour l'instant — "
            "tu pourras le retrouver bientôt."
        )


def _topic_to_index(topic: str, current_index: int) -> int:
    """Retourne le nouvel index de topic, jamais inférieur au courant."""
    try:
        idx = TOPICS.index(topic)
        return max(current_index, idx)
    except ValueError:
        return current_index
