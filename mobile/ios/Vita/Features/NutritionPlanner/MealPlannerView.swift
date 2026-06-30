import SwiftUI
import UniformTypeIdentifiers

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
                            // Résumé macro de la semaine (si disponible après planification)
                            if let wm = vm.weekMacros, wm.calories != nil {
                                WeekMacroSummary(macros: wm)
                                    .padding(.horizontal, VitaSpacing.md)
                            }

                            // Mention discrète plan sportif — sans score, sans jugement
                            if vm.usedSportContext {
                                HStack(spacing: VitaSpacing.xs) {
                                    Image(systemName: "figure.run")
                                        .font(.caption)
                                        .foregroundStyle(VitaColor.accent)
                                    Text("VITA tient compte de ta semaine sportive.")
                                        .font(VitaFont.caption())
                                        .foregroundStyle(VitaColor.textSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, VitaSpacing.md)
                            }

                            ForEach(0..<7, id: \.self) { day in
                                VStack(spacing: 4) {
                                    DayRow(
                                        dayLabel:     DAYS_FR[day],
                                        activeSlots:  vm.activeMealSlots,
                                        itemsForSlot: { slot in vm.items(day: day, slot: slot) },
                                        onAdd:    { slot in addSlot = (day, slot) },
                                        onRemove: { id in Task { await vm.removeItem(itemId: id) } },
                                        onMove:   { id, targetDay, targetSlot in
                                            Task { await vm.moveItem(itemId: id, toDayOfWeek: targetDay, toMealSlot: targetSlot) }
                                        },
                                        day: day
                                    )
                                    // Macros du jour (si disponibles)
                                    if let dm = vm.dayMacros.first(where: { $0.dayOfWeek == day }),
                                       dm.calories != nil {
                                        DayMacroBar(macros: dm)
                                            .padding(.horizontal, VitaSpacing.xs)
                                    }
                                }
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

private let SLOT_LABELS: [String: String] = [
    "breakfast": "Petit-déjeuner",
    "lunch":     "Déjeuner",
    "dinner":    "Dîner",
    "snack":     "Collation",
]

private struct DayRow: View {
    let dayLabel:     String
    let activeSlots:  [String]
    let itemsForSlot: (String) -> [MealPlanItem]
    let onAdd:    (String) -> Void
    let onRemove: (String) -> Void
    let onMove:   (String, Int, String) -> Void  // (itemId, targetDay, targetSlot)
    let day: Int

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.xs) {
            Text(dayLabel)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: VitaSpacing.sm) {
                ForEach(activeSlots, id: \.self) { slot in
                    SlotCell(
                        label:    SLOT_LABELS[slot] ?? slot,
                        items:    itemsForSlot(slot),
                        onAdd:    { onAdd(slot) },
                        onRemove: onRemove,
                        onMove:   { id in onMove(id, day, slot) }
                    )
                }
            }
        }
    }
}

private struct SlotCell: View {
    let label: String
    let items: [MealPlanItem]
    let onAdd: () -> Void
    let onRemove: (String) -> Void
    let onMove: (String) -> Void   // itemId déposé dans ce créneau

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.xs) {
            Text(label)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                if items.isEmpty {
                    Button(action: onAdd) {
                        HStack {
                            Image(systemName: "plus").font(.caption)
                            Text("Ajouter").font(VitaFont.caption())
                        }
                        .foregroundStyle(VitaColor.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isDropTarget ? VitaColor.accent.opacity(0.08) : VitaColor.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                    }
                } else {
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
            .overlay(
                isDropTarget && !items.isEmpty
                    ? RoundedRectangle(cornerRadius: VitaRadius.sm)
                        .stroke(VitaColor.accent, lineWidth: 1.5)
                    : nil
            )
            .onDrop(of: [UTType.plainText], isTargeted: $isDropTarget) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let itemId = object as? String {
                        DispatchQueue.main.async { onMove(itemId) }
                    }
                }
                return true
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
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(VitaColor.textSecondary)
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
        .onDrag {
            NSItemProvider(object: item.id as NSString)
        }
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
                        Button("Organiser avec VITA") {
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

// MARK: — Macros

private struct WeekMacroSummary: View {
    let macros: DayMacros

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            MacroChip(label: "Énergie",   value: macros.calories.map { "\($0) kcal" } ?? "—", color: VitaColor.accent)
            MacroChip(label: "Protéines", value: macros.proteinG.map { formatG($0) } ?? "—",  color: VitaColor.accentDark)
            MacroChip(label: "Glucides",  value: macros.carbsG.map   { formatG($0) } ?? "—",  color: VitaColor.neutral)
            MacroChip(label: "Lipides",   value: macros.fatG.map     { formatG($0) } ?? "—",  color: VitaColor.textSecondary)
            MacroChip(label: "Fibres",    value: macros.fiberG.map   { formatG($0) } ?? "—",  color: Color.teal)
        }
        .padding(VitaSpacing.sm)
        .background(VitaColor.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
    }
}

private struct DayMacroBar: View {
    let macros: DayMacros

    var body: some View {
        HStack(spacing: VitaSpacing.xs) {
            if let kcal = macros.calories {
                Text("\(kcal) kcal")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.accent)
            }
            Spacer()
            if let p = macros.proteinG {
                Text("P \(formatG(p))")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.accentDark)
            }
            if let c = macros.carbsG {
                Text("G \(formatG(c))")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.neutral)
            }
            if let f = macros.fatG {
                Text("L \(formatG(f))")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }
            if let fi = macros.fiberG {
                Text("Fi \(formatG(fi))")
                    .font(VitaFont.caption())
                    .foregroundStyle(Color.teal)
            }
        }
        .padding(.horizontal, VitaSpacing.sm)
        .padding(.vertical, 3)
        .background(VitaColor.surfaceHigh.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
    }
}

private struct MacroChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(VitaFont.caption())
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(VitaFont.caption(11))
                .foregroundStyle(VitaColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VitaSpacing.xs)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
    }
}

private func formatG(_ value: Double) -> String {
    value >= 100 ? "\(Int(value))g" : String(format: "%.1fg", value)
}
