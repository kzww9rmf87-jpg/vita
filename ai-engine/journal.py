"""
Journal intime intelligent — analyse et réponse VITA.

Flux pour une entrée de journal :
  1. Détection de sécurité (sync, toujours)
  2. Analyse émotionnelle via Claude (async, avec fallback local)
  3. Génération de la réponse VITA (même appel que l'analyse)
  4. Persistance en DB
  5. Mise à jour de la mémoire émotionnelle (fire-and-forget)

VITA comme témoin émotionnel :
  - Reflète avant de répondre — montre qu'elle a entendu
  - Une seule question ouverte max par réponse
  - Ne prescrit jamais ("tu devrais")
  - Ne minimise pas ("c'est normal", "ça va aller")
  - Si signal de crise : ressource 3114 en tête de réponse
"""
import json
import logging
import re
from typing import Optional

import anthropic

from config import get_settings
from db import get_pool
from safety import detect_safety_signals, build_crisis_prefix
from emotional_memory import update_emotional_memories, load_emotional_context
from memory.consolidation import consolidate_from_interaction
from memory.life_story import detect_life_events
from memory.models import MemorySource

logger = logging.getLogger(__name__)
settings = get_settings()
client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

# ── Prompt système journal ───────────────────────────────────────────────────

_JOURNAL_SYSTEM = """Tu es VITA — un Témoin Bienveillant.

L'utilisateur t'a partagé une entrée de journal intime. Ton rôle est double :
1. Analyser ce que l'entrée révèle (analyse JSON, usage interne)
2. Répondre à l'utilisateur avec douceur et présence

---

RÈGLES ABSOLUES POUR LA RÉPONSE :

— Tu reflètes avant de répondre. Ta première phrase doit montrer que tu as vraiment entendu — pas une reformulation froide, une présence.
— Maximum 4 phrases au total.
— Une seule question ouverte, en dernière phrase. Jamais plus d'une question.
— Zéro prescription : pas de "tu devrais", "essaie de", "il faut que".
— Zéro minimisation : pas de "c'est normal", "ça va aller", "tout le monde passe par là".
— Tu peux nommer une émotion que tu perçois — pas la définir, juste la nommer avec douceur.
— Si l'utilisateur exprime de la fierté ou quelque chose de positif, accueille-le pleinement sans te précipiter vers "et maintenant".

---

FORMAT DE RÉPONSE :

Réponds avec un objet JSON unique :
{
  "mood_label": "joie|tristesse|anxiété|colère|fatigue|fierté|neutre|ambivalence",
  "emotional_tone": "positif|négatif|ambivalent|neutre",
  "themes": ["thème1", "thème2"],
  "intensity": <1-10>,
  "valence": <-1.0 à 1.0>,
  "vita_response": "Ta réponse VITA complète ici"
}

Pour les thèmes, utilise des mots simples en français (exemples: travail, famille, santé, sport, relation, fatigue, solitude, confiance, avenir, corps, alimentation).

Pour vita_response : texte brut, pas de markdown. Chaleureux, direct, présent.
"""


