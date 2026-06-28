import Foundation

// MARK: — Modèles

struct EncounterExchange: Identifiable, Equatable {
    let id = UUID()
    let role: ExchangeRole
    let content: String
    let topic: String?

    enum ExchangeRole {
        case vita
        case user
    }

    var isVita: Bool { role == .vita }
}

struct FirstEncounterSession: Codable {
    let status: String
    let topicIndex: Int?
    let exchangeCount: Int?
    let exchanges: [RawExchange]?
    let portrait: String?
    let completedAt: String?
    let alreadyStarted: Bool?
    let vitaOpening: String?
    let sessionId: String?

    struct RawExchange: Codable {
        let role: String
        let content: String
        let topic: String?
        let createdAt: String?
    }
}

struct FirstEncounterMessageResponse: Codable {
    let vitaResponse: String
    let topic: String
    let exchangeNumber: Int
    let isComplete: Bool
    let portrait: String?
}

struct FirstEncounterCorrectionResponse: Codable {
    let portrait: String
}

// MARK: — État de la vue

enum FirstEncounterState: Equatable {
    case loading
    case notStarted
    case conversation
    case waitingVita        // VITA est en train de répondre
    case portrait(String)   // Portrait généré
    case correcting         // Correction en cours
    case completed
    case error(String)
}

// MARK: — ViewModel

@MainActor
final class FirstEncounterViewModel: ObservableObject {
    @Published var state: FirstEncounterState = .loading
    @Published var exchanges: [EncounterExchange] = []
    @Published var exchangeCount: Int = 0
    @Published var portrait: String = ""
    @Published var correctionText: String = ""
    @Published var isSending: Bool = false

    // MARK: — Chargement initial

    func loadSession() async {
        guard case .loading = state else { return }
        do {
            let session: FirstEncounterSession = try await APIClient.shared.get("/first-encounter/session")
            _applySession(session)
        } catch {
            state = .notStarted
        }
    }

    // MARK: — Démarrage

    func start() async {
        state = .waitingVita
        do {
            let session: FirstEncounterSession = try await APIClient.shared.post(
                "/first-encounter/start",
                body: EmptyBody()
            )
            _applySession(session)
        } catch {
            state = .error("La rencontre n'a pas pu démarrer. Réessaie dans un instant.")
        }
    }

    // MARK: — Envoi d'un message

    func sendMessage(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        // Ajouter immédiatement la bulle utilisateur
        exchanges.append(EncounterExchange(role: .user, content: trimmed, topic: nil))
        exchangeCount += 1
        isSending = true
        state = .waitingVita

        do {
            let body = MessageBody(content: trimmed)
            let response: FirstEncounterMessageResponse = try await APIClient.shared.post(
                "/first-encounter/message",
                body: body
            )

            exchanges.append(EncounterExchange(role: .vita, content: response.vitaResponse, topic: response.topic))
            exchangeCount = response.exchangeNumber

            if response.isComplete, let portraitText = response.portrait {
                portrait = portraitText
                state = .portrait(portraitText)
            } else {
                state = .conversation
            }
        } catch {
            state = .error("La réponse de VITA n'est pas arrivée. Tu peux réessayer.")
        }

        isSending = false
    }

    // MARK: — Correction du portrait

    func sendCorrection() async {
        let trimmed = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        state = .correcting
        do {
            let body = CorrectionBody(correction: trimmed)
            let response: FirstEncounterCorrectionResponse = try await APIClient.shared.post(
                "/first-encounter/correct",
                body: body
            )
            portrait = response.portrait
            correctionText = ""
            state = .portrait(response.portrait)
        } catch {
            state = .portrait(portrait) // Revenir au portrait existant
        }
    }

    // MARK: — Validation du portrait

    func validatePortrait() {
        UserDefaults.standard.set(true, forKey: "vita.first_encounter.complete")
        NotificationCenter.default.post(name: .vitaFirstEncounterComplete, object: nil)
        state = .completed
    }

    // MARK: — Retry après erreur

    func retry() async {
        if exchanges.isEmpty {
            state = .loading
            await loadSession()
        } else {
            state = .conversation
        }
    }

    // MARK: — Indicateur discret d'avancement

    var progressLabel: String {
        let total = 10
        let current = min(exchangeCount, total)
        if current == 0 { return "Nous faisons connaissance" }
        return "Échange \(current) sur environ \(total)"
    }

    // MARK: — Privé

    private func _applySession(_ session: FirstEncounterSession) {
        switch session.status {
        case "not_started":
            state = .notStarted

        case "completed":
            if let p = session.portrait {
                portrait = p
                state = .portrait(p)
            } else {
                state = .completed
            }

        case "in_progress":
            if let rawExchanges = session.exchanges {
                exchanges = rawExchanges.map { raw in
                    EncounterExchange(
                        role: raw.role == "vita" ? .vita : .user,
                        content: raw.content,
                        topic: raw.topic
                    )
                }
            }
            exchangeCount = session.exchangeCount ?? 0

            // Si la session vient d'être créée, le message d'ouverture arrive ici
            if let opening = session.vitaOpening, !opening.isEmpty {
                exchanges = [EncounterExchange(role: .vita, content: opening, topic: "situation_actuelle")]
            }
            state = .conversation

        default:
            // already_started avec état in_progress
            if let rawExchanges = session.exchanges {
                exchanges = rawExchanges.map { raw in
                    EncounterExchange(
                        role: raw.role == "vita" ? .vita : .user,
                        content: raw.content,
                        topic: raw.topic
                    )
                }
            }
            if let opening = session.vitaOpening {
                exchanges = [EncounterExchange(role: .vita, content: opening, topic: "situation_actuelle")]
            }
            exchangeCount = session.exchangeCount ?? 0
            state = .conversation
        }
    }
}

// MARK: — Notifications

extension Notification.Name {
    static let vitaFirstEncounterComplete = Notification.Name("vita.first_encounter.complete")
}

// MARK: — Corps de requêtes

private struct MessageBody: Encodable {
    let content: String
}

private struct CorrectionBody: Encodable {
    let correction: String
}
