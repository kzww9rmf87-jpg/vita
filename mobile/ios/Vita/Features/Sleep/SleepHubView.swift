import SwiftUI

struct SleepHubView: View {
    @StateObject private var sleepVM = SleepViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VitaSpacing.lg) {

                    // Mon rythme
                    NavigationLink(destination: SleepRhythmView()) {
                        HubCard(
                            icon: "moon.circle.fill",
                            title: "Mon rythme",
                            subtitle: rhythmSubtitle,
                            color: VitaColor.accent
                        )
                    }
                    .buttonStyle(.plain)

                    // Mes nuits
                    NavigationLink(destination: SleepView()) {
                        HubCard(
                            icon: "moon.stars.fill",
                            title: "Mes nuits",
                            subtitle: nightsSubtitle,
                            badge: nightsBadge,
                            color: .indigo
                        )
                    }
                    .buttonStyle(.plain)

                    // Routine du soir
                    NavigationLink(destination: EveningRoutineView()) {
                        HubCard(
                            icon: "sparkles",
                            title: "Routine du soir",
                            subtitle: "Préparer une bonne nuit",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)

                    // Récupération
                    NavigationLink(destination: SleepRecoveryView()) {
                        HubCard(
                            icon: "bolt.heart.fill",
                            title: "Récupération",
                            subtitle: "Qualité et récupération",
                            color: .pink
                        )
                    }
                    .buttonStyle(.plain)

                    // Tendances
                    NavigationLink(destination: SleepTrendsView()) {
                        HubCard(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Tendances",
                            subtitle: "Évolution sur le long terme",
                            color: .teal
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(VitaSpacing.md)
            }
            .navigationTitle("Sommeil")
        }
        .task { await sleepVM.loadHistory() }
    }

    private var rhythmSubtitle: String {
        guard let latest = sleepVM.latest else { return "Aucune donnée récente" }
        return sleepVM.durationLabel(latest.durationMinutes)
    }

    private var nightsSubtitle: String {
        let n = sleepVM.entries.count
        return n == 0 ? "Commencer à enregistrer" : "\(n) nuit\(n > 1 ? "s" : "") enregistrée\(n > 1 ? "s" : "")"
    }

    private var nightsBadge: String? {
        guard let latest = sleepVM.latest else { return nil }
        return sleepVM.durationLabel(latest.durationMinutes)
    }
}

// MARK: — Carte hub

private struct HubCard: View {
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

// MARK: — Sous-vues placeholder

struct SleepRhythmView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: VitaSpacing.lg) {
                Image(systemName: "moon.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(VitaColor.accent)
                Text("Mon rythme")
                    .font(VitaFont.headline(20))
                    .foregroundStyle(VitaColor.textPrimary)
                Text("Votre rythme circadien et vos heures idéales de coucher arrivent bientôt.")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VitaColor.background)
            .navigationTitle("Mon rythme")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct EveningRoutineView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: VitaSpacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)
                Text("Routine du soir")
                    .font(VitaFont.headline(20))
                    .foregroundStyle(VitaColor.textPrimary)
                Text("Des rituels personnalisés pour préparer une meilleure nuit arrivent bientôt.")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VitaColor.background)
            .navigationTitle("Routine du soir")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SleepRecoveryView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: VitaSpacing.lg) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.pink)
                Text("Récupération")
                    .font(VitaFont.headline(20))
                    .foregroundStyle(VitaColor.textPrimary)
                Text("L'analyse de qualité de récupération et de votre dette de sommeil arrive bientôt.")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VitaColor.background)
            .navigationTitle("Récupération")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SleepTrendsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: VitaSpacing.lg) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.teal)
                Text("Tendances")
                    .font(VitaFont.headline(20))
                    .foregroundStyle(VitaColor.textPrimary)
                Text("L'analyse de vos tendances de sommeil sur le long terme arrive bientôt.")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VitaColor.background)
            .navigationTitle("Tendances")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
