import Foundation

// MARK: — Modèles

struct MealPlan: Identifiable, Codable, Equatable {
    let id: String
    let weekStart: String
    let name: String?
    let notes: String?
    let createdAt: String?
}

// Macros d'une journée (issues de la distribution IA)
struct DayMacros: Codable, Equatable {
    let dayOfWeek: Int   // 0-6 ou -1 pour la semaine entière
    let calories:  Int?
    let proteinG:  Double?
    let carbsG:    Double?
    let fatG:      Double?
    let fiberG:    Double?
}

struct MealPlanDetail: Codable {
    let id: String
    let weekStart: String
    let name: String?
    var items: [MealPlanItem]
}

struct MealPlanItem: Identifiable, Codable, Equatable {
    let id: String
    var dayOfWeek: Int        // 0 = lundi, 6 = dimanche (var pour mise à jour optimiste)
    var mealSlot: String      // "breakfast" | "lunch" | "dinner" | "snack" (var pour mise à jour optimiste)
    let recipeId: String?
    let recipeName: String
    let portions: Double
    let notes: String?
    let sortOrder: Int?
    // Macros optionnelles (depuis JOIN recipes)
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
}

struct MealPlanItemCreate: Encodable {
    let dayOfWeek: Int
    let mealSlot: String
    let recipeId: String?
    let recipeName: String
    let portions: Double
    let notes: String?
}

struct MealPlanItemPatch: Encodable {
    let dayOfWeek: Int?
    let mealSlot: String?
    let portions: Double?
}

// MARK: — ViewModel

struct DistributeResponse: Codable {
    let itemsCreated: Int
    let dayMacros:    [DayMacros]?
    let weekMacros:   DayMacros?
    let usedClaude:   Bool?
}

@MainActor
final class MealPlannerViewModel: ObservableObject {
    @Published var plans: [MealPlan] = []
    @Published var currentPlan: MealPlanDetail?
    @Published var dayMacros:  [DayMacros] = []
    @Published var weekMacros: DayMacros?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // Semaine affichée (lundi courant par défaut)
    @Published var weekStart: Date = currentMonday()

    var weekStartString: String {
        Self.dateFormatter.string(from: weekStart)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func loadPlans() async {
        isLoading = true; defer { isLoading = false }
        do {
            plans = try await APIClient.shared.get("/meal-plans")
        } catch { errorMessage = error.localizedDescription }
    }

    func loadCurrentPlan() async {
        // Cherche le plan pour la semaine courante, crée-le si absent
        isLoading = true; defer { isLoading = false }
        do {
            // Essaye de trouver le plan dans la liste déjà chargée
            if let existing = plans.first(where: { $0.weekStart == weekStartString }) {
                currentPlan = try await APIClient.shared.get("/meal-plans/\(existing.id)")
            } else {
                // Crée le plan pour cette semaine
                let body = ["weekStart": weekStartString]
                let created: [String: String] = try await APIClient.shared.post("/meal-plans", body: body)
                if let id = created["id"] {
                    currentPlan = try await APIClient.shared.get("/meal-plans/\(id)")
                }
                await loadPlans()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func addItem(dayOfWeek: Int, mealSlot: String, recipeId: String?, recipeName: String, portions: Double = 1) async {
        guard let planId = currentPlan?.id else { return }
        isSaving = true; defer { isSaving = false }
        let body = MealPlanItemCreate(
            dayOfWeek: dayOfWeek, mealSlot: mealSlot,
            recipeId: recipeId, recipeName: recipeName,
            portions: portions, notes: nil
        )
        do {
            let _: [String: String] = try await APIClient.shared.post("/meal-plans/\(planId)/items", body: body)
            await loadCurrentPlan()
        } catch { errorMessage = error.localizedDescription }
    }

    func moveItem(itemId: String, toDayOfWeek: Int, toMealSlot: String) async {
        guard let planId = currentPlan?.id,
              let idx = currentPlan?.items.firstIndex(where: { $0.id == itemId })
        else { return }

        // Optimiste : déplace immédiatement dans l'UI
        let prevDay  = currentPlan!.items[idx].dayOfWeek
        let prevSlot = currentPlan!.items[idx].mealSlot
        currentPlan!.items[idx].dayOfWeek = toDayOfWeek
        currentPlan!.items[idx].mealSlot  = toMealSlot

        do {
            let body = MealPlanItemPatch(dayOfWeek: toDayOfWeek, mealSlot: toMealSlot, portions: nil)
            let _: [String: String] = try await APIClient.shared.patch(
                "/meal-plans/\(planId)/items/\(itemId)", body: body
            )
        } catch {
            // Rollback si l'API échoue
            currentPlan?.items[idx].dayOfWeek = prevDay
            currentPlan?.items[idx].mealSlot  = prevSlot
            errorMessage = error.localizedDescription
        }
    }

    func removeItem(itemId: String) async {
        guard let planId = currentPlan?.id else { return }
        do {
            try await APIClient.shared.delete("/meal-plans/\(planId)/items/\(itemId)")
            currentPlan?.items.removeAll(where: { $0.id == itemId })  // optimiste
        } catch { errorMessage = error.localizedDescription }
    }

    func distribute(recipeIds: [String]) async {
        guard let planId = currentPlan?.id else { return }
        isSaving = true; defer { isSaving = false }
        let body = ["recipeIds": recipeIds]
        do {
            let result: DistributeResponse = try await APIClient.shared.post("/meal-plans/\(planId)/distribute", body: body)
            dayMacros  = result.dayMacros  ?? []
            weekMacros = result.weekMacros
            await loadCurrentPlan()
        } catch { errorMessage = error.localizedDescription }
    }

    func navigateWeek(by delta: Int) async {
        weekStart = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekStart) ?? weekStart
        currentPlan = nil
        await loadCurrentPlan()
    }

    func items(day: Int, slot: String) -> [MealPlanItem] {
        currentPlan?.items.filter { $0.dayOfWeek == day && $0.mealSlot == slot } ?? []
    }

    // §1 — Créneaux actifs selon le plan courant (lunch + dinner toujours présents)
    var activeMealSlots: [String] {
        let allSlots: [String] = ["breakfast", "lunch", "dinner", "snack"]
        let base: Set<String>  = ["lunch", "dinner"]
        let inPlan = Set(currentPlan?.items.map { $0.mealSlot } ?? [])
        return allSlots.filter { base.contains($0) || inPlan.contains($0) }
    }
}

private func currentMonday() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2  // lundi
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    return cal.date(from: comps) ?? Date()
}
