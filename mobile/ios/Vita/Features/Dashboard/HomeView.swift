import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: VitaSpacing.md) {

                        HeaderSection(firstName: vm.firstName)

                        FirstEncounterCard()

                        ClimateEntryCard()

                        if let voice = vm.vitaVoice {
                            VitaVoiceCard(text: voice)
                        }

                        if let reco = vm.recommendation {
                            RecommendationCard(recommendation: reco) {
                                vm.markRecommendationDone()
                            }
                        } else if !vm.checkinDone {
                            CheckInPromptCard()
                        }

                        MetricsRow(
                            sleepHours: vm.avgSleepHours,
                            energy: vm.avgEnergy,
                            stress: vm.avgStress,
                            sessions: vm.activitySessions
                        )

                        if !vm.newPatterns.isEmpty {
                            PatternDiscoveryCard(patterns: vm.newPatterns)
                        }

                        MonHistoireEntryCard()

                        ReflectionEntryCard()

                        #if DEBUG
                        MemoryInspectorEntryCard()
                        #endif

                        QuickLogBar()
                    }
                    .padding(.bottom, VitaSpacing.xxl)
                }
                .refreshable { await vm.load() }
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6  { return "Bonne nuit" }
        if hour < 12 { return "Bonjour" }
        if hour < 18 { return "Bon après-midi" }
        return "Bonsoir"
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(firstName.isEmpty ? greeting : "\(greeting), \(firstName)")
                    .font(VitaFont.title(22))
                    .foregroundColor(VitaColor.textPrimary)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month()))
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
        .padding(.top, VitaSpacing.lg)
    }
}

// MARK: — Voix VITA

private struct VitaVoiceCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: VitaSpacing.sm) {
            Image(systemName: "eye")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(VitaColor.accent)
                .frame(width: 20)
                .padding(.top, 2)

