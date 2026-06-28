import Foundation

// MARK: — Modèles

struct Meal: Identifiable, Codable, Equatable {
    let id: String
    let date: String
    let eatenAt: String?
    let mealType: String?
    let description: String
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let isRestaurant: Bool?
    let notes: String?
    let createdAt: String?
}

struct MealCreate: Encodable {
    let date: String
    let mealType: String?
    let description: String
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let isRestaurant: Bool?
    let notes: String?
}

struct NutritionDailyEntry: Codable {
    let date: String
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let waterMl: Int?
    let notes: String?
}

// MARK: — ViewModel

@MainActor
final class NutritionViewModel: ObservableObject {

    @Published var todayMeals: [Meal] = []
    @Published var dailyHistory: [NutritionDailyEntry] = []
    @Published var isLoading = false
    @Published var isSaving  = false
    @Published var errorMessage: String?

    // Formulaire de saisie rapide repas
    @Published var formDate        = Calendar.current.startOfDay(for: Date())
    @Published var formDescription = ""
    @Published var formMealType: String? = nil
    @Published var formCalories: Int = 0
    @Published var formProtein: Double = 0
    @Published var formIsRestaurant = false
    @Published var formNotes       = ""

    let mealTypes = ["breakfast", "lunch", "dinner", "snack"]
    let mealTypeLabels = ["Petit-déjeuner", "Déjeuner", "Dîner", "Collation"]

    // MARK: — Chargement

    func loadToday() async {
        isLoading = true
        defer { isLoading = false }
        let dateStr = ISO8601DateFormatter.vitaDate.string(from: Date())
        do {
            let meals: [Meal] = try await APIClient.shared.get("/nutrition/meals?date=\(dateStr)")
            todayMeals = meals
        } catch {
            errorMessage = "Impossible de charger les repas."
        }
    }

    func loadHistory() async {
        do {
            let history: [NutritionDailyEntry] = try await APIClient.shared.get("/nutrition/history?days=14")
            dailyHistory = history
        } catch {
            // Historique optionnel — pas d'erreur affichée
        }
    }

    // MARK: — Création d'un repas

    func saveMeal() async -> Bool {
        let trimmed = formDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let dateStr = ISO8601DateFormatter.vitaDate.string(from: formDate)
        let body = MealCreate(
            date: dateStr,
            mealType: formMealType,
            description: trimmed,
            calories: formCalories > 0 ? formCalories : nil,
            proteinG: formProtein > 0 ? formProtein : nil,
            carbsG: nil,
            fatG: nil,
            isRestaurant: formIsRestaurant ? true : nil,
            notes: formNotes.isEmpty ? nil : formNotes
        )
        do {
            let _: [String: String] = try await APIClient.shared.post("/nutrition/meals", body: body)
            await loadToday()
            resetMealForm()
            return true
        } catch {
            errorMessage = "L'enregistrement a échoué."
            return false
        }
    }

    // MARK: — Suppression

    func deleteMeal(_ meal: Meal) async {
        do {
            try await APIClient.shared.delete("/nutrition/meals/\(meal.id)")
            todayMeals.removeAll { $0.id == meal.id }
        } catch {
            errorMessage = "Impossible de supprimer ce repas."
        }
    }

    // MARK: — Utilitaires

    func resetMealForm() {
        formDate        = Calendar.current.startOfDay(for: Date())
        formDescription = ""
        formMealType    = nil
        formCalories    = 0
        formProtein     = 0
        formIsRestaurant = false
        formNotes       = ""
    }

    var todayCaloriesTotal: Int {
        todayMeals.compactMap(\.calories).reduce(0, +)
    }

    func mealTypeLabel(_ type: String?) -> String {
        guard let type else { return "" }
        switch type {
        case "breakfast": return "Petit-déjeuner"
        case "lunch":     return "Déjeuner"
        case "dinner":    return "Dîner"
        case "snack":     return "Collation"
        default:          return type
        }
    }
}

private extension ISO8601DateFormatter {
    static let vitaDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
