"""
Memory Retrieval — injecte les mémoires longue durée dans le contexte AI.

Appelé avant chaque réponse Claude (chat, journal, recommandations).

Format de sortie : bloc texte compact destiné à être inséré dans le system prompt.
Exemple :
  [VITA connaît cet utilisateur]
  • (goal, ★★★★) Veut courir un semi-marathon d'ici octobre
  • (family, ★★★) A une relation compliquée avec son père
  • (work, ★★) Travaille comme graphiste freelance

Si aucune mémoire pertinente, retourne une chaîne vide.
"""
from __future__ import annotations

from .postgres_provider import PostgresMemoryProvider

_provider = PostgresMemoryProvider()

_IMPORTANCE_STARS = {1: "★", 2: "★★", 3: "★★★", 4: "★★★★", 5: "★★★★★"}


async def retrieve_context_block(
    user_id: str,
    query: str = "",
    limit: int = 15,
) -> str:
    """
    Retourne un bloc texte prêt à être injecté dans un system prompt.

    `query` est le dernier message de l'utilisateur — utilisé pour pondérer
    la similarité keyword. Peut être vide (ex : première ouverture du chat).
    """
    memories = await _provider.retrieve_for_context(user_id, query=query, limit=limit)
    if not memories:
        return ""

    # Garde de sécurité : jamais plus de `limit` mémoires dans le prompt, même si le provider en retourne plus
    memories = memories[:limit]

    lines = ["[VITA connaît cet utilisateur]"]
    for mem in memories:
        stars = _IMPORTANCE_STARS.get(mem.importance, "★★★")
        lines.append(f"• ({mem.type.value}, {stars}) {mem.summary}")

    return "\n".join(lines)
