import Foundation
import Combine

// MARK: — Modèles

struct JournalEntry: Decodable, Identifiable {
    let id: String
    let content: String
    let moodLabel: String?
    let emotionalTone: String?
    let themes: [String]?
    let intensity: Int?
    let vitaResponse: String?
    let isPrivate: Bool
    let createdAt: String

    var displayDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: createdAt) ?? isoBasic.date(from: createdAt) else {
            return createdAt
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM 'à' HH:mm"
        return f.string(from: date)
    }

    var moodIcon: String {
        switch moodLabel {
        case "joie":        return "sun.max.fill"
        case "fierté":      return "star.fill"
        case "tristesse":   return "cloud.rain.fill"
        case "anxiété":     return "wind"
        case "colère":      return "flame.fill"
        case "fatigue":     return "moon.zzz.fill"
        case "ambivalence": return "arrow.left.arrow.right"
        default:            return "circle.fill"
        }
    }

    var moodColor: String {
        switch moodLabel {
        case "joie", "fierté":  return "activity"   // orange/jaune
        case "tristesse":       return "sleep"       // indigo
        case "anxiété":         return "purple"
        case "colère":          return "activity"
        case "fatigue":         return "sleep"
        default:                return "accent"
        }
    }
}

struct JournalEntryResponse: Decodable {
    let id: String
    let vitaResponse: String?
    let moodLabel: String?
    let themes: [String]
}

private struct NewEntryBody: Encodable {
    let content: String
    let isPrivate: Bool
}

struct EmotionalMemory: Decodable, Identifiable {
    let id: String
    let theme: String
    let summary: String?
    let valence: Double?
    let recurrenceCount: Int
    let lastSeenAt: String
    let confidence: Double
}

// MARK: — ViewModel

@MainActor
final class JournalViewModel: ObservableObject {

    // État principal
    @Published var entries: [JournalEntry] = []
    @Published var memories: [EmotionalMemory] = []
    @Published var isLoading = false
    @Published var isSending = false

    // Composition
    @Published var draftText = ""
    @Published var showingNewEntry = false

    // Retour VITA après soumission
    @Published var vitaResponse: String?
    @Published var showingVitaResponse = false

    // Erreur UI
    @Published var errorMessage: String?

    var canSubmit: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: — Chargement

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let entriesTask: [JournalEntry] = APIClient.shared.get("/journal/recent", queryParams: ["limit": "20"])
        async let memoriesTask: [EmotionalMemory] = APIClient.shared.get("/journal/memories")
        do {
            let (e, m) = try await (entriesTask, memoriesTask)
            entries = e
            memories = m
        } catch {
            errorMessage = "Impossible de charger le journal."
        }
    }

    // MARK: — Soumission

    func submitEntry() async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        isSending = true
        defer { isSending = false }

        do {
            let response: JournalEntryResponse = try await APIClient.shared.post(
                "/journal/entry",
                body: NewEntryBody(content: trimmed, isPrivate: false)
            )
            draftText = ""
            showingNewEntry = false
            vitaResponse = response.vitaResponse
            showingVitaResponse = response.vitaResponse != nil
            await load()
        } catch {
            errorMessage = "Impossible de sauvegarder l'entrée."
        }
    }
}
