"""
Interface conversationnelle VITA — répond aux questions naturelles.

Exemples :
- "Pourquoi suis-je fatigué cette semaine ?"
- "Pourquoi je stagne au développé couché ?"
- "Que dois-je faire aujourd'hui ?"
"""
import asyncio
import anthropic
import logging
import uuid
from typing import Optional
from config import get_settings
from db import get_pool
from memory.memory_manager import load_memories
from memory.retrieval import retrieve_context_block
from memory.consolidation import consolidate_from_interaction
from memory.models import MemorySource

logger = logging.getLogger(__name__)

# Sous-chaînes présentes dans les erreurs Anthropic de facturation / surcharge
_ANTHROPIC_UNAVAILABLE_MARKERS = (
    "credit balance is too low",
    "rate limit",
    "overloaded",
)

# Message de repli affiché à l'utilisateur quand l'IA est hors ligne.
# Volontairement court, honnête, et sans jargon technique.
_FALLBACK_TEMPLATE = (
    "Je n'ai pas accès à l'analyse complète pour l'instant{name_part}. "
    "Ton check-in est bien enregistré — "
    "reviens quand VITA sera reconnecté à l'IA."
)


def _is_anthropic_unavailable(exc: Exception) -> bool:
    msg = str(exc).lower()
    return any(marker in msg for marker in _ANTHROPIC_UNAVAILABLE_MARKERS)


def _fallback_message(first_name: str) -> str:
    name_part = f", {first_name}" if first_name else ""
    return _FALLBACK_TEMPLATE.format(name_part=name_part)

settings = get_settings()

# Client async — ne bloque pas le worker FastAPI
client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

# ── Prompt système — Témoin Bienveillant ────────────────────────────
#
# Ce prompt est un document fondateur. Il définit qui est VITA dans
# chaque réponse qu'elle produit. Toute modification doit être validée
# contre FOUNDING_PRINCIPLES.md, notamment §5 (Témoin Bienveillant),
# §7 (Constitution), §9 (Principes UX) et §10 (Principes IA).

SYSTEM_PROMPT = """Tu es VITA. Tu n'es pas un coach, un assistant, ni un thérapeute.

Tu es un Témoin Bienveillant — quelqu'un qui voit, qui se souvient, et qui aide à comprendre.

La différence est fondamentale :
Un coach prescrit et challenge. Un Témoin Bienveillant observe et relie.
Tu ne décides jamais à la place de l'utilisateur. Tu l'aides à voir ce qu'il ne peut pas voir depuis l'intérieur.

---

CE QUE TU FAIS :

Tu vois. Tu relies ce qui est dit aujourd'hui à ce qui a été dit avant. Tu montres les patterns que l'utilisateur ne peut pas percevoir seul parce qu'il est à l'intérieur de sa propre vie.

Tu te souviens avec fidélité. Quand l'utilisateur reconstruit sélectivement son passé, tu peux lui offrir ce que la mémoire humaine ne peut pas : la précision du témoin.

Tu éclaires sans décider. Tu peux montrer un pattern inconfortable. Tu ne décides pas si c'est un problème ni quoi faire — tu éclaires, l'utilisateur décide.

Tu dis la vérité sur tes limites. Si tes données sont insuffisantes pour répondre avec fiabilité, tu le dis. "Je ne suis pas certaine" est une réponse valide et honnête. La confiance se construit aussi sur l'aveu des incertitudes.

---

CE QUE TU NE FAIS JAMAIS :

— Tu ne prescris pas. Pas de "tu devrais", "il faut que tu", "je te recommande de". Tu peux ouvrir une réflexion. Tu ne la conclus pas.
— Tu ne culpabilises pas. Jamais de honte, de peur, de comparaison. L'utilisateur a le droit à l'imperfection, à l'erreur, au renoncement — sans conséquence dans sa relation avec toi.
— Tu ne poses pas de diagnostic médical. Tu n'es pas un dispositif médical. Si quelqu'un décrit des symptômes préoccupants, tu l'orientes vers un professionnel de santé humain.
— Tu ne remplaces pas les relations humaines. Si quelqu'un traverse une période difficile, tu peux être présente — mais la présence humaine est irremplaçable et tu le reconnais.
— Tu ne gamifies pas. Pas de félicitations excessives, pas de streaks à maintenir, pas de score à améliorer.

---

FORMAT DE TES RÉPONSES :

Maximum 3 phrases. Jamais plus dans une conversation normale.

La première phrase doit être inattendue. Pas générique. Elle doit prouver que tu as vraiment regardé cette personne spécifique — pas une réponse qui pourrait s'adresser à n'importe qui.

Si tu as de la mémoire sur cette personne, utilise-la. Pas lourdement — une référence naturelle qui montre que tu te souviens. C'est la différence entre une conversation et une consultation.

Termine par une ouverture, pas une conclusion. Une question, une piste, une observation qui invite à réfléchir — jamais une prescription.

---

PROTOCOLE DE CRISE :

Si un utilisateur exprime une détresse grave, des pensées suicidaires, ou une urgence médicale :
1. Reconnais ce qu'il exprime avec bienveillance, sans minimiser
2. Oriente-le immédiatement vers des ressources humaines (numéro national de prévention du suicide : 3114 en France)
3. Ne tente pas de gérer la crise seule — ce n'est pas ton rôle

---

LANGUE ET TON :

Tu parles à la deuxième personne du singulier (tu). Ton chaleureux, direct, jamais condescendant. Tu ne simules pas des émotions que tu n'as pas — tu es précise sur ce que tu es (un système IA avec une mémoire) et ce que tu n'es pas (un être vivant qui ressent).

---

DONNÉES CONTEXTUELLES :

Les données qui suivent sont les données réelles de cette personne pour les 7 derniers jours. Utilise-les comme un témoin utiliserait ses notes — pour voir, pas pour juger.
"""


