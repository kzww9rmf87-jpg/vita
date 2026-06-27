import Foundation

// MARK: — Événements reçus par l'app via SSE

enum VitaSSEEvent: Equatable {
    case thinking(message: String)
    case recommendation(content: String, actionType: String, agentSource: String)
    case error(code: String)
}

// MARK: — Décodeurs JSON des payloads SSE

private struct ThinkingPayload: Decodable {
    let message: String
}

private struct RecommendationPayload: Decodable {
    let content: String
    let actionType: String
    let agentSource: String
}

private struct ErrorPayload: Decodable {
    let code: String
}

// MARK: — Client SSE

@MainActor
final class VitaSSEClient: ObservableObject {
    @Published private(set) var lastEvent: VitaSSEEvent?
    @Published private(set) var isConnected = false

    private var streamTask: Task<Void, Never>?

    // Ouvre la connexion SSE. Idempotent : annule la précédente si elle existe.
    func connect(to path: String) {
        disconnect()
        streamTask = Task { [weak self] in
            await self?.stream(path: path)
        }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    // MARK: — Streaming

    private func stream(path: String) async {
        guard let request = await APIClient.shared.sseRequest(path: path) else { return }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            isConnected = true

            var eventName = ""
            var dataLine = ""

            for try await line in bytes.lines {
                if Task.isCancelled { break }

                if line.hasPrefix("event: ") {
                    eventName = String(line.dropFirst(7))
                } else if line.hasPrefix("data: ") {
                    dataLine = String(line.dropFirst(6))
                } else if line.isEmpty, !eventName.isEmpty, !dataLine.isEmpty {
                    // Bloc SSE complet — parser et publier
                    parseAndPublish(eventName: eventName, data: dataLine)
                    eventName = ""
                    dataLine = ""
                }
                // Lignes commençant par ':' = keep-alive / commentaires — ignorées
            }
        } catch {
            guard !Task.isCancelled else { return }
            // Reconnexion automatique après 3 secondes si la connexion est perdue
            isConnected = false
            try? await Task.sleep(for: .seconds(3))
            await stream(path: path)
        }
    }

    // MARK: — Parsing

    private func parseAndPublish(eventName: String, data: String) {
        guard let raw = data.data(using: .utf8) else { return }

        switch eventName {
        case "thinking":
            if let payload = try? JSONDecoder.vita.decode(ThinkingPayload.self, from: raw) {
                lastEvent = .thinking(message: payload.message)
            }
        case "recommendation":
            if let payload = try? JSONDecoder.vita.decode(RecommendationPayload.self, from: raw) {
                lastEvent = .recommendation(
                    content: payload.content,
                    actionType: payload.actionType,
                    agentSource: payload.agentSource
                )
            }
        case "error":
            if let payload = try? JSONDecoder.vita.decode(ErrorPayload.self, from: raw) {
                lastEvent = .error(code: payload.code)
            }
        default:
            break
        }
    }
}
