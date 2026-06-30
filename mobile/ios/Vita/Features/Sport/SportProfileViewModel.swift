import Foundation

// MARK: — Modèles

struct SportProfileData: Codable {
    var fitnessLevel: String
    var preferredActivities: [String]
    var sessionsPerWeek: Int
    var sessionDurationMin: Int
    var availableDays: [Int]
    var context: String?
    // Sprint 12.2 — préférences découverte
    var motivation: String?
    var attractiveActivities: [String]
    var rejectedActivities: [String]
    var preferredContext: [String]
    var apprehensionLevel: String
    var realisticTimeMin: Int?

    init(
        fitnessLevel: String = "beginner",
        preferredActivities: [String] = [],
        sessionsPerWeek: Int = 3,
        sessionDurationMin: Int = 45,
        availableDays: [Int] = [1, 3, 5],
        context: String? = nil,
        motivation: String? = nil,
        attractiveActivities: [String] = [],
        rejectedActivities: [String] = [],
        preferredContext: [String] = [],
        apprehensionLevel: String = "aucune",
        realisticTimeMin: Int? = nil
    ) {
        self.fitnessLevel         = fitnessLevel
        self.preferredActivities  = preferredActivities
        self.sessionsPerWeek      = sessionsPerWeek
        self.sessionDurationMin   = sessionDurationMin
        self.availableDays        = availableDays
        self.context              = context
        self.motivation           = motivation
        self.attractiveActivities = attractiveActivities
        self.rejectedActivities   = rejectedActivities
        self.preferredContext     = preferredContext
        self.apprehensionLevel    = apprehensionLevel
        self.realisticTimeMin     = realisticTimeMin
    }
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

@MainActor
final class SportProfileViewModel: ObservableObject {

    @Published var profile: SportProfileData?
    @Published var isLoading = false
    @Published var isSaving  = false
    @Published var errorMessage: String?
    @Published var savedSuccessfully = false

    // Formulaire — champs existants
    @Published var formLevel       = "beginner"
    @Published var formActivities: [String] = []
    @Published var formSessions    = 3
    @Published var formDuration    = 45
    @Published var formDays: [Int] = [1, 3, 5]
    @Published var formContext     = ""

    // Formulaire — Sprint 12.2
    @Published var formMotivation:           String?    = nil
    @Published var formAttractiveActivities: [String]  = []
    @Published var formRejectedActivities:   [String]  = []
    @Published var formPreferredContext:     [String]  = []
    @Published var formApprehension:         String    = "aucune"
    @Published var formRealisticTime:        Int?      = nil

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

    let motivationOptions: [(id: String, label: String)] = [
        ("bouger_un_peu",       "Bouger un peu"),
        ("reprendre_confiance", "Reprendre confiance"),
        ("ameliorer_energie",   "Améliorer mon énergie"),
        ("perdre_poids",        "Perdre du poids"),
        ("preparer_sport",      "Me préparer pour un sport"),
    ]

    let contextOptions: [(id: String, label: String)] = [
        ("seul",    "Seul(e)"),
        ("groupe",  "En groupe"),
        ("dehors",  "Dehors"),
        ("maison",  "À la maison"),
        ("salle",   "En salle"),
    ]

    let apprehensionOptions: [(id: String, label: String)] = [
        ("aucune",  "Aucune"),
        ("legere",  "Légère"),
        ("moderee", "Modérée"),
        ("elevee",  "Importante"),
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
            fitnessLevel:         formLevel,
            preferredActivities:  formActivities,
            sessionsPerWeek:      formSessions,
            sessionDurationMin:   formDuration,
            availableDays:        formDays,
            context:              formContext.isEmpty ? nil : formContext,
            motivation:           formMotivation,
            attractiveActivities: formAttractiveActivities,
            rejectedActivities:   formRejectedActivities,
            preferredContext:     formPreferredContext,
            apprehensionLevel:    formApprehension,
            realisticTimeMin:     formRealisticTime
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

    func toggleRejectedActivity(_ name: String) {
        if formRejectedActivities.contains(name) {
            formRejectedActivities.removeAll { $0 == name }
        } else {
            formRejectedActivities.append(name)
        }
    }

    func togglePreferredContext(_ id: String) {
        if formPreferredContext.contains(id) {
            formPreferredContext.removeAll { $0 == id }
        } else {
            formPreferredContext.append(id)
        }
    }

    func levelLabel(_ id: String) -> String {
        fitnessLevels.first { $0.id == id }?.label ?? id
    }

    private func populateForm(from data: SportProfileData) {
        formLevel                = data.fitnessLevel
        formActivities           = data.preferredActivities
        formSessions             = data.sessionsPerWeek
        formDuration             = data.sessionDurationMin
        formDays                 = data.availableDays
        formContext              = data.context ?? ""
        formMotivation           = data.motivation
        formAttractiveActivities = data.attractiveActivities
        formRejectedActivities   = data.rejectedActivities
        formPreferredContext     = data.preferredContext
        formApprehension         = data.apprehensionLevel
        formRealisticTime        = data.realisticTimeMin
    }
}
