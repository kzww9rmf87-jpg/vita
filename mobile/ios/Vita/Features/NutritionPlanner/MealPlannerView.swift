import SwiftUI

private let DAYS_FR = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

struct MealPlannerView: View {
    @StateObject private var vm = MealPlannerViewModel()
    @StateObject private var recipeVm = RecipeLibraryViewModel()
    @State private var addSlot: (day: Int, slot: String)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekNavigator(vm: vm)
                    .padding(.horizontal, VitaSpacing.md)
                    .padding(.vertical, VitaSpacing.sm)

                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: VitaSpacing.sm) {
                            ForEach(0..<7, id: \.self) { day in
                                DayRow(
                                    dayLabel: DAYS_FR[day],
                                    lunchItems: vm.items(day: day, slot: "lunch"),
                                    dinnerItems: vm.items(day: day, slot: "dinner"),
                                    onAdd: { slot in addSlot = (day, slot) },
                                    onRemove: { id in Task { await vm.removeItem(itemId: id) } }
                                )
                            }
                        }
                        .padding(VitaSpacing.md)
                    }
                }
            }
            .navigationTitle("Plan de la semaine")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DistributeButton(vm: vm, recipeVm: recipeVm)
                }
            }
            .sheet(item: Binding(
                get: { addSlot.map { AddSlotID(day: $0.day, slot: $0.slot) } },
                set: { if $0 == nil { addSlot = nil } }
            )) { target in
                RecipePickerSheet(
                    recipeVm: recipeVm,
                    onSelect: { recipe in
                        addSlot = nil
                        Task { await vm.addItem(dayOfWeek: target.day, mealSlot: target.slot, recipeId: recipe.id, recipeName: recipe.name) }
                    },
                    onDismiss: { addSlot = nil }
                )
            }
            .alert("Erreur", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
        .task {
            await recipeVm.loadRecipes()
            await vm.loadPlans()
            await vm.loadCurrentPlan()
        }
    }
}

// Identifiable wrapper pour le binding du sheet
private struct AddSlotID: Identifiable {
    let day: Int
    let slot: String
    var id: String { "\(day)-\(slot)" }
}

// MARK: — WeekNavigator

private struct WeekNavigator: View {
    @ObservedObject var vm: MealPlannerViewModel
    private let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM"; f.locale = Locale(identifier: "fr_FR"); return f }()

    var body: some View {
        HStack {
            Button { Task { await vm.navigateWeek(by: -1) } } label: {
                Image(systemName: "chevron.left").font(VitaFont.headline(16))
            }
            Spacer()
            Text(weekLabel)
                .font(VitaFont.headline(16))
                .foregroundStyle(VitaColor.textPrimary)
            Spacer()
            Button { Task { await vm.navigateWeek(by: 1) } } label: {
                Image(systemName: "chevron.right").font(VitaFont.headline(16))
            }
        }
    }

    private var weekLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: vm.weekStart) ?? vm.weekStart
        return "\(fmt.string(from: vm.weekStart)) – \(fmt.string(from: end))"
    }
}

// MARK: — DayRow

private struct DayRow: View {
    let dayLabel: String
    let lunchItems: [MealPlanItem]
    let dinnerItems: [MealPlanItem]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.xs) {
            Text(dayLabel)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: VitaSpacing.sm) {
                SlotCell(label: "Déjeuner", items: lunchItems,
                         onAdd: { onAdd("lunch") }, onRemove: onRemove)
                SlotCell(label: "Dîner", items: dinnerItems,
                         onAdd: { onAdd("dinner") }, onRemove: onRemove)
            }
        }
    }
}

private struct SlotCell: View {
    let label: String
    let items: [MealPlanItem]
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.xs) {
            Text(label)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)

            if items.isEmpty {
                Button(action: onAdd) {
                    HStack {
                        Image(systemName: "plus").font(.caption)
                        Text("Ajouter").font(VitaFont.caption())
                    }
                    .foregroundStyle(VitaColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(VitaColor.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        MealItemChip(item: item, onRemove: { onRemove(item.id) })
                    }
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(VitaColor.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealItemChip: View {
    let item: MealPlanItem
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Text(item.recipeName)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textPrimary)
                .lineLimit(2)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(VitaColor.textSecondary)
            }
        }
        .padding(.horizontal, VitaSpacing.sm)
        .padding(.vertical, VitaSpacing.xs)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: — DistributeButton

private struct DistributeButton: View {
    @ObservedObject var vm: MealPlannerViewModel
    @ObservedObject var recipeVm: RecipeLibraryViewModel
    @State private var showPicker = false
    @State private var selectedIds: Set<String> = []

    var body: some View {
        Button { showPicker = true } label: {
            Image(systemName: "wand.and.stars")
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List(recipeVm.recipes) { recipe in
                    MultipleSelectionRow(
                        title: recipe.name,
                        isSelected: selectedIds.contains(recipe.id)
                    ) {
                        if selectedIds.contains(recipe.id) { selectedIds.remove(recipe.id) }
                        else { selectedIds.insert(recipe.id) }
                    }
                }
                .navigationTitle("Choisir les recettes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { showPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Planifier") {
                            showPicker = false
                            Task { await vm.distribute(recipeIds: Array(selectedIds)) }
                        }
                        .disabled(selectedIds.isEmpty || vm.isSaving)
                    }
                }
            }
        }
    }
}

private struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(VitaFont.body()).foregroundStyle(VitaColor.textPrimary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(VitaColor.accent) }
            }
        }
    }
}

// MARK: — RecipePickerSheet

private struct RecipePickerSheet: View {
    @ObservedObject var recipeVm: RecipeLibraryViewModel
    let onSelect: (Recipe) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(recipeVm.recipes) { recipe in
                Button {
                    onSelect(recipe)
                } label: {
                    RecipePickerRow(recipe: recipe)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Choisir une recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onDismiss)
                }
            }
        }
    }
}

private struct RecipePickerRow: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recipe.name).font(VitaFont.body()).foregroundStyle(VitaColor.textPrimary)
            HStack {
                Text("\(recipe.servings) portions")
                if recipe.totalMinutes > 0 { Text("· \(recipe.totalMinutes) min") }
            }
            .font(VitaFont.caption())
            .foregroundStyle(VitaColor.textSecondary)
        }
    }
}
