import Foundation
import SwiftUI

@MainActor
final class MorningCheckInViewModel: ObservableObject {
    // Navigation
    @Published var currentStep = 1
    @Published var showThinking = false

    // Réponses utilisateur
    @Published var sleepQuality = 3
    @Published var energyLevel = 3
    @Published var hasPain = false
    @Published var painAreas: [String] = []

    // État de la soumission
    @Published var isSubmitting = false
    @Published var submitError: String?
    @Published var alreadyCheckedIn = false

    // État SSE
    @Published var thinkingMessages: [String] = []
    @Published var recommendation: DailyRecommendation?
    @Published var hasRecommendationError = false

    private let sseClient = VitaSSEClient()

    func nextStep() {
        guard currentStep < 3 else { return }
        currentStep += 1
    }

    func previousStep() {
        guard currentStep > 1 else { return }
        currentStep -= 1
    }

    func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil

        // 1. Ouvrir la connexion SSE AVANT de soumettre pour ne pas manquer
        //    les premiers événements thinking émis dès la réception du check-in.
        sseClient.connect(to: "/dashboard/events")
        observeSSEEvents()

        // 2. Naviguer vers l'écran de raisonnement immédiatement
        showThinking = true

        // 3. Soumettre le check-in — le serveur répond 201 instantanément
        let body = MorningCheckInBody(
            energy: energyLevel,
            mood: 3,
            stress: 3,
            painAreas: hasPain ? painAreas : [],
            painIntensity: hasPain ? 5 : 0,
            durationSec: nil
        )

        do {
            let _: CheckInResponse = try await APIClient.shared.post("/checkin/morning", body: body)
        } catch APIError.conflict {
            // 409 : check-in déjà effectué aujourd'hui — pas une erreur technique
            sseClient.disconnect()
            showThinking = false
            alreadyCheckedIn = true
        } catch {
            sseClient.disconnect()
            showThinking = false
            submitError = "Le check-in n'a pas pu être enregistré. Réessaie."
        }

        isSubmitting = false
    }

    // Chargement de secours si la connexion SSE était absente ou a échoué
    func loadFallbackRecommendation() async {
        do {
            struct FallbackResponse: Decodable {
                let ready: Bool
                let content: String?
                let actionType: String?
                let agentSource: String?
                let actions: [String]?
            }
            let resp: FallbackResponse = try await APIClient.shared.get("/dashboard/recommendation")
            if resp.ready, let content = resp.content {
                recommendation = DailyRecommendation(
                    content: content,
                    contentShort: nil,
                    actionType: resp.actionType ?? "do",
                    agentSource: resp.agentSource ?? "vita",
                    confidence: 0.8,
                    date: isoToday(),
                    actions: resp.actions ?? []
                )
            } else {
                try await Task.sleep(for: .seconds(3))
                let retry: FallbackResponse = try await APIClient.shared.get("/dashboard/recommendation")
                if retry.ready, let content = retry.content {
                    recommendation = DailyRecommendation(
                        content: content,
                        contentShort: nil,
                        actionType: retry.actionType ?? "do",
                        agentSource: retry.agentSource ?? "vita",
                        confidence: 0.8,
                        date: isoToday(),
                        actions: retry.actions ?? []
                    )
                } else {
                    hasRecommendationError = true
                }
            }
        } catch {
            hasRecommendationError = true
        }
    }

    // Appelé quand l'utilisateur choisit "Voir ma recommandation" après un 409.
    // Navigue vers VitaThinkingView et charge la reco existante via l'API REST.
    func showExistingRecommendation() {
        alreadyCheckedIn = false
        showThinking = true
        Task { await loadFallbackRecommendation() }
    }

    func disconnectSSE() {
        sseClient.disconnect()
    }

    // MARK: — Observation des événements SSE

    private func observeSSEEvents() {
        Task { [weak self] in
            // Surveiller lastEvent via une boucle — évite de dépendre de Combine
            var seen: VitaSSEEvent?
            while let self, !Task.isCancelled {
                let current = await self.sseClient.lastEvent
                if current != seen {
                    seen = current
                    if let event = current {
                        await self.handleSSEEvent(event)
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func handleSSEEvent(_ event: VitaSSEEvent) {
        switch event {
        case .thinking(let message):
            withAnimation(.vitaDefault) {
                thinkingMessages.append(message)
            }
        case .recommendation(let content, let actionType, let agentSource, let actions):
            sseClient.disconnect()
            withAnimation(.vitaDefault) {
                recommendation = DailyRecommendation(
                    content: content,
                    contentShort: nil,
                    actionType: actionType,
                    agentSource: agentSource,
                    confidence: 0.85,
                    date: isoToday(),
                    actions: actions
                )
            }
        case .error:
            sseClient.disconnect()
            Task { await loadFallbackRecommendation() }
        }
    }

    private func isoToday() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: — Modèles réseau

struct MorningCheckInBody: Encodable {
    let energy: Int
    let mood: Int
    let stress: Int
    let painAreas: [String]
    let painIntensity: Int
    let durationSec: Int?
}

struct CheckInResponse: Codable {
    let id: String
    let date: String
}

struct DailyRecommendation: Codable, Identifiable {
    var id: String { date }
    let content: String
    let contentShort: String?
    let actionType: String
    let agentSource: String
    let confidence: Double
    let date: String
    let actions: [String]

    // init explicite pour les sites de construction (SSE, fallback REST)
    init(content: String, contentShort: String?, actionType: String,
         agentSource: String, confidence: Double, date: String, actions: [String] = []) {
        self.content = content
        self.contentShort = contentShort
        self.actionType = actionType
        self.agentSource = agentSource
        self.confidence = confidence
        self.date = date
        self.actions = actions
    }

    // Décodage défensif : actions absentes (anciennes recos) → tableau vide
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content      = try c.decode(String.self,   forKey: .content)
        contentShort = try c.decodeIfPresent(String.self, forKey: .contentShort)
        actionType   = try c.decode(String.self,   forKey: .actionType)
        agentSource  = try c.decode(String.self,   forKey: .agentSource)
        confidence   = try c.decode(Double.self,   forKey: .confidence)
        date         = try c.decode(String.self,   forKey: .date)
        actions      = (try? c.decodeIfPresent([String].self, forKey: .actions)) ?? []
    }
}