            Text(text)
                .font(VitaFont.body(15))
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.accentLight.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.lg)
                .stroke(VitaColor.accentLight.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Recommandation

private struct RecommendationCard: View {
    let recommendation: WeekReco
    let onDone: () -> Void

    @State private var isDone = false

    private var actionIcon: String {
        switch recommendation.actionType {
        case "rest":      return "bed.double.fill"
        case "adjust":    return "slider.horizontal.3"
        case "avoid":     return "xmark.circle"
        case "celebrate": return "star.fill"
        default:          return "arrow.right.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.md) {
            Label("Ce que VITA observe", systemImage: actionIcon)
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.accent)

            Text(recommendation.content)
                .font(VitaFont.body(16))
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(4)

            if let actions = recommendation.actions, !actions.isEmpty {
                Divider()
                    .background(VitaColor.neutral.opacity(0.2))

                VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                    Text("Pour aujourd'hui")
                        .font(VitaFont.caption(11))
                        .foregroundColor(VitaColor.textSecondary)
                        .padding(.bottom, 2)

                    ForEach(Array(actions.prefix(3).enumerated()), id: \.offset) { index, action in
                        HStack(alignment: .top, spacing: VitaSpacing.sm) {
                            Text("\(index + 1)")
                                .font(VitaFont.mono(12))
                                .foregroundColor(VitaColor.accent)
                                .frame(width: 16, alignment: .leading)
                            Text(action)
                                .font(VitaFont.body(14))
                                .foregroundColor(VitaColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Button {
                withAnimation(.vitaFast) { isDone = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDone()
            } label: {
                Label(
                    isDone ? "Noté !" : "Je le fais",
                    systemImage: isDone ? "checkmark" : "hand.thumbsup"
                )
                .font(VitaFont.caption())
                .foregroundColor(isDone ? .white : VitaColor.accent)
                .padding(.horizontal, VitaSpacing.md)
                .padding(.vertical, VitaSpacing.sm)
                .background(isDone ? VitaColor.accent : VitaColor.accentLight.opacity(0.3))
                .clipShape(Capsule())
            }
        }
        .padding(VitaSpacing.lg)
        .vitaCard()
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Invitation check-in

private struct CheckInPromptCard: View {
    @State private var showCheckIn = false

    var body: some View {
        Button { showCheckIn = true } label: {
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

// MARK: — Métriques

private struct MetricsRow: View {
    let sleepHours: Double?
    let energy: Double?
    let stress: Double?
    let sessions: Int?

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            MetricPill(
                icon: "moon.fill",
                value: sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                label: "Sommeil",
                color: VitaColor.accent
            )
            MetricPill(
                icon: "bolt.fill",
                value: energy.map { String(format: "%.1f", $0) } ?? "—",
                label: "Énergie",
                color: VitaColor.warning
            )
            MetricPill(
                icon: "waveform.path.ecg",
                value: stress.map { String(format: "%.1f", $0) } ?? "—",
                label: "Stress",
                color: stress.map { $0 >= 4 ? VitaColor.warning : VitaColor.textSecondary } ?? VitaColor.textSecondary
            )
            if let n = sessions {
                MetricPill(
                    icon: "dumbbell.fill",
                    value: "\(n)",
                    label: "Séances",
                    color: VitaColor.accentDark
                )
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct MetricPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: VitaSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16))
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

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Label("VITA a remarqué", systemImage: "sparkles")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.warning)

            Text(patterns[0].description)
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

// MARK: — Climat intérieur du jour

private struct ClimateEntryCard: View {
    @StateObject private var vm = DailyInsightViewModel()

    var body: some View {
        NavigationLink(destination: DailyInsightView()) {
            HStack(spacing: VitaSpacing.md) {

                // Icône dynamique selon le climat disponible
                if case .available(let insight) = vm.state {
                    Image(systemName: insight.typedClimate.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(insight.typedClimate.accentColor)
                        .frame(width: 28)
                } else {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(VitaColor.accentLight)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Climat intérieur")
                        .font(VitaFont.headline())
                        .foregroundColor(VitaColor.textPrimary)

                    Group {
                        switch vm.state {
                        case .available(let insight):
                            Text(insight.typedClimate.label)
                                .font(VitaFont.caption())
                                .foregroundColor(insight.typedClimate.accentColor)
                        case .loading, .idle:
                            Text("Chargement…")
                                .font(VitaFont.caption())
                                .foregroundColor(VitaColor.textTertiary)
                        default:
                            Text("Générer la synthèse du jour")
                                .font(VitaFont.caption())
                                .foregroundColor(VitaColor.textSecondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VitaColor.textTertiary)
            }
            .padding(VitaSpacing.md)
            .vitaCard()
        }
        .padding(.horizontal, VitaSpacing.lg)
        .task { await vm.load() }
    }
}

// MARK: — Réflexion hebdomadaire

private struct ReflectionEntryCard: View {
    var body: some View {
        NavigationLink(destination: WeeklyReflectionView()) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Réflexion de la semaine")
                        .font(VitaFont.headline())
                        .foregroundColor(VitaColor.textPrimary)
                    Text("Un regard de VITA sur ta semaine")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textSecondary)
                }
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(VitaColor.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VitaColor.textTertiary)
            }
            .padding(VitaSpacing.md)
            .vitaCard()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Mon Histoire

private struct MonHistoireEntryCard: View {
    var body: some View {
        NavigationLink(destination: LifeStoryView()) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mon Histoire")
                        .font(VitaFont.headline())
                        .foregroundColor(VitaColor.textPrimary)
                    Text("Ce que VITA a retenu de toi")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textSecondary)
                }
                Spacer()
                Image(systemName: "book.closed.fill")
                    .foregroundColor(VitaColor.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VitaColor.textTertiary)
            }
            .padding(VitaSpacing.md)
            .vitaCard()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Memory Inspector (DEBUG uniquement)

#if DEBUG
private struct MemoryInspectorEntryCard: View {
    var body: some View {
        NavigationLink(destination: MemoryInspectorView()) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: VitaSpacing.xs) {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 12))
                            .foregroundColor(VitaColor.warning)
                        Text("Memory Inspector")
                            .font(VitaFont.headline())
                            .foregroundColor(VitaColor.textPrimary)
                    }
                    Text("Mémoires longue durée — DEBUG")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VitaColor.textTertiary)
            }
            .padding(VitaSpacing.md)
            .background(VitaColor.warning.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.lg)
                    .stroke(VitaColor.warning.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}
#endif

// MARK: — Première Rencontre (carte d'invitation)

private struct FirstEncounterCard: View {
    @State private var isComplete = UserDefaults.standard.bool(forKey: "vita.first_encounter.complete")
    @State private var showEncounter = false

    var body: some View {
        Group {
            if !isComplete {
                Button {
                    showEncounter = true
                } label: {
                    HStack(spacing: VitaSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(VitaColor.accent.opacity(0.10))
                                .frame(width: 40, height: 40)
                            Image(systemName: "person.and.arrow.left.and.arrow.right")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(VitaColor.accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Première rencontre")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            Text("VITA aimerait te connaître mieux")
                                .font(VitaFont.caption())
                                .foregroundColor(VitaColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(VitaColor.textTertiary)
                    }
                    .padding(VitaSpacing.md)
                    .vitaCard()
                }
                .padding(.horizontal, VitaSpacing.lg)
            }
        }
        .fullScreenCover(isPresented: $showEncounter) {
            NavigationStack {
                FirstEncounterView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Plus tard") { showEncounter = false }
                                .foregroundColor(VitaColor.textSecondary)
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitaFirstEncounterComplete)) { _ in
            isComplete = true
            showEncounter = false
        }
    }
}

// MARK: — Log rapide

private struct QuickLogBar: View {
    @State private var activeSheet: QuickLogSheet?

    enum QuickLogSheet: Identifiable {
        case sleep, activity, nutrition
        var id: Self { self }
    }

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            QuickLogButton(icon: "moon.fill", label: "Sommeil") { activeSheet = .sleep }
            QuickLogButton(icon: "dumbbell.fill", label: "Sport")  { activeSheet = .activity }
            QuickLogButton(icon: "fork.knife", label: "Repas")     { activeSheet = .nutrition }
        }
        .padding(.horizontal, VitaSpacing.lg)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sleep:     QuickLogPlaceholderSheet(title: "Sommeil",   icon: "moon.fill")
            case .activity:  QuickLogPlaceholderSheet(title: "Activité",  icon: "dumbbell.fill")
            case .nutrition: QuickLogPlaceholderSheet(title: "Repas",     icon: "fork.knife")
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
                    .font(.system(size: 18))
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

private struct QuickLogPlaceholderSheet: View {
    let title: String
    let icon: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()
                VStack(spacing: VitaSpacing.lg) {
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(VitaColor.accentLight)
                    VStack(spacing: VitaSpacing.xs) {
                        Text(title)
                            .font(VitaFont.headline())
                            .foregroundColor(VitaColor.textPrimary)
                        Text("Cette section sera disponible prochainement.")
                            .font(VitaFont.body())
                            .foregroundColor(VitaColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.horizontal, VitaSpacing.xl)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(VitaColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
