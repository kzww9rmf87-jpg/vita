import Foundation

// MARK: — Modèles

/// Ensemble limité des climates — miroir exact du backend.
/// Jamais étendu sans mise à jour simultanée de l'AI Engine.
enum InsightClimate: String, CaseIterable {
    case calm         = "CALM"
    case constructive = "CONSTRUCTIVE"
    case demanding    = "DEMANDING"
    case recovery     = "RECOVERY"
    case uncertain    = "UNCERTAIN"
    case energized    = "ENERGIZED"
    case reflective   = "REFLECTIVE"
    case transition   = "TRANSITION"
    case balanced     = "BALANCED"

    /// Label français affiché à l'utilisateur — jamais le nom technique.
    var label: String {
        switch self {
        case .calm:         return "Calme"
        case .constructive: return "Constructive"
        case .demanding:    return "Exigeante"
        case .recovery:     return "Récupération"
        case .uncertain:    return "Incertaine"
        case .energized:    return "Dynamisée"
        case .reflective:   return "Réflexive"
        case .transition:   return "En transition"
        case .balanced:     return "Équilibrée"
        }
    }

    /// SF Symbol accompagnant le climat — toujours évocateur, jamais évaluatif.
    var icon: String {
        switch self {
        case .calm:         return "cloud.fill"
        case .constructive: return "leaf.fill"
        case .demanding:    return "bolt.fill"
        case .recovery:     return "moon.fill"
        case .uncertain:    return "wind"
        case .energized:    return "sun.max.fill"
        case .reflective:   return "sparkles"
        case .transition:   return "arrow.triangle.turn.up.right.circle.fill"
        case .balanced:     return "circle.grid.2x2.fill"
        }
    }
}

struct DailyInsight: Codable, Identifiable {
    let id: String
    let date: String
    let climate: String
    let summary: String
    let drivers: [String]
    let reflection: String
    let question: String
    let createdAt: String?

    /// Climate typé — fallback sur .balanced si valeur inconnue.
    var typedClimate: InsightClimate {
        InsightClimate(rawValue: climate) ?? .balanced
    }
}

private struct InsightResponse: Codable {
    let available: Bool
    let id: String?
    let date: String?
    let climate: String?
    let summary: String?
    let drivers: [String]?
    let reflection: String?
    let question: String?
    let createdAt: String?

    var insight: DailyInsight? {
        guard available,
              let id, let date, let climate,
              let summary, let reflection, let question
        else { return nil }
        return DailyInsight(
            id: id,
            date: date,
            climate: climate,
            summary: summary,
            drivers: drivers ?? [],
            reflection: reflection,
            question: question,
            createdAt: createdAt
        )
    }
}

// MARK: — États

enum DailyInsightState {
    case idle
    case loading
    case available(DailyInsight)
    case notGenerated
    case generating
    case error(String)
}

// MARK: — ViewModel

@MainActor
final class DailyInsightViewModel: ObservableObject {
    @Published var state: DailyInsightState = .idle

    private let targetDate: String

    init(date: String? = nil) {
        if let date {
            targetDate = date
        } else {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            targetDate = f.string(from: Date())
        }
    }

    func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let response: InsightResponse = try await APIClient.shared.get(
                "/daily-insight/\(targetDate)"
            )
            if let insight = response.insight {
                state = .available(insight)
            } else {
                state = .notGenerated
            }
        } catch {
            state = .error("Synthèse du jour indisponible.")
        }
    }

    func generate() async {
        state = .generating
        do {
            let body = GenerateBody(date: targetDate)
            let response: InsightResponse = try await APIClient.shared.post(
                "/daily-insight/generate",
                body: body
            )
            if let insight = response.insight {
                state = .available(insight)
            } else {
                state = .notGenerated
            }
        } catch {
            state = .error("La synthèse n'a pas pu être générée.")
        }
    }

    func reload() async {
        state = .idle
        await load()
    }
}

private struct GenerateBody: Encodable {
    let date: String
}
