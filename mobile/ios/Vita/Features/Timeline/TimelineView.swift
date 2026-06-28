import SwiftUI

// MARK: — Écran principal

struct TimelineView: View {
    @StateObject private var vm = TimelineViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    DateNavigator(
                        label: vm.displayedDate,
                        canGoForward: vm.canGoToNextDay,
                        onBack: vm.goToPreviousDay,
                        onForward: vm.goToNextDay
                    )
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.vertical, VitaSpacing.sm)

                    if vm.isLoading {
                        Spacer()
                        ProgressView()
                            .tint(VitaColor.accent)
                        Spacer()
                    } else if vm.events.isEmpty {
                        EmptyTimelineView()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(vm.events.enumerated()), id: \.element.id) { index, event in
                                    TimelineRow(
                                        event: event,
                                        isLast: index == vm.events.count - 1
                                    )
                                }
                            }
                            .padding(.horizontal, VitaSpacing.lg)
                            .padding(.vertical, VitaSpacing.md)
                        }
                        .refreshable { await vm.load() }
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await vm.load() }
        }
    }
}

// MARK: — Navigateur de date

private struct DateNavigator: View {
    let label: String
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VitaColor.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(VitaColor.surface)
                    .clipShape(Circle())
            }

            Spacer()

            Text(label)
                .font(VitaFont.headline(17))
                .foregroundColor(VitaColor.textPrimary)

            Spacer()

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(canGoForward ? VitaColor.textSecondary : VitaColor.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(VitaColor.surface)
                    .clipShape(Circle())
            }
            .disabled(!canGoForward)
        }
    }
}

// MARK: — Ligne d'événement

private struct TimelineRow: View {
    let event: TimelineEvent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // Heure
            Text(event.displayTime)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(VitaColor.textTertiary)
                .frame(width: 38, alignment: .trailing)
                .padding(.top, 3)

            // Ligne verticale + point
            TimelineStem(color: event.accentColor.swiftColor, isLast: isLast)

            // Carte
            TimelineCard(event: event)
                .padding(.leading, VitaSpacing.sm)
                .padding(.bottom, isLast ? VitaSpacing.sm : VitaSpacing.lg)
        }
    }
}

// MARK: — Tige (ligne + point)

private struct TimelineStem: View {
    let color: Color
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
                .padding(.horizontal, 10)

            if !isLast {
                Rectangle()
                    .fill(VitaColor.neutral.opacity(0.25))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 14)
            }
        }
        .frame(width: 29)
    }
}

// MARK: — Carte d'événement

private struct TimelineCard: View {
    let event: TimelineEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: VitaSpacing.xs) {
                Image(systemName: event.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(event.accentColor.swiftColor)

                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VitaColor.textPrimary)
            }

            if let sub = event.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(VitaColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: — État vide

private struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: VitaSpacing.md) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundColor(VitaColor.textTertiary)
            Text("Aucun événement")
                .font(VitaFont.headline())
                .foregroundColor(VitaColor.textPrimary)
            Text("Les événements de ta journée\napparaîtront ici au fil du temps.")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.xl)
    }
}

// MARK: — Extension couleur

extension VitaTimelineColor {
    var swiftColor: Color {
        switch self {
        case .accent:    return VitaColor.accent
        case .activity:  return .orange
        case .sleep:     return Color(red: 0.37, green: 0.36, blue: 0.90) // indigo doux
        case .nutrition: return Color(red: 0.20, green: 0.73, blue: 0.44) // vert
        case .purple:    return Color(red: 0.60, green: 0.32, blue: 0.88)
        }
    }
}
