import SwiftUI

// MARK: — Écran principal VITA
// Principe : une seule recommandation visible, score global,
// 3 métriques rapides, navigation en 1 tap.

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: VitaSpacing.md) {
                        // En-tête
                        HeaderSection(
                            firstName: vm.firstName,
                            dayScore: vm.dayScore,
                            level: vm.level
                        )

                        // Recommandation du jour (élément central)
                        if let reco = vm.recommendation {
                            RecommendationCard(recommendation: reco) {
                                vm.markRecommendationDone()
                            }
                        } else if vm.checkinDone == false {
                            CheckInPromptCard()
                        }

                        // Métriques rapides (3 max)
                        HStack(spacing: VitaSpacing.sm) {
                            MetricPill(
                                icon: "moon.fill",
                                value: vm.sleepSummary,
                                label: "Sommeil",
                                color: VitaColor.accent
                            )
                            MetricPill(
                                icon: "flame.fill",
                                value: vm.activitySummary,
                                label: "Activité",
                                color: VitaColor.warning
                            )
                            MetricPill(
                                icon: "fork.knife",
                                value: vm.nutritionSummary,
                                label: "Nutrition",
                                color: .blue.opacity(0.7)
                            )
                        }
                        .padding(.horizontal, VitaSpacing.lg)

                        // Patterns détectés (si nouveau)
                        if !vm.newPatterns.isEmpty {
                            PatternDiscoveryCard(patterns: vm.newPatterns)
                        }

                        // Streaks
                        if !vm.streaks.isEmpty {
                            StreakSection(streaks: vm.streaks)
                        }

                        // Bouton log rapide
                        QuickLogBar()
                    }
                    .padding(.bottom, VitaSpacing.xxl)
                }
                .refreshable {
                    await vm.load()
                }
            }
            .navigationBarHidden(true)
            .task { await vm.load() }
            .onReceive(NotificationCenter.default.publisher(for: .vitaCheckInComplete)) { _ in
                vm.handleCheckInComplete()
            }
        }
    }
}

// MARK: — En-tête

private struct HeaderSection: View {
    let firstName: String
    let dayScore: Int
    let level: Int

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Bonjour" : hour < 18 ? "Bon après-midi" : "Bonsoir"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting) \(firstName)")
                    .font(VitaFont.title(22))
                    .foregroundColor(VitaColor.textPrimary)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month()))
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
            }

            Spacer()

            // Score du jour + niveau
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(dayScore)")
                    .font(VitaFont.mono(28))
                    .foregroundColor(scoreColor(dayScore))
                Text("Niv. \(level)")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
        .padding(.top, VitaSpacing.lg)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0..<40: return VitaColor.warning
        case 40..<70: return VitaColor.textPrimary
        default: return VitaColor.accent
        }
    }
}

// MARK: — Carte recommandation

private struct RecommendationCard: View {
    let recommendation: DailyRecommendation
    let onDone: () -> Void

    @State private var isDone = false

    var actionIcon: String {
        switch recommendation.actionType {
        case "rest": return "bed.double.fill"
        case "adjust": return "slider.horizontal.3"
        case "avoid": return "xmark.circle"
        case "celebrate": return "star.fill"
        default: return "arrow.right.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.md) {
            HStack {
                Label("Recommandation du jour", systemImage: actionIcon)
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.accent)
                Spacer()
                Text(recommendation.agentSource.capitalized)
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.textTertiary)
            }

            Text(recommendation.content)
                .font(VitaFont.body(17))
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(4)

            HStack(spacing: VitaSpacing.sm) {
                Button {
                    withAnimation(.vitaFast) { isDone = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onDone()
                } label: {
                    Label(isDone ? "Noté !" : "Je le fais", systemImage: isDone ? "checkmark" : "hand.thumbsup")
                        .font(VitaFont.caption())
                        .foregroundColor(isDone ? .white : VitaColor.accent)
                        .padding(.horizontal, VitaSpacing.md)
                        .padding(.vertical, VitaSpacing.sm)
                        .background(isDone ? VitaColor.accent : VitaColor.accentLight.opacity(0.3))
                        .clipShape(Capsule())
                }

                Spacer()

                // Barre de confiance discrète
                ConfidenceBar(value: recommendation.confidence)
            }
        }
        .padding(VitaSpacing.lg)
        .vitaCard()
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct ConfidenceBar: View {
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(i) < value * 5 ? VitaColor.accentLight : VitaColor.neutral.opacity(0.3))
                    .frame(width: 4, height: 12)
            }
        }
    }
}

