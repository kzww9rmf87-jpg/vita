import SwiftUI

// MARK: — Onboarding VITA — < 5 minutes, zéro friction

struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Indicateur de progression
                OnboardingProgressBar(current: vm.step, total: OnboardingStep.allCases.count)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.md)

                Spacer()

                // Étape courante
                Group {
                    switch vm.currentStep {
                    case .welcome:
                        WelcomeStep(name: $vm.firstName)
                    case .goal:
                        GoalStep(goal: $vm.primaryGoal)
                    case .activity:
                        ActivityLevelStep(level: $vm.activityLevel)
                    case .healthConnect:
                        HealthConnectStep(connected: $vm.healthConnected) {
                            Task { await vm.connectHealth() }
                        }
                    case .wakeTime:
                        WakeTimeStep(time: $vm.wakeTime)
                    case .done:
                        OnboardingDoneStep()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.vitaDefault, value: vm.step)

                Spacer()

                // Bouton action
                VStack(spacing: VitaSpacing.sm) {
                    Button(vm.buttonLabel) {
                        Task { await vm.advance() }
                    }
                    .buttonStyle(VitaPrimaryButtonStyle())
                    .disabled(vm.isLoading || !vm.canAdvance)

                    if vm.step > 0 {
                        Button("Retour") {
                            withAnimation(.vitaDefault) { vm.back() }
                        }
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                    }
                }
                .padding(.horizontal, VitaSpacing.lg)
                .padding(.bottom, VitaSpacing.xl)
            }
        }
    }
}

// MARK: — Étapes

private struct WelcomeStep: View {
    @Binding var name: String

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Text("Bienvenue sur VITA")
                .font(VitaFont.title())
                .foregroundColor(VitaColor.textPrimary)

            Text("Ton coach IA personnel.\nPas de données à analyser — VITA réfléchit pour toi.")
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Comment tu t'appelles ?", text: $name)
                .font(VitaFont.headline())
                .multilineTextAlignment(.center)
                .padding(VitaSpacing.md)
                .background(VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                .textContentType(.givenName)
        }
        .padding(.horizontal, VitaSpacing.xl)
    }
}

private struct GoalStep: View {
    @Binding var goal: String

    let options: [(String, String, String)] = [
        ("perform", "Performer", "bolt.fill"),
        ("lose_weight", "Perdre du poids", "arrow.down.circle.fill"),
        ("recover", "Récupérer", "heart.fill"),
        ("feel_better", "Me sentir mieux", "sun.max.fill"),
    ]

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Text("Ton objectif principal ?")
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)

            Text("VITA personnalisera tes recommandations.")
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)

            VStack(spacing: VitaSpacing.sm) {
                ForEach(options, id: \.0) { id, label, icon in
                    Button {
                        withAnimation(.vitaFast) { goal = id }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .frame(width: 28)
                                .foregroundColor(goal == id ? .white : VitaColor.accent)
                            Text(label)
                                .font(VitaFont.headline())
                            Spacer()
                            if goal == id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundColor(goal == id ? .white : VitaColor.textPrimary)
                        .padding(VitaSpacing.md)
                        .background(goal == id ? VitaColor.accent : VitaColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                    }
                }
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct ActivityLevelStep: View {
    @Binding var level: Int

    let levels: [(Int, String, String)] = [
        (1, "Sédentaire", "Peu ou pas de sport"),
        (2, "Légèrement actif", "1-2 séances/semaine"),
        (3, "Modérément actif", "3-4 séances/semaine"),
        (4, "Très actif", "5-6 séances/semaine"),
        (5, "Athlète", "Entraînement quotidien"),
    ]

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Text("Ton niveau d'activité ?")
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)

            VStack(spacing: VitaSpacing.sm) {
                ForEach(levels, id: \.0) { value, title, subtitle in
                    Button {
                        withAnimation(.vitaFast) { level = value }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(VitaFont.body())
                                Text(subtitle)
                                    .font(VitaFont.caption(12))
                                    .opacity(0.7)
                            }
                            Spacer()
                            if level == value {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(level == value ? .white : VitaColor.accent)
                            }
                        }
                        .foregroundColor(level == value ? .white : VitaColor.textPrimary)
                        .padding(VitaSpacing.md)
                        .background(level == value ? VitaColor.accent : VitaColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                    }
                }
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct HealthConnectStep: View {
    @Binding var connected: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundColor(VitaColor.accent)

            VStack(spacing: VitaSpacing.sm) {
                Text("Connecter Apple Santé ?")
                    .font(VitaFont.title(26))
                    .foregroundColor(VitaColor.textPrimary)

                Text("VITA synchronise automatiquement ton sommeil, tes pas et ta fréquence cardiaque.")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if connected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(VitaColor.success)
                    Text("Connecté")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.success)
                }
            } else {
                Button("Connecter Apple Santé", action: onConnect)
                    .buttonStyle(VitaPrimaryButtonStyle())
                    .padding(.horizontal, VitaSpacing.lg)
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct WakeTimeStep: View {
    @Binding var time: Date

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Text("Tu te lèves vers quelle heure ?")
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("VITA enverra ton check-in matin au bon moment.")
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)

            DatePicker("Heure de réveil", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct OnboardingDoneStep: View {
    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundColor(VitaColor.accent)
                .symbolEffect(.bounce)

            Text("VITA est prête")
                .font(VitaFont.title())
                .foregroundColor(VitaColor.textPrimary)

            Text("Ta première recommandation t'attend.\nBonne journée.")
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Barre de progression Onboarding

private struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: VitaSpacing.xs) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < current ? VitaColor.accent : VitaColor.neutral.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: 3)
                    .animation(.vitaDefault, value: current)
            }
        }
    }
}
