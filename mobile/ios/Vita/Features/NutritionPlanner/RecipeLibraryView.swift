import SwiftUI

struct RecipeLibraryView: View {
    @StateObject private var vm = RecipeLibraryViewModel()
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.recipes.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.recipes.isEmpty {
                    RecipeEmptyStateView { showAddSheet = true }
                } else {
                    List {
                        ForEach(vm.recipes) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipeId: recipe.id, vm: vm)) {
                                RecipeRow(recipe: recipe)
                            }
                        }
                        .onDelete { indices in
                            for i in indices {
                                Task { await vm.delete(id: vm.recipes[i].id) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Mes recettes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                RecipeAddSheet(vm: vm, onDismiss: { showAddSheet = false })
            }
            .alert("Erreur", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .task { await vm.loadRecipes() }
    }
}

// MARK: — Sous-vues

private struct RecipeEmptyStateView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: VitaSpacing.md) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(VitaColor.textSecondary)
            Text("Aucune recette")
                .font(VitaFont.headline())
                .foregroundStyle(VitaColor.textPrimary)
            Text("Ajoutez vos recettes pour organiser votre semaine.")
                .font(VitaFont.body())
                .foregroundStyle(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VitaSpacing.xl)
            Button("Ajouter une recette", action: onAdd)
                .buttonStyle(.borderedProminent)
                .tint(VitaColor.accent)
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.xs) {
            Text(recipe.name)
                .font(VitaFont.headline(16))
                .foregroundStyle(VitaColor.textPrimary)
            HStack(spacing: VitaSpacing.sm) {
                Label("\(recipe.servings) portions", systemImage: "person.2")
                if recipe.totalMinutes > 0 {
                    Label("\(recipe.totalMinutes) min", systemImage: "clock")
                }
                if let kcal = recipe.calories {
                    Label("\(kcal) kcal", systemImage: "flame")
                }
            }
            .font(VitaFont.caption())
            .foregroundStyle(VitaColor.textSecondary)
        }
        .padding(.vertical, VitaSpacing.xs)
    }
}

// MARK: — Detail

struct RecipeDetailView: View {
    let recipeId: String
    @ObservedObject var vm: RecipeLibraryViewModel

    var body: some View {
        ZStack {
            if vm.isLoading {
                ProgressView()
            } else if let r = vm.selectedRecipe {
                ScrollView {
                    VStack(alignment: .leading, spacing: VitaSpacing.lg) {
                        // En-tête macros
                        if r.calories != nil || r.proteinG != nil {
                            MacrosRow(
                                calories: r.calories,
                                proteinG: r.proteinG,
                                carbsG: r.carbsG,
                                fatG: r.fatG,
                                fiberG: r.fiberG
                            )
                            .padding(.horizontal, VitaSpacing.md)
                        }
                        // Infos
                        HStack(spacing: VitaSpacing.lg) {
                            InfoChip(label: "\(r.servings) portions", icon: "person.2")
                            if r.totalMinutes > 0 {
                                InfoChip(label: "\(r.totalMinutes) min", icon: "clock")
                            }
                        }
                        .padding(.horizontal, VitaSpacing.md)

                        // Ingrédients
                        if !r.ingredients.isEmpty {
                            VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                                Text("Ingrédients")
                                    .font(VitaFont.headline())
                                    .foregroundStyle(VitaColor.textPrimary)
                                    .padding(.horizontal, VitaSpacing.md)
                                ForEach(r.ingredients) { ing in
                                    HStack {
                                        Text(ing.name)
                                            .font(VitaFont.body())
                                            .foregroundStyle(VitaColor.textPrimary)
                                        Spacer()
                                        if let q = ing.quantityG {
                                            Text("\(Int(q)) g")
                                                .font(VitaFont.body())
                                                .foregroundStyle(VitaColor.textSecondary)
                                        }
                                    }
                                    .padding(.horizontal, VitaSpacing.md)
                                    Divider().padding(.horizontal, VitaSpacing.md)
                                }
                            }
                        }

                        if let notes = r.notes, !notes.isEmpty {
                            Text(notes)
                                .font(VitaFont.body())
                                .foregroundStyle(VitaColor.textSecondary)
                                .padding(.horizontal, VitaSpacing.md)
                        }
                    }
                    .padding(.vertical, VitaSpacing.md)
                }
            }
        }
        .navigationTitle(vm.selectedRecipe?.name ?? "Recette")
        .task { await vm.loadDetail(id: recipeId) }
    }
}

