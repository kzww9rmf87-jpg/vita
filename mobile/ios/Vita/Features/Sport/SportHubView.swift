import SwiftUI

struct SportHubView: View {
    @StateObject private var activityVM = ActivityViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VitaSpacing.lg) {

                    // Plan de la semaine
                    NavigationLink(destination: TrainingWeekView()) {
                        HubCard(
                            icon: "calendar",
                            title: "Plan de la semaine",
                            subtitle: weekPlanSubtitle,
                            color: VitaColor.accent
                        )
                    }
                    .buttonStyle(.plain)

                    // Mes activités
                    NavigationLink(destination: ActivityView()) {
                        HubCard(
                            icon: "figure.run",
                            title: "Mes activités",
                            subtitle: activitiesSubtitle,
                            badge: activityBadge,
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    // Mes séances
                    NavigationLink(destination: TrainingHistoryView()) {
                        HubCard(
                            icon: "dumbbell.fill",
                            title: "Mes séances",
                            subtitle: "Historique et suivi",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)

                    // Mon objectif — profil sportif
                    NavigationLink(destination: SportProfileView()) {
                        HubCard(
                            icon: "target",
                            title: "Mon objectif",
                            subtitle: "Préférences sportives",
                            color: .indigo
                        )
                    }
                    .buttonStyle(.plain)

                    // Récupération
                    NavigationLink(destination: SportRecoveryView()) {
                        HubCard(
                            icon: "heart.fill",
                            title: "Récupération",
                            subtitle: "Repos et adaptation",
                            color: .pink
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(VitaSpacing.md)
            }
            .navigationTitle("Sport")
        }
        .task { await activityVM.loadHistory() }
    }

    private var weekPlanSubtitle: String {
        let n = activityVM.weekSessionCount
        return n == 0 ? "Aucune séance cette semaine" : "\(n) séance\(n > 1 ? "s" : "") planifiée\(n > 1 ? "s" : "")"
    }

    private var activitiesSubtitle: String {
        let n = activityVM.weekSessionCount
        return n == 0 ? "Commencer à enregistrer" : "\(n) activité\(n > 1 ? "s" : "") cette semaine"
    }

    private var activityBadge: String? {
        let n = activityVM.weekSessionCount
        return n > 0 ? "\(n) cette semaine" : nil
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


struct SportRecoveryView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: VitaSpacing.lg) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.pink)
                Text("Récupération")
                    .font(VitaFont.headline(20))
                    .foregroundStyle(VitaColor.textPrimary)
                Text("Le suivi de récupération et d'adaptation arrive bientôt.")
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
