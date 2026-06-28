import Foundation

// MARK: — Modèles

struct ShoppingListItem: Identifiable, Codable, Equatable {
    let id: String
    let ingredientName: String
    let quantity: Double?
    let unit: String?
    let category: String
    var isChecked: Bool
}

// Ordre d'affichage et labels des catégories
enum ShoppingCategory: String, CaseIterable {
    case produce   = "produce"
    case meat      = "meat"
    case fish      = "fish"
    case dairy     = "dairy"
    case pantry    = "pantry"
    case frozen    = "frozen"
    case beverages = "beverages"
    case spices    = "spices"
    case other     = "other"

    var label: String {
        switch self {
        case .produce:   return "Fruits & Légumes"
        case .meat:      return "Viandes"
        case .fish:      return "Poissons & Fruits de mer"
        case .dairy:     return "Produits laitiers"
        case .pantry:    return "Épicerie sèche"
        case .frozen:    return "Surgelés"
        case .beverages: return "Boissons"
        case .spices:    return "Épices & Herbes"
        case .other:     return "Autres"
        }
    }
}

// MARK: — ViewModel

@MainActor
final class ShoppingListViewModel: ObservableObject {
    @Published var items: [ShoppingListItem] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var errorMessage: String?

    var planId: String?

    var itemsByCategory: [(category: ShoppingCategory, items: [ShoppingListItem])] {
        ShoppingCategory.allCases.compactMap { cat in
            let catItems = items.filter { $0.category == cat.rawValue }
            return catItems.isEmpty ? nil : (cat, catItems)
        }
    }

    var uncheckedCount: Int { items.filter { !$0.isChecked }.count }

    func load(planId: String) async {
        self.planId = planId
        isLoading = true; defer { isLoading = false }
        do {
            items = try await APIClient.shared.get("/meal-plans/\(planId)/shopping-list")
        } catch { errorMessage = error.localizedDescription }
    }

    func generate(planId: String) async {
        isGenerating = true; defer { isGenerating = false }
        do {
            let _: [String: Int] = try await APIClient.shared.post(
                "/meal-plans/\(planId)/shopping-list/generate", body: ShoppingListEmptyBody()
            )
            await load(planId: planId)
        } catch { errorMessage = error.localizedDescription }
    }

    func toggle(itemId: String) async {
        guard let planId, let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        let newValue = !items[idx].isChecked
        items[idx].isChecked = newValue  // optimiste
        do {
            let _: [String: String] = try await APIClient.shared.patch(
                "/meal-plans/\(planId)/shopping-list/\(itemId)",
                body: ["isChecked": newValue]
            )
        } catch {
            items[idx].isChecked = !newValue  // rollback
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShoppingListEmptyBody: Encodable {}