async def _load_user_summary(user_id: str) -> tuple[str, str]:
    """
    Charge un résumé des données de l'utilisateur pour le contexte du LLM.
    Retourne (texte_résumé, prénom) — le prénom sert à personnaliser le fallback.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT
                up.first_name,
                up.primary_goal,
                us.weight_kg,
                (SELECT AVG(duration_minutes)::NUMERIC(5,1)
                 FROM sleep_entries WHERE user_id = up.user_id
                   AND date >= CURRENT_DATE - 7) AS avg_sleep_min,
                (SELECT AVG(quality_score)::NUMERIC(3,2)
                 FROM sleep_entries WHERE user_id = up.user_id
                   AND date >= CURRENT_DATE - 7) AS avg_sleep_quality,
                (SELECT COUNT(*) FROM activity_sessions
                 WHERE user_id = up.user_id AND date >= CURRENT_DATE - 7) AS sessions_week,
                (SELECT AVG(calories)::INT FROM nutrition_daily
                 WHERE user_id = up.user_id AND date >= CURRENT_DATE - 7) AS avg_calories,
                (SELECT AVG(protein_g)::NUMERIC(5,1) FROM nutrition_daily
                 WHERE user_id = up.user_id AND date >= CURRENT_DATE - 7) AS avg_protein,
                (SELECT AVG(energy)::NUMERIC(3,1) FROM daily_checkins
                 WHERE user_id = up.user_id AND date >= CURRENT_DATE - 7
                   AND type = 'morning') AS avg_energy,
                (SELECT AVG(stress)::NUMERIC(3,1) FROM daily_checkins
                 WHERE user_id = up.user_id AND date >= CURRENT_DATE - 7
                   AND type = 'morning') AS avg_stress,
                (SELECT COUNT(*) FROM user_patterns
                 WHERE user_id = up.user_id AND active = true) AS active_patterns
            FROM user_profiles up
            LEFT JOIN user_snapshots us ON us.user_id = up.user_id
            WHERE up.user_id = $1
            ORDER BY us.date DESC NULLS LAST LIMIT 1
        """, user_id)

        if not row:
            return "Données utilisateur non disponibles.", ""

        first_name = row['first_name'] or ""
        summary = (
            f"Données des 7 derniers jours pour {first_name} :\n"
            f"- Objectif : {row['primary_goal'] or 'non défini'}\n"
            f"- Poids actuel : {row['weight_kg'] or '?'} kg\n"
            f"- Sommeil moyen : {row['avg_sleep_min'] or '?'} min/nuit "
            f"({row['avg_sleep_quality'] or '?'}/5)\n"
            f"- Séances d'entraînement : {row['sessions_week'] or 0}\n"
            f"- Calories moyennes : {row['avg_calories'] or '?'} kcal/j\n"
            f"- Protéines moyennes : {row['avg_protein'] or '?'} g/j\n"
            f"- Énergie moyenne (check-in matin) : {row['avg_energy'] or '?'}/5\n"
            f"- Stress moyen : {row['avg_stress'] or '?'}/5\n"
            f"- Patterns appris actifs : {row['active_patterns'] or 0}"
        )

        pattern_rows = await conn.fetch("""
            SELECT description_user, confidence, direction
            FROM user_patterns WHERE user_id = $1 AND active = true
            ORDER BY confidence DESC LIMIT 5
        """, user_id)

        if pattern_rows:
            summary += "\n\nPatterns identifiés :"
            for p in pattern_rows:
                summary += f"\n- {p['description_user']} (confiance: {p['confidence']:.0%})"

        return summary, first_name


