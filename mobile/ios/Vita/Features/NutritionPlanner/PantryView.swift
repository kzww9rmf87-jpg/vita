import SwiftUI

// MARK: — Modèles

struct PantryItem: Identifiable, Codable, Equatable {
    let id: String
    let ingredientName: String
    let notes: String?
    let createdAt: String?
}

// MARK: — ViewModel

@MainActor
final class PantryViewModel: ObservableObject {
    @Published var items: [PantryItem] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var newIngredientName = ""

    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            items = try await APIClient.shared.get("/pantry")
        } catch { errorMessage = error.localizedDescription }
    }

    func add() async {
        let name = newIngredientName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        let body = ["ingredientName": name]
        do {
            let _: [String: String] = try await APIClient.shared.post("/pantry", body: body)
            newIngredientName = ""
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(id: String) async {
        do {
            try await APIClient.shared.delete("/pantry/\(id)")
            items.removeAll { $0.id == id }
        } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: — Vue

struct PantryView: View {
    @StateObject private var vm = PantryViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Champ d'ajout rapide
                HStack(spacing: VitaSpacing.sm) {
                    TextField("Ajouter un ingrédient…", text: $vm.newIngredientName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit { Task { await vm.add() } }
                    Button {
                        Task { await vm.add() }
                    } label: {
                        if vm.isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(VitaColor.accent)
                        }
                    }
                    .disabled(vm.newIngredientName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSaving)
                }
                .padding(VitaSpacing.md)

                Divider()

                if vm.isLoading && vm.items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.items.isEmpty {
                    PantryEmptyState()
                } else {
                    List {
                        ForEach(vm.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.ingredientName)
                                    .font(VitaFont.body())
                                    .foregroundStyle(VitaColor.textPrimary)
                                if let notes = item.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(VitaFont.caption())
                                        .foregroundStyle(VitaColor.textSecondary)
                                }
                            }
                        }
                        .onDelete { indices in
                            for i in indices {
                                Task { await vm.delete(id: vm.items[i].id) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Garde-manger")
            .alert("Erreur", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
        .task { await vm.load() }
    }
}

private struct PantryEmptyState: View {
    var body: some View {
        VStack(spacing: VitaSpacing.md) {
            Image(systemName: "cabinet")
                .font(.system(size: 48))
                .foregroundStyle(VitaColor.textSecondary)
            Text("Garde-manger vide")
                .font(VitaFont.headline())
                .foregroundStyle(VitaColor.textPrimary)
            Text("Ajoutez les ingrédients que vous avez toujours chez vous.\nIls seront retirés automatiquement de vos listes de courses.")
                .font(VitaFont.body())
                .foregroundStyle(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VitaSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
