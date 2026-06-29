import Foundation

// MARK: — Modèles

struct Recipe: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let servings: Int
    let prepMinutes: Int?
    let cookMinutes: Int?
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let notes: String?
    let createdAt: String?

    var totalMinutes: Int {
        (prepMinutes ?? 0) + (cookMinutes ?? 0)
    }
}

struct RecipeIngredient: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let quantityG: Double?
    let unit: String?
    let sortOrder: Int?
}

struct RecipeDetail: Codable {
    let id: String
    let name: String
    let servings: Int
    let prepMinutes: Int?
    let cookMinutes: Int?
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let notes: String?
    let ingredients: [RecipeIngredient]

    var totalMinutes: Int { (prepMinutes ?? 0) + (cookMinutes ?? 0) }
}

struct RecipeCreate: Encodable {
    let name: String
    let servings: Int
    let prepMinutes: Int?
    let cookMinutes: Int?
    let notes: String?
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let ingredients: [RecipeIngredientCreate]
}

struct RecipeIngredientCreate: Encodable {
    let name: String
    let quantityG: Double?
    let sortOrder: Int?
}

// MARK: — ViewModel

@MainActor
final class RecipeLibraryViewModel: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var selectedRecipe: RecipeDetail?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // Formulaire de création
    @Published var formName = ""
    @Published var formServings = 4
    @Published var formPrepMinutes: Int? = nil
    @Published var formCookMinutes: Int? = nil
    @Published var formNotes = ""
    @Published var formIngredients: [RecipeIngredientCreate] = []
    // Macros par portion (optionnelles — orientation planification)
    @Published var formCalories: String = ""
    @Published var formProteinG: String = ""
    @Published var formCarbsG: String = ""
    @Published var formFatG: String = ""
    @Published var formFiberG: String = ""
    // Prefill IA
    @Published var isPrefilling = false
    @Published var prefillError: String? = nil

    func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            recipes = try await APIClient.shared.get("/nutrition/recipes")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDetail(id: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            selectedRecipe = try await APIClient.shared.get("/nutrition/recipes/\(id)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        guard !formName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let body = RecipeCreate(
            name: formName,
            servings: formServings,
            prepMinutes: formPrepMinutes,
            cookMinutes: formCookMinutes,
            notes: formNotes.isEmpty ? nil : formNotes,
            calories: Int(formCalories),
            proteinG: Double(formProteinG),
            carbsG: Double(formCarbsG),
            fatG: Double(formFatG),
            fiberG: Double(formFiberG),
            ingredients: formIngredients
        )
        do {
            let _: [String: String] = try await APIClient.shared.post("/nutrition/recipes", body: body)
            await loadRecipes()
            resetForm()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: String) async {
        do {
            try await APIClient.shared.delete("/nutrition/recipes/\(id)")
            recipes.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetForm() {
        formName = ""
        formServings = 4
        formPrepMinutes = nil
        formCookMinutes = nil
        formNotes = ""
        formIngredients = []
        formCalories   = ""
        formProteinG   = ""
        formCarbsG     = ""
        formFatG       = ""
        formFiberG     = ""
        prefillError   = nil
    }

    func prefill() async {
        let name = formName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isPrefilling = true
        prefillError = nil
        defer { isPrefilling = false }
        do {
            struct PrefillRequest: Encodable {
                let recipeName: String
                let servings: Int
            }
            struct PrefillIngredient: Decodable {
                let name: String
                let quantityG: Double?
                let sortOrder: Int
            }
            struct PrefillResponse: Decodable {
                let prepMinutes: Int?
                let cookMinutes: Int?
                let notes: String?
                let caloriesPerServing: Int?
                let proteinGPerServing: Double?
                let carbsGPerServing: Double?
                let fatGPerServing: Double?
                let fiberGPerServing: Double?
                let ingredients: [PrefillIngredient]
            }
            let body = PrefillRequest(recipeName: name, servings: formServings)
            let result: PrefillResponse = try await APIClient.shared.post("/nutrition/recipes/prefill", body: body)
            formPrepMinutes  = result.prepMinutes
            formCookMinutes  = result.cookMinutes
            formNotes        = result.notes ?? formNotes
            formCalories     = result.caloriesPerServing.map(String.init) ?? ""
            formProteinG     = result.proteinGPerServing.map { String(format: "%.1f", $0) } ?? ""
            formCarbsG       = result.carbsGPerServing.map   { String(format: "%.1f", $0) } ?? ""
            formFatG         = result.fatGPerServing.map     { String(format: "%.1f", $0) } ?? ""
            formFiberG       = result.fiberGPerServing.map   { String(format: "%.1f", $0) } ?? ""
            formIngredients  = result.ingredients.map {
                RecipeIngredientCreate(name: $0.name, quantityG: $0.quantityG, sortOrder: $0.sortOrder)
            }
        } catch {
            prefillError = "VITA n'a pas pu générer la recette. Tu peux remplir les champs manuellement."
        }
    }

    func addIngredient(name: String, quantityG: Double?) {
        let sortOrder = formIngredients.count
        formIngredients.append(RecipeIngredientCreate(
            name: name, quantityG: quantityG, sortOrder: sortOrder
        ))
    }
}
