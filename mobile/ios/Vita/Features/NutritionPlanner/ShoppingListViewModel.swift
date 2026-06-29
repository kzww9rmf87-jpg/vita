import SwiftUI

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
    @Published var readyBanner: String?  // texte de la bannière post-génération

    var planId: String?

    var itemsByCategory: [(category: ShoppingCategory, items: [ShoppingListItem])] {
        ShoppingCategory.allCases.compactMap { cat in
            let catItems = items.filter { $0.category == cat.rawValue }
            return catItems.isEmpty ? nil : (cat, catItems)
        }
    }

    var uncheckedCount: Int { items.filter { !$0.isChecked }.count }

    var shareText: String {
        guard !items.isEmpty else { return "Liste de courses vide." }
        return itemsByCategory.map { group in
            "\(group.category.label)\n" + group.items.map { item in
                var line = "• \(item.ingredientName.capitalized)"
                if let qty = item.quantity, let unit = item.unit {
                    line += " (\(Int(qty)) \(unit))"
                }
                if item.isChecked { line += " ✓" }
                return line
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

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
            let result: [String: Int] = try await APIClient.shared.post(
                "/meal-plans/\(planId)/shopping-list/generate", body: ShoppingListEmptyBody()
            )
            await load(planId: planId)
            let count = result["itemsGenerated"] ?? 0
            let text = count > 0
                ? "\(count) article\(count > 1 ? "s" : "") à acheter"
                : "Le garde-manger couvre tout — rien à acheter !"
            withAnimation { readyBanner = text }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { readyBanner = nil }
            }
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
