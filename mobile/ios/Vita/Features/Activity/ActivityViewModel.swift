import Foundation

// MARK: — Modèles

struct ActivitySession: Identifiable, Codable, Equatable {
    let id: String
    let date: String
    let activityName: String
    let durationMinutes: Int?
    let caloriesBurned: Int?
    let hrAvgBpm: Int?
    let rpe: Int?
    let distanceMeters: Int?
    let steps: Int?
    let source: String?
    let createdAt: String?
}

struct ActivitySessionCreate: Encodable {
    let date: String
    let activityName: String
    let durationMinutes: Int?
    let caloriesBurned: Int?
    let rpe: Int?
    let distanceMeters: Int?
    let steps: Int?
    let notes: String?
}

// MARK: — ViewModel

@MainActor
final class ActivityViewModel: ObservableObject {

    @Published var sessions: [ActivitySession] = []
    @Published var isLoading = false
    @Published var isSaving  = false
    @Published var errorMessage: String?

    // Formulaire de saisie rapide
    @Published var formDate       = Calendar.current.startOfDay(for: Date())
    @Published var formName       = ""
    @Published var formDuration   = 45
    @Published var formRpe: Int   = 6
    @Published var formCalories: Int = 0
    @Published var formDistance   = 0
    @Published var formNotes      = ""

    // Noms d'activités fréquents — suggestions
    let quickActivities = [
        "Marche", "Course", "Vélo", "Natation",
        "Musculation", "Yoga", "HIIT", "Étirements",
    ]

    // MARK: — Chargement

    func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result: [ActivitySession] = try await APIClient.shared.get("/activity/history?days=30")
            sessions = result
        } catch {
            errorMessage = "Impossible de charger l'historique."
        }
    }

    // MARK: — Création

    func save() async -> Bool {
        let trimmed = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let dateStr = ISO8601DateFormatter.vitaDate.string(from: formDate)
        let body = ActivitySessionCreate(
            date: dateStr,
            activityName: trimmed,
            durationMinutes: formDuration > 0 ? formDuration : nil,
            caloriesBurned: formCalories > 0 ? formCalories : nil,
            rpe: formRpe,
            distanceMeters: formDistance > 0 ? formDistance : nil,
            steps: nil,
            notes: formNotes.isEmpty ? nil : formNotes
        )
        do {
            let _: [String: String] = try await APIClient.shared.post("/activity", body: body)
            await loadHistory()
            resetForm()
            return true
        } catch {
            errorMessage = "L'enregistrement a échoué."
            return false
        }
    }

    // MARK: — Suppression

    func delete(_ session: ActivitySession) async {
        do {
            try await APIClient.shared.delete("/activity/\(session.id)")
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = "Impossible de supprimer cette session."
        }
    }

    // MARK: — Utilitaires

    func resetForm() {
        formDate     = Calendar.current.startOfDay(for: Date())
        formName     = ""
        formDuration = 45
        formRpe      = 6
        formCalories = 0
        formDistance = 0
        formNotes    = ""
    }

    func durationLabel(_ minutes: Int?) -> String {
        guard let m = minutes else { return "—" }
        if m < 60 { return "\(m) min" }
        let h = m / 60; let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h\(rem)"
    }

    var weekSessionCount: Int { sessions.filter { isThisWeek($0.date) }.count }

    private func isThisWeek(_ dateStr: String) -> Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: dateStr) else { return false }
        return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
    }
}

private extension ISO8601DateFormatter {
    static let vitaDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
