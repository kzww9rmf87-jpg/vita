import Foundation
import SwiftUI

// MARK: — Modèles réseau

struct DiscoveryExchangeData: Codable {
    let role: String   // "vita" | "user"
    let content: String
}

struct DiscoverySynthesisData: Codable {
    var rapportAuSport:      String?
    var motivations:         [String]
    var freins:              [String]
    var experiencesPositives:[String]
    var experiencesNegatives:[String]
    var contextePrefer:      [String]
    var contraintes:         [String]
    var personnalite:        String?
    var resumeValide:        String?
}

struct ActivityProposalData: Codable, Identifiable {
    var id: String { name }
    let name:            String
    let whyItFits:       String
    let firstStep:       String
    let frequency:       String
    let constraintLevel: String
}

struct DiscoveryStartResponse: Codable {
    let alreadyStarted: Bool
    let sessionId:      String?
    let vitaOpening:    String?
    let status:         String?
    let exchanges:      [DiscoveryExchangeData]?
    let synthesis:      DiscoverySynthesisData?
    let proposals:      [ActivityProposalData]?
}

struct DiscoveryMessageResponse: Codable {
    let vitaResponse: String
    let newStatus:    String
    let synthesis:    DiscoverySynthesisData?
    let proposals:    [ActivityProposalData]?
}

struct DiscoveryReactResponse: Codable {
    let vitaResponse: String
    let newProposals: [ActivityProposalData]
    let isComplete:   Bool
}

// MARK: — ViewModel

@MainActor
final class SportDiscoveryViewModel: ObservableObject {

    enum Phase: Equatable {
        case discovering
        case reformulating
        case proposing
        case completed
    }

    @Published var phase: Phase           = .discovering
    @Published var exchanges: [DiscoveryExchangeData] = []
    @Published var synthesis: DiscoverySynthesisData?  = nil
    @Published var proposals: [ActivityProposalData]   = []
    @Published var acceptedNames: Set<String>          = []
    @Published var refusedNames:  Set<String>          = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isComplete = false

    private var sessionId: String?
    private let client = APIClient.shared

    // MARK: — Start

    func start() async {
        guard exchanges.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let res: DiscoveryStartResponse = try await client.post(
                "/sport/discovery/start",
                body: EmptyResponse()
            )
            sessionId = res.sessionId

            if res.alreadyStarted, let existing = res.exchanges {
                exchanges = existing
                phase = phaseFrom(res.status)
                synthesis = res.synthesis
                proposals = res.proposals ?? []
            } else if let opening = res.vitaOpening {
                exchanges = [DiscoveryExchangeData(role: "vita", content: opening)]
                phase = .discovering
            }
        } catch {
            errorMessage = "Impossible de démarrer la découverte. Réessaie dans un instant."
        }
    }

    // MARK: — Send message

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let currentExchanges = exchanges
        // Ajoute immédiatement le message utilisateur pour une réponse UI rapide
        exchanges.append(DiscoveryExchangeData(role: "user", content: text))

        struct MessageBody: Encodable {
            let user_message: String
            let exchanges: [DiscoveryExchangeData]
            let status: String
        }

        do {
            let res: DiscoveryMessageResponse = try await client.post(
                "/sport/discovery/message",
                body: MessageBody(
                    user_message: text,
                    exchanges:    currentExchanges,
                    status:       phaseToString(phase)
                )
            )
            exchanges.append(DiscoveryExchangeData(role: "vita", content: res.vitaResponse))
            phase = phaseFrom(res.newStatus)
            if let synth = res.synthesis {
                synthesis = synth
            }
            if !(res.proposals ?? []).isEmpty {
                proposals = res.proposals!
            }
        } catch {
            // Retire le message utilisateur optimiste si erreur
            exchanges = currentExchanges
            errorMessage = "Une erreur est survenue. Réessaie."
        }
    }

    // MARK: — Confirm synthesis

    func confirmSynthesis() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct ConfirmBody: Encodable {
            let synthesis: DiscoverySynthesisData?
            let exchanges: [DiscoveryExchangeData]
        }

        do {
            let res: DiscoveryMessageResponse = try await client.post(
                "/sport/discovery/confirm",
                body: ConfirmBody(synthesis: synthesis, exchanges: exchanges)
            )
            exchanges.append(DiscoveryExchangeData(role: "vita", content: res.vitaResponse))
            phase = .proposing
            proposals = res.proposals ?? []
        } catch {
            errorMessage = "Une erreur est survenue. Réessaie."
        }
    }

    // MARK: — React to proposals

    func react() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct ReactBody: Encodable {
            let proposals:      [ActivityProposalData]
            let accepted_names: [String]
            let refused_names:  [String]
            let synthesis:      DiscoverySynthesisData?
        }

        do {
            let res: DiscoveryReactResponse = try await client.post(
                "/sport/discovery/react",
                body: ReactBody(
                    proposals:      proposals,
                    accepted_names: Array(acceptedNames),
                    refused_names:  Array(refusedNames),
                    synthesis:      synthesis
                )
            )
            if res.isComplete {
                exchanges.append(DiscoveryExchangeData(role: "vita", content: res.vitaResponse))
                phase = .completed
                isComplete = true
            } else {
                exchanges.append(DiscoveryExchangeData(role: "vita", content: res.vitaResponse))
                proposals = res.newProposals
                acceptedNames = []
                refusedNames  = []
            }
        } catch {
            errorMessage = "Une erreur est survenue. Réessaie."
        }
    }

    // MARK: — Helpers

    func toggleAccepted(_ name: String) {
        if acceptedNames.contains(name) {
            acceptedNames.remove(name)
        } else {
            acceptedNames.insert(name)
            refusedNames.remove(name)
        }
    }

    func toggleRefused(_ name: String) {
        if refusedNames.contains(name) {
            refusedNames.remove(name)
        } else {
            refusedNames.insert(name)
            acceptedNames.remove(name)
        }
    }

    private func phaseFrom(_ status: String?) -> Phase {
        switch status {
        case "reformulating": return .reformulating
        case "proposing":     return .proposing
        case "completed":     return .completed
        default:              return .discovering
        }
    }

    private func phaseToString(_ phase: Phase) -> String {
        switch phase {
        case .discovering:    return "discovering"
        case .reformulating:  return "reformulating"
        case .proposing:      return "proposing"
        case .completed:      return "completed"
        }
    }
}
