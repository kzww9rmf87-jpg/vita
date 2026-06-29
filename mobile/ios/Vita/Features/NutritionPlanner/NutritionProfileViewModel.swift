import Foundation

// MARK: — Modèles

struct NutritionProfile: Codable, Equatable {
    let id: String?
    var objective:          String  // maintain | lose | gain | recompose
    var weightKg:           Double?
    var heightCm:           Int?
    var age:                Int?
    var sex:                String? // male | female | other
    var activityLevel:      String  // sedentary | light | moderate | active | very_active
    var mealsPerDay:        Int
    var batchCooking:       Bool
    var cookTimeAvailable:  String? // minimal | moderate | generous
    var budget:             String? // low | medium | high
    var allergies:          [String]
    var intolerances:       [String]
    var excludedFoods:      [String]
    var preferredCuisines:  [String]
    // Cibles calculées — orientations internes, jamais affichées comme scores
    var targetCalories:     Int?
    var targetProteinG:     Double?
    var targetCarbsG:       Double?
    var targetFatG:         Double?
    var targetFiberG:       Double?
}

// Labels d'affichage

enum ObjectiveOption: String, CaseIterable {
    case maintain  = "maintain"
    case lose      = "lose"
    case gain      = "gain"
    case recompose = "recompose"

    var label: String {
        switch self {
        case .maintain:  return "Maintien"
        case .lose:      return "Perte de poids"
        case .gain:      return "Prise de masse"
        case .recompose: return "Recomposition"
        }
    }
    var description: String {
        switch self {
        case .maintain:  return "Garder mon poids actuel"
        case .lose:      return "Perdre du poids progressivement"
        case .gain:      return "Prendre du muscle"
        case .recompose: return "Perdre du gras en gardant le muscle"
        }
    }
}

enum ActivityLevelOption: String, CaseIterable {
    case sedentary  = "sedentary"
    case light      = "light"
    case moderate   = "moderate"
    case active     = "active"
    case very_active = "very_active"

    var label: String {
        switch self {
        case .sedentary:  return "Sédentaire"
        case .light:      return "Légèrement actif"
        case .moderate:   return "Modérément actif"
        case .active:     return "Actif"
        case .very_active: return "Très actif"
        }
    }
    var description: String {
        switch self {
        case .sedentary:  return "Peu ou pas d'exercice"
        case .light:      return "1-3 jours d'exercice / semaine"
        case .moderate:   return "3-5 jours d'exercice / semaine"
        case .active:     return "6-7 jours d'exercice / semaine"
        case .very_active: return "Travail physique + entraînement intensif"
        }
    }
}

enum CookTimeOption: String, CaseIterable {
    case minimal  = "minimal"
    case moderate = "moderate"
    case generous = "generous"

    var label: String {
        switch self {
        case .minimal:  return "Minimal (< 20 min)"
        case .moderate: return "Modéré (20-45 min)"
        case .generous: return "Disponible (> 45 min)"
        }
    }
}

enum BudgetOption: String, CaseIterable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var label: String {
        switch self {
        case .low:    return "Économique"
        case .medium: return "Moyen"
        case .high:   return "Sans contrainte"
        }
    }
}

// MARK: — ViewModel

@MainActor
final class NutritionProfileViewModel: ObservableObject {
    @Published var profile:       NutritionProfile?
    @Published var isLoading      = false
    @Published var isSaving       = false
    @Published var errorMessage:  String?
    @Published var successMessage: String?

    // Champs du formulaire (alimentés depuis profile ou valeurs par défaut)
    @Published var formObjective:         ObjectiveOption   = .maintain
    @Published var formWeightKg:          String            = ""
    @Published var formHeightCm:          String            = ""
    @Published var formAge:               String            = ""
    @Published var formSex:               String            = ""
    @Published var formActivityLevel:     ActivityLevelOption = .moderate
    @Published var formMealsPerDay:       Int               = 3
    @Published var formBatchCooking:      Bool              = false
    @Published var formCookTime:          CookTimeOption?   = nil
    @Published var formBudget:            BudgetOption?     = nil
    @Published var formAllergiesText:     String            = ""
    @Published var formIntolerancesText:  String            = ""
    @Published var formExcludedFoodsText: String            = ""

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await APIClient.shared.get("/nutrition/profile")
            if let p = profile { populateForm(from: p) }
        } catch let error as APIError {
            if case .serverError(let code) = error, code == 404 { /* Pas encore de profil */ }
            else { errorMessage = error.localizedDescription }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = buildBody()
        do {
            if profile == nil {
                let _: [String: String] = try await APIClient.shared.post("/nutrition/profile", body: body)
            } else {
                let _: [String: Bool] = try await APIClient.shared.patch("/nutrition/profile", body: body)
            }
            await load()
            successMessage = "Profil enregistré."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func populateForm(from p: NutritionProfile) {
        formObjective      = ObjectiveOption(rawValue: p.objective)   ?? .maintain
        formWeightKg       = p.weightKg.map    { String(format: "%.1f", $0) } ?? ""
        formHeightCm       = p.heightCm.map    { String($0) } ?? ""
        formAge            = p.age.map         { String($0) } ?? ""
        formSex            = p.sex ?? ""
        formActivityLevel  = ActivityLevelOption(rawValue: p.activityLevel) ?? .moderate
        formMealsPerDay    = p.mealsPerDay
        formBatchCooking   = p.batchCooking
        formCookTime       = p.cookTimeAvailable.flatMap { CookTimeOption(rawValue: $0) }
        formBudget         = p.budget.flatMap { BudgetOption(rawValue: $0) }
        formAllergiesText      = p.allergies.joined(separator: ", ")
        formIntolerancesText   = p.intolerances.joined(separator: ", ")
        formExcludedFoodsText  = p.excludedFoods.joined(separator: ", ")
    }

    private func buildBody() -> NutritionProfileBody {
        NutritionProfileBody(
            objective:         formObjective.rawValue,
            weightKg:          Double(formWeightKg.replacingOccurrences(of: ",", with: ".")),
            heightCm:          Int(formHeightCm),
            age:               Int(formAge),
            sex:               formSex.isEmpty ? nil : formSex,
            activityLevel:     formActivityLevel.rawValue,
            mealsPerDay:       formMealsPerDay,
            batchCooking:      formBatchCooking,
            cookTimeAvailable: formCookTime?.rawValue,
            budget:            formBudget?.rawValue,
            allergies:         splitTags(formAllergiesText),
            intolerances:      splitTags(formIntolerancesText),
            excludedFoods:     splitTags(formExcludedFoodsText),
            preferredCuisines: []
        )
    }

    private func splitTags(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// Corps de la requête (snake_case automatique via JSONEncoder.vita)
struct NutritionProfileBody: Encodable {
    let objective:          String
    let weightKg:           Double?
    let heightCm:           Int?
    let age:                Int?
    let sex:                String?
    let activityLevel:      String
    let mealsPerDay:        Int
    let batchCooking:       Bool
    let cookTimeAvailable:  String?
    let budget:             String?
    let allergies:          [String]
    let intolerances:       [String]
    let excludedFoods:      [String]
    let preferredCuisines:  [String]
}
