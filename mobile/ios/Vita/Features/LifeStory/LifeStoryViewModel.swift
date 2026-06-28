import Foundation

// MARK: — Modèles

struct LifeMemory: Codable, Identifiable {
    let id: String
    let type: String
    let summary: String
    let lastSeen: Date
}

struct LifeStoryGroup: Codable, Identifiable {
    var id: String { month }
    let month: String
    let label: String
    let memories: [LifeMemory]
}

private struct LifeStoryResponse: Codable {
    let groups: [LifeStoryGroup]
}

// MARK: — ViewModel

@MainActor
final class LifeStoryViewModel: ObservableObject {
    @Published var groups: [LifeStoryGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: LifeStoryResponse = try await APIClient.shared.get("/life-story")
            self.groups = response.groups
        } catch {
            errorMessage = "Impossible de charger ton histoire pour l'instant."
        }
    }
}
