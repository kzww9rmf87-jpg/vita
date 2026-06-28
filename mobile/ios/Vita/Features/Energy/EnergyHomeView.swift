import SwiftUI

// MARK: — Vue principale Énergie

struct EnergyHomeView: View {
    @StateObject private var sleepVM      = SleepViewModel()
    @StateObject private var activityVM   = ActivityViewModel()
    @StateObject private var nutritionVM  = NutritionViewModel()

    @State private var activeDomain: EnergyDomain? = nil

    enum EnergyDomain { case sleep, activity, nutrition }

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.lg) {

                        // Titre
                        Text("Énergie")
                            .font(VitaFont.title(26))
                            .foregroundColor(VitaColor.textPrimary)
                            .padding(.horizontal, VitaSpacing.lg)
                            .padding(.top, VitaSpacing.lg)

                        // Trois cartes
                        VStack(spacing: VitaSpacing.md) {
                            NavigationLink(destination: SleepView()) {
                                SleepCard(vm: sleepVM)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: ActivityView()) {
                                ActivityCard(vm: activityVM)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: NutritionView()) {
                                NutritionCard(vm: nutritionVM)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, VitaSpacing.lg)

                        Spacer(minLength: VitaSpacing.xxl)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await sleepVM.loadHistory()
            await activityVM.loadHistory()
            await nutritionVM.loadToday()
        }
    }
}

// MARK: — Carte Sommeil

private struct SleepCard: View {
    @ObservedObject var vm: SleepViewModel

    var body: some View {
        HStack(spacing: VitaSpacing.md) {
            ZStack {
                Circle()
                    .fill(VitaColor.accent.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: "moon.fill")
                    .font(.system(size: 22))
                    .foregroundColor(VitaColor.accent)
            }

            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("Sommeil")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                if let latest = vm.latest {
                    Text(vm.durationLabel(latest.durationMinutes))
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                } else {
                    Text("Aucune donnée")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textTertiary)
                }
            }

            Spacer()

            if let latest = vm.latest {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Circle()
                            .fill(i <= latest.qualityScore ? VitaColor.accent : VitaColor.neutral.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(VitaColor.textTertiary)
        }
        .padding(VitaSpacing.md)
        .vitaCard()
    }
}

// MARK: — Carte Activité

private struct ActivityCard: View {
    @ObservedObject var vm: ActivityViewModel

    var body: some View {
        HStack(spacing: VitaSpacing.md) {
            ZStack {
                Circle()
                    .fill(VitaColor.accent.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: "figure.run")
                    .font(.system(size: 22))
                    .foregroundColor(VitaColor.accent)
            }

            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("Activité")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                let count = vm.weekSessionCount
                Text(count == 0 ? "Aucune session cette semaine" : "\(count) session\(count > 1 ? "s" : "") cette semaine")
                    .font(VitaFont.body())
                    .foregroundColor(count > 0 ? VitaColor.textSecondary : VitaColor.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(VitaColor.textTertiary)
        }
        .padding(VitaSpacing.md)
        .vitaCard()
    }
}

// MARK: — Carte Nutrition

private struct NutritionCard: View {
    @ObservedObject var vm: NutritionViewModel

    var body: some View {
        HStack(spacing: VitaSpacing.md) {
            ZStack {
                Circle()
                    .fill(VitaColor.accent.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: "fork.knife")
                    .font(.system(size: 22))
                    .foregroundColor(VitaColor.accent)
            }

            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("Nutrition")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                let count = vm.todayMeals.count
                if count == 0 {
                    Text("Aucun repas enregistré")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textTertiary)
                } else {
                    let cal = vm.todayCaloriesTotal
                    Text(cal > 0 ? "\(count) repas · \(cal) kcal" : "\(count) repas")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(VitaColor.textTertiary)
        }
        .padding(VitaSpacing.md)
        .vitaCard()
    }
}
