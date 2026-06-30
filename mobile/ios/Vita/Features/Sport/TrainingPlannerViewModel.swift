import Foundation

// MARK: — Modèles AI Planner

struct AIPlannedSession: Identifiable, Codable {
    let id            = UUID()
    let dayOfWeek:    Int
    let activityName: String
    let sessionType:  String
    let durationMin:  Int
    let notes:        String?
    let sortOrder:    Int
    // Sprint 12.4 — enrichissement carte séance (optionnels pour rétrocompat)
    var intensityLabel:     String?
    var sessionGoal:        String?
    var simpleInstruction:  String?
    var progressionNote:    String?
    var whyThisSession:     String?

    enum CodingKeys: String, CodingKey {
        case dayOfWeek, activityName, sessionType, durationMin, notes, sortOrder
        case intensityLabel, sessionGoal, simpleInstruction, progressionNote, whyThisSession
    }

    init(
        dayOfWeek: Int, activityName: String, sessionType: String,
        durationMin: Int, notes: String? = nil, sortOrder: Int,
        intensityLabel: String? = nil, sessionGoal: String? = nil,
        simpleInstruction: String? = nil, progressionNote: String? = nil,
        whyThisSession: String? = nil
    ) {
        self.dayOfWeek        = dayOfWeek
        self.activityName     = activityName
        self.sessionType      = sessionType
        self.durationMin      = durationMin
        self.notes            = notes
        self.sortOrder        = sortOrder
        self.intensityLabel   = intensityLabel
        self.sessionGoal      = sessionGoal
        self.simpleInstruction = simpleInstruction
        self.progressionNote  = progressionNote
        self.whyThisSession   = whyThisSession
    }
}

struct AITrainingWeekPlan: Codable {
    let sessions:     [AIPlannedSession]
    let rationale:    String
    let usedClaude:   Bool
    let usedIdentity: Bool   // true si sport_identity a influencé le plan
    let hasProfile:   Bool   // false = plan généré avec profil par défaut
    let hasIdentity:  Bool   // true si une découverte conversationnelle existe
}

// MARK: — ViewModel

@MainActor
final class TrainingPlannerViewModel: ObservableObject {
    @Published var suggestedPlan:  AITrainingWeekPlan?
    @Published var isSuggesting:   Bool = false
    @Published var isSaving:       Bool = false
    @Published var errorMessage:   String?
    @Published var showSuggestion: Bool = false

    let dayNames = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]

    func suggest() async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let plan: AITrainingWeekPlan = try await APIClient.shared.post(
                "/sport/training-planner/suggest", body: EmptyResponse()
            )
            suggestedPlan  = plan
            showSuggestion = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAsPlan(name: String, makeActive: Bool, planVM: TrainingPlanViewModel) async -> Bool {
        guard let plan = suggestedPlan else { return false }
        isSaving = true
        defer { isSaving = false }

        let sessions = plan.sessions.map { s in
            TrainingPlanSessionCreate(
                dayOfWeek:    s.dayOfWeek,
                activityName: s.activityName,
                durationMin:  s.durationMin,
                notes:        s.notes,
                sortOrder:    s.sortOrder
            )
        }
        let body = TrainingPlanCreate(
            name:        name,
            description: plan.rationale,
            isActive:    makeActive,
            sessions:    sessions
        )
        do {
            let _: [String: String] = try await APIClient.shared.post("/sport/training-plans", body: body)
            suggestedPlan  = nil
            showSuggestion = false
            await planVM.load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sessionsForDay(_ day: Int) -> [AIPlannedSession] {
        (suggestedPlan?.sessions ?? [])
            .filter { $0.dayOfWeek == day }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func durationLabel(_ min: Int) -> String {
        min >= 60 ? "\(min / 60)h\(min % 60 > 0 ? "\(min % 60)" : "")" : "\(min) min"
    }

    func sessionTypeIcon(_ type: String) -> String {
        switch type {
        case "strength":  return "dumbbell.fill"
        case "cardio":    return "figure.run"
        case "combat":    return "figure.martial.arts"
        case "mobility":  return "figure.flexibility"
        case "walk":      return "figure.walk"
        case "recovery":  return "heart.fill"
        default:          return "figure.mixed.cardio"
        }
    }

    // Infère l'icône depuis le nom de l'activité (plan sauvegardé, sans session_type)
    func sessionIconFromActivity(_ name: String) -> String {
        let low = name.lowercased()
        if ["musculation", "muscu", "weight", "haltère", "gym", "force"].contains(where: { low.contains($0) }) {
            return "dumbbell.fill"
        }
        if ["krav", "combat", "boxe", "judo", "mma"].contains(where: { low.contains($0) }) {
            return "figure.martial.arts"
        }
        if ["yoga", "mobilité", "mobilite", "étirement", "stretching", "pilates"].contains(where: { low.contains($0) }) {
            return "figure.flexibility"
        }
        if ["marche", "walk", "randonnée", "rando"].contains(where: { low.contains($0) }) {
            return "figure.walk"
        }
        if ["course", "run", "vélo", "velo", "natation", "swim", "cardio", "hiit"].contains(where: { low.contains($0) }) {
            return "figure.run"
        }
        return "figure.mixed.cardio"
    }
}

