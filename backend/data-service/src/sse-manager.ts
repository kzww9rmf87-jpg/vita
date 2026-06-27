// Registre des connexions SSE actives, indexé par userId.
//
// Pourquoi SSE plutôt que WebSocket :
// - Unidirectionnel (serveur → client) : exactement ce dont VITA a besoin
// - HTTP natif : traverse Nginx sans configuration d'upgrade de protocole
// - Reconnexion automatique intégrée dans le protocole
// - Beaucoup plus simple à maintenir sur le long terme
//
// Limite connue : ce registre est en mémoire. Si le service est
// multi-instances, les connexions ne seront pas partagées entre instances.
// Pour le MVP (instance unique), c'est délibérément suffisant.

import type { ServerResponse } from 'node:http'

const connections = new Map<string, Set<ServerResponse>>()

export function registerConnection(userId: string, res: ServerResponse): void {
  if (!connections.has(userId)) {
    connections.set(userId, new Set())
  }
  connections.get(userId)!.add(res)
}

export function unregisterConnection(userId: string, res: ServerResponse): void {
  const userConnections = connections.get(userId)
  if (!userConnections) return
  userConnections.delete(res)
  if (userConnections.size === 0) {
    connections.delete(userId)
  }
}

// Envoie un événement SSE à toutes les connexions actives d'un utilisateur.
// Retourne true si au moins une connexion a reçu l'événement.
export function sendEvent(
  userId: string,
  eventName: string,
  data: Record<string, unknown>
): boolean {
  const userConnections = connections.get(userId)
  if (!userConnections || userConnections.size === 0) return false

  const payload = `event: ${eventName}\ndata: ${JSON.stringify(data)}\n\n`

  for (const res of userConnections) {
    try {
      res.write(payload)
    } catch {
      // La connexion est fermée côté client — on la nettoie silencieusement
      userConnections.delete(res)
    }
  }
  return true
}

export function hasConnection(userId: string): boolean {
  return (connections.get(userId)?.size ?? 0) > 0
}

// Uniquement pour les tests — ne pas appeler en production
export function _clearAll(): void {
  connections.clear()
}
