import Foundation

// MARK: — Modèles

struct SportProfileData: Codable {
    var fitnessLevel: String
    var preferredActivities: [String]
    var sessionsPerWeek: Int
    var sessionDurationMin: Int
    var availableDays: [Int]
    var context: String?
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

@MainActor
final class SportProfileViewModel: ObservableObject {

    @Published var profile: SportProfileData?
    @Published var isLoading = false
    @Published var isSaving  = false
    @Published var errorMessage: String?
    @Published var savedSuccessfully = false

    // Formulaire
    @Published var formLevel       = "beginner"
    @Published var formActivities: [String] = []
    @Published var formSessions    = 3
    @Published var formDuration    = 45
    @Published var formDays: [Int] = [1, 3, 5]
    @Published var formContext     = ""

    let fitnessLevels: [(id: String, label: String)] = [
        ("beginner",     "Débutant"),
        ("intermediate", "Intermédiaire"),
        ("advanced",     "Avancé"),
        ("elite",        "Élite"),
    ]

    let dayNames = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]

    let suggestedActivities = [
        "Musculation", "Course", "Vélo", "Natation",
        "HIIT", "Yoga", "Boxe", "Marche", "Mobilité",
    ]

    // MARK: — Chargement

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data: SportProfileData = try await APIClient.shared.get("/sport/profile")
            profile = data
            populateForm(from: data)
        } catch {
            // 404 = pas encore de profil → formulaire vide avec défauts
        }
    }

    // MARK: — Sauvegarde

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let body = SportProfileData(
            fitnessLevel:        formLevel,
            preferredActivities: formActivities,
            sessionsPerWeek:     formSessions,
            sessionDurationMin:  formDuration,
            availableDays:       formDays,
            context:             formContext.isEmpty ? nil : formContext
        )

        do {
            let _: [String: String] = try await APIClient.shared.put("/sport/profile", body: body)
            profile = body
            savedSuccessfully = true
        } catch {
            errorMessage = "La sauvegarde a échoué."
        }
    }

    // MARK: — Utilitaires

    func toggleDay(_ day: Int) {
        if formDays.contains(day) {
            formDays.removeAll { $0 == day }
        } else {
            formDays.append(day)
            formDays.sort()
        }
    }

    func toggleActivity(_ name: String) {
        if formActivities.contains(name) {
            formActivities.removeAll { $0 == name }
        } else {
            formActivities.append(name)
        }
    }

    func levelLabel(_ id: String) -> String {
        fitnessLevels.first { $0.id == id }?.label ?? id
    }

    private func populateForm(from data: SportProfileData) {
        formLevel       = data.fitnessLevel
        formActivities  = data.preferredActivities
        formSessions    = data.sessionsPerWeek
        formDuration    = data.sessionDurationMin
        formDays        = data.availableDays
        formContext     = data.context ?? ""
    }
}