async def analyze_and_respond(
    user_id: str,
    content: str,
    entry_id: Optional[str] = None,
) -> dict:
    """
    Analyse une entrée de journal et génère la réponse VITA.
    Retourne le dict complet à persister.
    """

    # ── 1. Sécurité (sync, prioritaire) ──────────────────────────────────────
    safety = detect_safety_signals(content)
    crisis_prefix = build_crisis_prefix(safety)

    # ── 2. Contexte émotionnel existant ──────────────────────────────────────
    emotional_ctx = await load_emotional_context(user_id, limit=3)
    context_block = ""
    if emotional_ctx:
        lines = "\n".join(
            f"- {m['theme']} (valence {m['valence']:+.1f}, {m['recurrence_count']}x)"
            for m in emotional_ctx
        )
        context_block = f"\n\nThèmes émotionnels récurrents de cet utilisateur :\n{lines}"

    # ── 3. Appel Claude ───────────────────────────────────────────────────────
    user_prompt = f"Entrée de journal :\n\n{content}{context_block}"

    try:
        response = await client.messages.create(
            model=settings.model_fast,
            max_tokens=600,
            system=_JOURNAL_SYSTEM,
            messages=[{"role": "user", "content": user_prompt}],
        )
        raw = response.content[0].text
        analysis = _parse_analysis(raw)

    except Exception as exc:
        logger.warning("[JOURNAL] Claude unavailable, using fallback: %s", exc)
        analysis = _fallback_analysis(content)

    # ── 4. Injecte le préfixe de crise si nécessaire ─────────────────────────
    if crisis_prefix:
        analysis["vita_response"] = crisis_prefix + analysis["vita_response"]

    # ── 5. Mise à jour mémoire émotionnelle (fire-and-forget) ────────────────
    import asyncio
    asyncio.ensure_future(
        update_emotional_memories(
            user_id,
            themes=analysis.get("themes", []),
            valence=analysis.get("valence", 0.0),
            entry_summary=_short_summary(analysis),
        )
    )

    # ── 6. Flag de sécurité si nécessaire ────────────────────────────────────
    if safety.has_flag:
        asyncio.ensure_future(
            _save_safety_flag(user_id, safety, entry_id)
        )

    # ── 7. Consolidation mémoire longue durée (fire-and-forget) ──────────────
    # Pas de mémorisation si le contenu contient un signal de crise :
    # le texte d'une détresse aiguë ne doit pas être réinjecté dans de futures conversations.
    if not safety.has_flag:
        asyncio.ensure_future(
            consolidate_from_interaction(
                user_id=user_id,
                text=content,
                source=MemorySource.JOURNAL,
                source_id=entry_id,
            )
        )
        asyncio.ensure_future(
            detect_life_events(
                user_id=user_id,
                text=content,
                source=MemorySource.JOURNAL,
                source_id=entry_id,
            )
        )

    return {
        "mood_label": analysis.get("mood_label", "neutre"),
        "emotional_tone": analysis.get("emotional_tone", "neutre"),
        "themes": analysis.get("themes", []),
        "intensity": analysis.get("intensity", 5),
        "valence": analysis.get("valence", 0.0),
        "vita_response": analysis.get("vita_response", ""),
        "safety_flag": safety.has_flag,
        "safety_severity": safety.severity if safety.has_flag else None,
    }


def _parse_analysis(raw: str) -> dict:
    """Parse la réponse Claude — extrait le JSON, valide les champs."""
    try:
        # Strip markdown code fences if present
        clean = re.sub(r"^```(?:json)?\s*", "", raw.strip(), flags=re.MULTILINE)
        clean = re.sub(r"\s*```$", "", clean.strip(), flags=re.MULTILINE)
        data = json.loads(clean)

        return {
            "mood_label": str(data.get("mood_label", "neutre"))[:50],
            "emotional_tone": str(data.get("emotional_tone", "neutre"))[:20],
            "themes": [str(t)[:50] for t in data.get("themes", []) if t][:5],
            "intensity": max(1, min(10, int(data.get("intensity", 5)))),
            "valence": max(-1.0, min(1.0, float(data.get("valence", 0.0)))),
            "vita_response": str(data.get("vita_response", "")).strip(),
        }
    except Exception as exc:
        logger.warning("[JOURNAL] Failed to parse Claude response: %s", exc)
        return _fallback_analysis("")


def _fallback_analysis(content: str) -> dict:
    """Analyse locale minimale quand Claude est indisponible."""
    word_count = len(content.split())
    intensity = min(10, max(1, word_count // 20 + 3))

    return {
        "mood_label": "neutre",
        "emotional_tone": "neutre",
        "themes": [],
        "intensity": intensity,
        "valence": 0.0,
        "vita_response": (
            "J'ai bien reçu ce que tu m'as partagé. "
            "Je ne peux pas analyser plus finement pour l'instant, "
            "mais ton entrée est enregistrée. "
            "Comment te sens-tu là, maintenant ?"
        ),
    }


def _short_summary(analysis: dict) -> Optional[str]:
    """Phrase de résumé courte pour la mémoire émotionnelle."""
    tone = analysis.get("emotional_tone", "neutre")
    mood = analysis.get("mood_label", "neutre")
    if mood != "neutre":
        return f"Entrée {tone} — {mood}"
    return None


async def _save_safety_flag(user_id: str, safety, entry_id: Optional[str]) -> None:
    """Persiste un signal de sécurité en DB."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                """INSERT INTO safety_flags
                   (user_id, source, severity, category, excerpt)
                   VALUES ($1, 'journal', $2, $3, $4)""",
                user_id, safety.severity, safety.category, safety.excerpt
            )
        logger.warning(
            "[SAFETY_FLAG] Severity=%s category=%s user=%s entry=%s",
            safety.severity, safety.category, user_id, entry_id
        )
    except Exception as exc:
        logger.error("[SAFETY_FLAG] Failed to save: %s", exc)