private struct MacrosRow: View {
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?

    var body: some View {
        HStack(spacing: 0) {
            if let v = calories  { MacroCell(value: "\(v)", unit: "kcal",    label: "Énergie") }
            if let v = proteinG  { MacroCell(value: formatted(v), unit: "g", label: "Protéines") }
            if let v = carbsG    { MacroCell(value: formatted(v), unit: "g", label: "Glucides") }
            if let v = fatG      { MacroCell(value: formatted(v), unit: "g", label: "Lipides") }
        }
        .background(VitaColor.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
    }

    private func formatted(_ v: Double) -> String { String(format: "%.0f", v) }
}

private struct MacroCell: View {
    let value: String
    let unit: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(VitaFont.headline(16)).foregroundStyle(VitaColor.textPrimary)
                Text(unit).font(VitaFont.caption()).foregroundStyle(VitaColor.textSecondary)
            }
            Text(label).font(VitaFont.caption()).foregroundStyle(VitaColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VitaSpacing.sm)
    }
}

private struct InfoChip: View {
    let label: String
    let icon: String
    var body: some View {
        Label(label, systemImage: icon)
            .font(VitaFont.caption())
            .foregroundStyle(VitaColor.textSecondary)
            .padding(.horizontal, VitaSpacing.sm)
            .padding(.vertical, VitaSpacing.xs)
            .background(VitaColor.surfaceHigh)
            .clipShape(Capsule())
    }
}

// MARK: — Ajout de recette

private struct RecipeAddSheet: View {
    @ObservedObject var vm: RecipeLibraryViewModel
    let onDismiss: () -> Void

    @State private var ingName = ""
    @State private var ingQty = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations") {
                    TextField("Nom de la recette", text: $vm.formName)
                    Stepper("Portions : \(vm.formServings)", value: $vm.formServings, in: 1...20)
                    HStack {
                        Text("Préparation (min)")
                        Spacer()
                        TextField("0", value: $vm.formPrepMinutes, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("Cuisson (min)")
                        Spacer()
                        TextField("0", value: $vm.formCookMinutes, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }
                }
                Section {
                    Button {
                        Task { await vm.prefill() }
                    } label: {
                        HStack {
                            if vm.isPrefilling {
                                ProgressView().scaleEffect(0.8)
                                Text("VITA réfléchit…")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Pré-remplir avec VITA")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VitaColor.accent)
                    .disabled(
                        vm.formName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isPrefilling
                    )

                    if let err = vm.prefillError {
                        Text(err)
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.warning)
                    } else {
                        Text("VITA peut estimer les ingrédients et valeurs nutritionnelles. Tu peux tout modifier avant d'enregistrer.")
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.textSecondary)
                    }
                }
                Section("Notes") {
                    TextField("Notes optionnelles", text: $vm.formNotes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                Section("Valeurs nutritionnelles par portion") {
                    HStack {
                        Text("Énergie (kcal)")
                        Spacer()
                        TextField("—", text: $vm.formCalories)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Protéines (g)")
                        Spacer()
                        TextField("—", text: $vm.formProteinG)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Glucides (g)")
                        Spacer()
                        TextField("—", text: $vm.formCarbsG)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Lipides (g)")
                        Spacer()
                        TextField("—", text: $vm.formFatG)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Fibres (g)")
                        Spacer()
                        TextField("—", text: $vm.formFiberG)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                    }
                }
                Section("Ingrédients") {
                    ForEach(vm.formIngredients.indices, id: \.self) { i in
                        HStack {
                            Text(vm.formIngredients[i].name)
                            Spacer()
                            if let q = vm.formIngredients[i].quantityG {
                                Text("\(Int(q)) g")
                                    .foregroundStyle(VitaColor.textSecondary)
                            }
                        }
                    }
                    .onDelete { vm.formIngredients.remove(atOffsets: $0) }

                    HStack {
                        TextField("Ingrédient", text: $ingName)
                        TextField("Qté (g)", text: $ingQty)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                        Button {
                            vm.addIngredient(name: ingName, quantityG: Double(ingQty))
                            ingName = ""; ingQty = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(VitaColor.accent)
                        }
                        .disabled(ingName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Nouvelle recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { vm.resetForm(); onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task { await vm.save(); onDismiss() }
                    }
                    .disabled(vm.formName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSaving)
                }
            }
        }
    }
}
