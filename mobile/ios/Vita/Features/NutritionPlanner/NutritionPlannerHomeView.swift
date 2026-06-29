import SwiftUI

struct NutritionPlannerHomeView: View {
    @StateObject private var mealPlanVm = MealPlannerViewModel()
    @State private var shoppingPlanId: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VitaSpacing.lg) {
                    // Carte 1 — Plan de la semaine
                    NavigationLink(destination: MealPlannerView()) {
                        PlannerCard(
                            icon: "calendar",
                            title: "Plan de la semaine",
                            subtitle: weekSubtitle,
                            badge: planBadge,
                            color: VitaColor.accent
                        )
                    }
                    .buttonStyle(.plain)

                    // Carte 2 — Recettes
                    NavigationLink(destination: RecipeLibraryView()) {
                        PlannerCard(
                            icon: "fork.knife",
                            title: "Mes recettes",
                            subtitle: "Bibliothèque de recettes",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    // Carte 3 — Liste de courses (lie au plan courant)
                    if let planId = shoppingPlanId {
                        NavigationLink(destination: ShoppingListView(planId: planId)) {
                            PlannerCard(
                                icon: "cart",
                                title: "Liste de courses",
                                subtitle: "Générée depuis le plan",
                                color: .green
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        PlannerCard(
                            icon: "cart",
                            title: "Liste de courses",
                            subtitle: "Planifiez d'abord vos repas",
                            color: VitaColor.textSecondary
                        )
                    }

                    // Carte 4 — Garde-manger
                    NavigationLink(destination: PantryView()) {
                        PlannerCard(
                            icon: "cabinet.fill",
                            title: "Garde-manger",
                            subtitle: "Ingrédients toujours disponibles",
                            color: .brown
                        )
                    }
                    .buttonStyle(.plain)

                    // Carte 5 — Profil nutritionnel
                    NavigationLink(destination: NutritionProfileView()) {
                        PlannerCard(
                            icon: "person.text.rectangle",
                            title: "Mon profil",
                            subtitle: "Préférences et organisation",
                            color: .indigo
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(VitaSpacing.md)
            }
            .navigationTitle("Organisation des repas")
        }
        .task {
            await mealPlanVm.loadPlans()
            await mealPlanVm.loadCurrentPlan()
            shoppingPlanId = mealPlanVm.currentPlan?.id
        }
    }

    private var weekSubtitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "fr_FR")
        let end = Calendar.current.date(byAdding: .day, value: 6, to: mealPlanVm.weekStart) ?? mealPlanVm.weekStart
        return "Semaine du \(fmt.string(from: mealPlanVm.weekStart)) au \(fmt.string(from: end))"
    }

    private var planBadge: String? {
        guard let count = mealPlanVm.currentPlan?.items.count, count > 0 else { return nil }
        return "\(count) repas"
    }
}

// MARK: — PlannerCard

private struct PlannerCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    let color: Color

    var body: some View {
        HStack(spacing: VitaSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: VitaRadius.sm)
                    .fill(color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VitaFont.headline(16))
                    .foregroundStyle(VitaColor.textPrimary)
                Text(subtitle)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(VitaFont.caption())
                    .foregroundStyle(color)
                    .padding(.horizontal, VitaSpacing.sm)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(VitaColor.textSecondary)
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
