import Foundation

// MARK: — Modèle

struct WeeklyReflection: Codable, Identifiable {
    let id: String
    let content: String
    let periodStart: String   // "YYYY-MM-DD"
    let periodEnd: String
    let themes: [String]
    let question: String?
    let createdAt: Date?

    var formattedPeriod: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "fr_FR")
        let display = DateFormatter()
        display.dateFormat = "d MMM"
        display.locale = Locale(identifier: "fr_FR")
        guard let s = fmt.date(from: periodStart), let e = fmt.date(from: periodEnd) else {
            return "\(periodStart) – \(periodEnd)"
        }
        return "\(display.string(from: s)) – \(display.string(from: e))"
    }
}

// Réponse polymorphe : { available: bool, ...champs optionnels }
private struct ReflectionResponse: Codable {
    let available: Bool
    let id: String?
    let content: String?
    let periodStart: String?
    let periodEnd: String?
    let themes: [String]?
    let question: String?
    let createdAt: Date?

    var reflection: WeeklyReflection? {
        guard available,
              let id, let content,
              let periodStart, let periodEnd else { return nil }
        return WeeklyReflection(
            id: id,
            content: content,
            periodStart: periodStart,
            periodEnd: periodEnd,
            themes: themes ?? [],
            question: question,
            createdAt: createdAt
        )
    }
}

// MARK: — État

enum ReflectionState {
    case idle
    case loading
    case available(WeeklyReflection)
    case notReady       // données insuffisantes cette semaine
    case generating
    case error(String)
}

// MARK: — ViewModel

@MainActor
final class ReflectionViewModel: ObservableObject {
    @Published var state: ReflectionState = .idle

    func load() async {
        state = .loading
        do {
            let response: ReflectionResponse = try await APIClient.shared.get("/reflection/weekly")
            state = response.reflection.map { .available($0) } ?? .notReady
        } catch {
            state = .error("Impossible de charger ta réflexion.")
        }
    }

    func generate() async {
        state = .generating
        do {
            let response: ReflectionResponse = try await APIClient.shared.post(
                "/reflection/weekly",
                body: EmptyRequestBody()
            )
            if let reflection = response.reflection {
                state = .available(reflection)
            } else {
                state = .error("Pas encore assez d'éléments cette semaine pour générer une réflexion.")
            }
        } catch {
            state = .error("La génération a échoué. Réessaie un peu plus tard.")
        }
    }
}

// Corps vide pour POST sans payload
private struct EmptyRequestBody: Encodable {}