// MARK: — Invitation check-in

private struct CheckInPromptCard: View {
    @State private var showCheckIn = false

    var body: some View {
        Button {
            showCheckIn = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-in du matin")
                        .font(VitaFont.headline())
                        .foregroundColor(VitaColor.textPrimary)
                    Text("20 secondes · 3 questions")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(VitaColor.accent)
            }
            .padding(VitaSpacing.lg)
            .background(VitaColor.accentLight.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.lg)
                    .stroke(VitaColor.accentLight, lineWidth: 1)
            )
        }
        .padding(.horizontal, VitaSpacing.lg)
        .sheet(isPresented: $showCheckIn) {
            MorningCheckInView()
        }
    }
}

// MARK: — Pillules métriques

private struct MetricPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: VitaSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(VitaFont.mono(15))
                .foregroundColor(VitaColor.textPrimary)
            Text(label)
                .font(VitaFont.caption(11))
                .foregroundColor(VitaColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VitaSpacing.md)
        .vitaCard()
    }
}

// MARK: — Pattern découvert

private struct PatternDiscoveryCard: View {
    let patterns: [PatternItem]
    @State private var currentIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Label("Pattern découvert", systemImage: "sparkles")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.warning)

            Text(patterns[currentIndex].description)
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(3)
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.lg)
                .stroke(VitaColor.warning.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Streaks

private struct StreakSection: View {
    let streaks: [StreakItem]

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Text("Régularité")
                .font(VitaFont.headline())
                .foregroundColor(VitaColor.textPrimary)
                .padding(.horizontal, VitaSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VitaSpacing.sm) {
                    ForEach(streaks) { streak in
                        StreakBadge(streak: streak)
                    }
                }
                .padding(.horizontal, VitaSpacing.lg)
            }
        }
    }
}

private struct StreakBadge: View {
    let streak: StreakItem

    var body: some View {
        VStack(spacing: VitaSpacing.xs) {
            Text("\(streak.currentCount)")
                .font(VitaFont.mono(22))
                .foregroundColor(streak.currentCount > 0 ? VitaColor.accent : VitaColor.textTertiary)
            Text(streak.label)
                .font(VitaFont.caption(11))
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 70)
        .padding(.vertical, VitaSpacing.md)
        .vitaCard()
    }
}

// MARK: — Barre de log rapide

private struct QuickLogBar: View {
    @State private var activeSheet: QuickLogSheet?

    enum QuickLogSheet: Identifiable {
        case sleep, activity, nutrition
        var id: Self { self }
    }

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            QuickLogButton(icon: "moon.fill", label: "Sommeil") {
                activeSheet = .sleep
            }
            QuickLogButton(icon: "dumbbell.fill", label: "Sport") {
                activeSheet = .activity
            }
            QuickLogButton(icon: "fork.knife", label: "Repas") {
                activeSheet = .nutrition
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sleep: Text("Log Sommeil — À implémenter")
            case .activity: Text("Log Sport — À implémenter")
            case .nutrition: Text("Log Nutrition — À implémenter")
            }
        }
    }
}

private struct QuickLogButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: VitaSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(VitaFont.caption(12))
            }
            .foregroundColor(VitaColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VitaSpacing.md)
            .vitaCard()
        }
    }
}

// MARK: — Modèles locaux

struct PatternItem: Identifiable {
    let id = UUID()
    let description: String
    let confidence: Double
}

struct StreakItem: Identifiable {
    let id = UUID()
    let streakType: String
    let currentCount: Int
    let label: String
}
