import Foundation

// MARK: — Modèles

struct TrainingPlanSummary: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let isActive: Bool
    let createdAt: String
}

struct TrainingPlanDetail: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let isActive: Bool
    let createdAt: String
    let sessions: [TrainingPlanSessionData]
}

struct TrainingPlanSessionData: Identifiable, Codable {
    let id: String
    let dayOfWeek: Int
    let activityName: String
    let durationMin: Int
    let notes: String?
    let sortOrder: Int
}

struct TrainingPlanCreate: Encodable {
    let name: String
    let description: String?
    let isActive: Bool
    let sessions: [TrainingPlanSessionCreate]
}

struct TrainingPlanSessionCreate: Encodable {
    let dayOfWeek: Int
    let activityName: String
    let durationMin: Int
    let notes: String?
    let sortOrder: Int
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

@MainActor
final class TrainingPlanViewModel: ObservableObject {

    @Published var plans: [TrainingPlanSummary] = []
    @Published var activePlan: TrainingPlanDetail?
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var showCreateSheet = false

    // Formulaire de création
    @Published var formName = ""
    @Published var formDescription = ""
    @Published var formSessions: [DraftSession] = []
    @Published var formMakeActive = true

    struct DraftSession: Identifiable {
        let id = UUID()
        var dayOfWeek: Int = 1
        var activityName: String = ""
        var durationMin: Int = 45
        var notes: String = ""
    }

    let dayNames = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]

    // MARK: — Chargement

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result: [TrainingPlanSummary] = try await APIClient.shared.get("/sport/training-plans")
            plans = result
            if let active = result.first(where: { $0.isActive }) {
                await loadDetail(id: active.id)
            }
        } catch {
            errorMessage = "Impossible de charger les plans."
        }
    }

    func loadDetail(id: String) async {
        do {
            let detail: TrainingPlanDetail = try await APIClient.shared.get("/sport/training-plans/\(id)")
            activePlan = detail
        } catch {
            errorMessage = "Impossible de charger le plan."
        }
    }

    // MARK: — Création

    func create() async -> Bool {
        let trimmed = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreating else { return false }
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil

        let sessions: [TrainingPlanSessionCreate] = formSessions
            .filter { !$0.activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { idx, s in
                TrainingPlanSessionCreate(
                    dayOfWeek:    s.dayOfWeek,
                    activityName: s.activityName.trimmingCharacters(in: .whitespacesAndNewlines),
                    durationMin:  s.durationMin,
                    notes:        s.notes.isEmpty ? nil : s.notes,
                    sortOrder:    idx
                )
            }

        let body = TrainingPlanCreate(
            name:        trimmed,
            description: formDescription.isEmpty ? nil : formDescription,
            isActive:    formMakeActive,
            sessions:    sessions
        )

        do {
            let _: [String: String] = try await APIClient.shared.post("/sport/training-plans", body: body)
            await load()
            resetForm()
            return true
        } catch {
            errorMessage = "La création a échoué."
            return false
        }
    }

    // MARK: — Suppression

    func delete(_ plan: TrainingPlanSummary) async {
        do {
            try await APIClient.shared.delete("/sport/training-plans/\(plan.id)")
            plans.removeAll { $0.id == plan.id }
            if activePlan?.id == plan.id { activePlan = nil }
        } catch {
            errorMessage = "Impossible de supprimer ce plan."
        }
    }

    // MARK: — Formulaire de création — gestion des séances modèles

    func addDraftSession() {
        formSessions.append(DraftSession())
    }

    func removeDraftSession(at offsets: IndexSet) {
        formSessions.remove(atOffsets: offsets)
    }

    func resetForm() {
        formName        = ""
        formDescription = ""
        formSessions    = []
        formMakeActive  = true
    }

    // MARK: — Utilitaires

    func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60; let rem = minutes % 60
        return rem == 0 ? "\(h)h" : "\(h)h\(rem)"
    }

    func sessionsForDay(_ day: Int, in plan: TrainingPlanDetail) -> [TrainingPlanSessionData] {
        plan.sessions
            .filter { $0.dayOfWeek == day }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
