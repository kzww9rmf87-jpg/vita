import SwiftUI

// MARK: — Vue principale

struct NutritionView: View {
    @StateObject private var vm = NutritionViewModel()
    @State private var showMealLog = false

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                NutritionHeaderView(caloriesTotal: vm.todayCaloriesTotal, mealCount: vm.todayMeals.count)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.lg)

                Divider()
                    .background(VitaColor.neutral.opacity(0.15))
                    .padding(.top, VitaSpacing.md)

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(VitaColor.accent)
                    Spacer()
                } else if vm.todayMeals.isEmpty {
                    NutritionEmptyStateView { showMealLog = true }
                } else {
                    MealListView(
                        meals: vm.todayMeals,
                        mealTypeLabel: vm.mealTypeLabel,
                        onDelete: { m in Task { await vm.deleteMeal(m) } }
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showMealLog) {
            MealQuickLogSheet(vm: vm)
        }
        .task {
            await vm.loadToday()
            await vm.loadHistory()
        }
        .overlay(alignment: .bottomTrailing) {
            Button { showMealLog = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(VitaColor.accent)
                    .clipShape(Circle())
                    .shadow(color: VitaColor.accent.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.trailing, VitaSpacing.lg)
            .padding(.bottom, VitaSpacing.xl)
        }
    }
}

// MARK: — En-tête

private struct NutritionHeaderView: View {
    let caloriesTotal: Int
    let mealCount: Int

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("Nutrition")
                    .font(VitaFont.title(22))
                    .foregroundColor(VitaColor.textPrimary)
                Text("Aujourd'hui")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: VitaSpacing.xs) {
                if caloriesTotal > 0 {
                    Text("\(caloriesTotal) kcal")
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundColor(VitaColor.textPrimary)
                }
                Text(mealCount == 0 ? "Aucun repas" : "\(mealCount) repas")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }
        }
    }
}

// MARK: — État vide

private struct NutritionEmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(VitaColor.accentLight)
            VStack(spacing: VitaSpacing.xs) {
                Text("Aucun repas enregistré")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text("Qu'est-ce que tu as mangé aujourd'hui ?")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
            }
            Button("Ajouter un repas", action: onAdd)
                .buttonStyle(VitaPrimaryButtonStyle())
                .padding(.horizontal, VitaSpacing.xl)
            Spacer()
        }
    }
}

// MARK: — Liste des repas

private struct MealListView: View {
    let meals: [Meal]
    let mealTypeLabel: (String?) -> String
    let onDelete: (Meal) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: VitaSpacing.sm) {
                ForEach(meals) { meal in
                    MealRow(meal: meal, mealTypeLabel: mealTypeLabel)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(meal)
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, VitaSpacing.lg)
            .padding(.vertical, VitaSpacing.md)
        }
    }
}

private struct MealRow: View {
    let meal: Meal
    let mealTypeLabel: (String?) -> String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text(meal.description)
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textPrimary)
                    .lineLimit(2)
                if let type = meal.mealType {
                    Text(mealTypeLabel(type))
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textTertiary)
                }
            }
            Spacer()
            if let cal = meal.calories {
                Text("\(cal) kcal")
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundColor(VitaColor.textSecondary)
            }
        }
        .padding(VitaSpacing.md)
        .vitaCard()
    }
}

// MARK: — Saisie rapide

struct MealQuickLogSheet: View {
    @ObservedObject var vm: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.xl) {

                        // Type de repas
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Moment du repas")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            HStack(spacing: VitaSpacing.sm) {
                                ForEach(Array(zip(vm.mealTypes, vm.mealTypeLabels)), id: \.0) { type, label in
                                    Button(label) {
                                        vm.formMealType = vm.formMealType == type ? nil : type
                                    }
                                    .font(VitaFont.caption(12))
                                    .foregroundColor(vm.formMealType == type ? .white : VitaColor.textSecondary)
                                    .padding(.vertical, VitaSpacing.sm)
                                    .frame(maxWidth: .infinity)
                                    .background(vm.formMealType == type ? VitaColor.accent : VitaColor.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                                }
                            }
                        }

                        // Description
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Qu'est-ce que tu as mangé ?")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            TextField("Décris ton repas librement…", text: $vm.formDescription, axis: .vertical)
                                .font(VitaFont.body())
                                .lineLimit(2...5)
                                .padding(VitaSpacing.md)
                                .background(VitaColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                        }

                        // Calories (optionnel)
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Calories (facultatif)")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            HStack {
                                TextField("0", value: $vm.formCalories, format: .number)
                                    .keyboardType(.numberPad)
                                    .font(VitaFont.body())
                                    .padding(VitaSpacing.md)
                                    .background(VitaColor.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                                    .frame(width: 120)
                                Text("kcal")
                                    .font(VitaFont.body())
                                    .foregroundColor(VitaColor.textTertiary)
                                Spacer()
                            }
                        }

                        // Restaurant
                        Toggle(isOn: $vm.formIsRestaurant) {
                            Text("Au restaurant")
                                .font(VitaFont.body())
                                .foregroundColor(VitaColor.textPrimary)
                        }
                        .tint(VitaColor.accent)

                        Button("Enregistrer ce repas") {
                            Task {
                                let ok = await vm.saveMeal()
                                if ok { dismiss() }
                            }
                        }
                        .buttonStyle(VitaPrimaryButtonStyle())
                        .disabled(vm.isSaving || vm.formDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.vertical, VitaSpacing.lg)
                }
            }
            .navigationTitle("Repas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(VitaColor.textSecondary)
                }
            }
        }
    }
}