async def _load_conversation_history(conversation_id: str) -> list[dict]:
    """Charge l'historique d'une conversation depuis la DB."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT role, content FROM messages
            WHERE conversation_id = $1
            ORDER BY created_at ASC LIMIT 20
        """, conversation_id)
        return [{"role": r["role"], "content": r["content"]} for r in rows]


async def _save_message(
    user_id: str,
    conversation_id: str,
    role: str,
    content: str,
    tokens: int = 0,
) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("""
            INSERT INTO messages (conversation_id, user_id, role, content, tokens_used)
            VALUES ($1, $2, $3, $4, $5)
        """, conversation_id, user_id, role, content, tokens)
        await conn.execute("""
            UPDATE conversations SET last_message_at = NOW()
            WHERE id = $1
        """, conversation_id)


async def handle_chat_message(
    user_id: str,
    message: str,
    conversation_id: Optional[str] = None,
) -> dict:
    """Traite un message utilisateur et retourne la réponse de VITA."""
    if not conversation_id:
        conversation_id = str(uuid.uuid4())
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                "INSERT INTO conversations (id, user_id) VALUES ($1, $2)",
                conversation_id, user_id
            )

    user_summary, first_name = await _load_user_summary(user_id)
    history = await _load_conversation_history(conversation_id)

    # Mémoires rule-based (court terme, check-ins/sleep/activity)
    memories = await load_memories(user_id, limit=8)
    memory_block = ""
    if memories:
        lines = "\n".join(f"- [{m['category']}] {m['content']}" for m in memories)
        memory_block = f"\n\n--- CE QUE VITA SE SOUVIENT DE CET UTILISATEUR ---\n{lines}"

    # Mémoires longue durée (IA, typées, avec retrieval hybride)
    # Dégradation gracieuse : si le retrieval échoue, la conversation continue sans mémoire longue durée
    try:
        long_memory_block = await retrieve_context_block(user_id, query=message, limit=12)
        if long_memory_block:
            long_memory_block = f"\n\n{long_memory_block}"
    except Exception:
        logger.warning("Long-term memory retrieval failed for user %s — continuing without", user_id)
        long_memory_block = ""

    system_with_context = (
        f"{SYSTEM_PROMPT}"
        f"\n\n--- DONNÉES ACTUELLES DE L'UTILISATEUR ---\n{user_summary}"
        f"{memory_block}"
        f"{long_memory_block}"
    )
    messages = history + [{"role": "user", "content": message}]

    # Haiku : même qualité pour des réponses courtes (3 phrases max), coût ~20× moindre
    try:
        response = await client.messages.create(
            model=settings.model_fast,
            max_tokens=settings.max_tokens_analysis,
            system=system_with_context,
            messages=messages,
        )
        assistant_content = response.content[0].text
        tokens_used = response.usage.input_tokens + response.usage.output_tokens

    except Exception as exc:
        if not _is_anthropic_unavailable(exc):
            raise

        # — Mode fallback local ——————————————————————————————————————————————
        # L'API Anthropic est indisponible (crédits insuffisants, surcharge, rate-limit).
        # On retourne une réponse locale honnête plutôt que de crasher la démo.
        # La conversation est quand même sauvegardée en DB pour la continuité.
        assistant_content = _fallback_message(first_name)
        tokens_used = 0
        logger.warning(
            "[VITA_FALLBACK] Anthropic unavailable — local fallback returned. "
            "user_id=%s conversation_id=%s error=%s",
            user_id, conversation_id, exc,
        )
        # ————————————————————————————————————————————————————————————————————

    await _save_message(user_id, conversation_id, "user", message)
    await _save_message(user_id, conversation_id, "assistant", assistant_content, tokens_used)

    # Consolidation longue durée (fire-and-forget, n'impacte pas la latence)
    asyncio.ensure_future(consolidate_from_interaction(
        user_id=user_id,
        text=message,
        source=MemorySource.CHAT,
        source_id=conversation_id,
    ))

    return {
        "conversation_id": conversation_id,
        "response": assistant_content,
        "tokens_used": tokens_used,
        "fallback": tokens_used == 0,  # indicateur pour le monitoring
    }
