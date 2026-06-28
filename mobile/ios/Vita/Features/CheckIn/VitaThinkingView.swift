import SwiftUI

// MARK: — Écran de raisonnement VITA
// Affiché immédiatement après le check-in pendant que l'IA génère la recommandation.
// Les messages reflètent le raisonnement de VITA — pas un spinner générique.

struct VitaThinkingView: View {
    @ObservedObject var vm: MorningCheckInViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            if let reco = vm.recommendation {
                RecommendationReadyView(recommendation: reco, onDismiss: {
                    dismiss()
                    // Notifier HomeView pour rafraîchir
                    NotificationCenter.default.post(name: .vitaCheckInComplete, object: nil)
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            } else if vm.hasRecommendationError {
                ErrorView(onRetry: {
                    Task { await vm.loadFallbackRecommendation() }
                }, onDismiss: {
                    dismiss()
                })
            } else {
                ThinkingMessagesView(messages: vm.thinkingMessages)
            }
        }
        .animation(.vitaDefault, value: vm.recommendation != nil)
        .animation(.vitaDefault, value: vm.hasRecommendationError)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: — Messages de raisonnement animés

private struct ThinkingMessagesView: View {
    let messages: [String]

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Spacer()

            // Indicateur animé
            VitaBreathingDot()
                .padding(.bottom, VitaSpacing.md)

            // Messages empilés du plus récent vers le plus ancien
            VStack(alignment: .leading, spacing: VitaSpacing.md) {
                ForEach(Array(messages.enumerated().reversed()), id: \.offset) { index, message in
                    HStack(spacing: VitaSpacing.sm) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(VitaColor.accent)
                            .opacity(index < messages.count - 1 ? 1 : 0)

                        Text(message)
                            .font(VitaFont.body())
                            .foregroundColor(
                                index == messages.count - 1
                                    ? VitaColor.textPrimary
                                    : VitaColor.textSecondary
                            )
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, VitaSpacing.xl)
            .animation(.vitaDefault, value: messages.count)

            if messages.isEmpty {
                Text("VITA prépare ta recommandation…")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
            }

            Spacer()
            Spacer()
        }
    }
}

// MARK: — Point animé (inspiration / expiration)

private struct VitaBreathingDot: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(VitaColor.accent)
            .frame(width: 12, height: 12)
            .scaleEffect(scale)
            .opacity(0.4 + 0.6 * (scale - 0.85) / 0.3)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.3
                }
            }
    }
}

// MARK: — Recommandation prête

private struct RecommendationReadyView: View {
    let recommendation: DailyRecommendation
    let onDismiss: () -> Void

    @State private var isDone = false

    var actionIcon: String {
        switch recommendation.actionType {
        case "rest":      return "bed.double.fill"
        case "adjust":    return "slider.horizontal.3"
        case "avoid":     return "xmark.circle"
        case "celebrate": return "star.fill"
        default:          return "arrow.right.circle.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: VitaSpacing.xl) {
                Spacer(minLength: VitaSpacing.xl)

                // En-tête
                VStack(spacing: VitaSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(VitaColor.accent)
                    Text("Ce que j'observe")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textSecondary)
                }

                // Observation
                Text(recommendation.content)
                    .font(VitaFont.body(18))
                    .foregroundColor(VitaColor.textPrimary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.lg)

                // Source discrète
                Label(recommendation.agentSource.capitalized, systemImage: actionIcon)
                    .font(VitaFont.caption(12))
                    .foregroundColor(VitaColor.textTertiary)

                // 3 actions concrètes
                if !recommendation.actions.isEmpty {
                    ActionsList(actions: recommendation.actions)
                        .padding(.horizontal, VitaSpacing.lg)
                }

                Spacer(minLength: VitaSpacing.lg)

                // Boutons
                VStack(spacing: VitaSpacing.sm) {
                    Button {
                        withAnimation(.vitaFast) { isDone = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            onDismiss()
                        }
                    } label: {
                        Label(
                            isDone ? "Noté !" : "J'ai compris",
                            systemImage: isDone ? "checkmark" : "hand.thumbsup"
                        )
                    }
                    .buttonStyle(VitaPrimaryButtonStyle())
                    .padding(.horizontal, VitaSpacing.lg)

                    Button("Fermer", action: onDismiss)
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                }
                .padding(.bottom, VitaSpacing.xl)
            }
        }
    }
}

// MARK: — Liste des 3 actions concrètes

private struct ActionsList: View {
    let actions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Text("Pour aujourd'hui")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.textSecondary)
                .padding(.bottom, 2)

            ForEach(Array(actions.prefix(3).enumerated()), id: \.offset) { index, action in
                HStack(alignment: .top, spacing: VitaSpacing.sm) {
                    Text("\(index + 1)")
                        .font(VitaFont.mono(13))
                        .foregroundColor(VitaColor.accent)
                        .frame(width: 18, alignment: .leading)
                    Text(action)
                        .font(VitaFont.body(15))
                        .foregroundColor(VitaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.lg)
                .stroke(VitaColor.neutral.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: — Erreur avec fallback

private struct ErrorView: View {
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36))
                .foregroundColor(VitaColor.textTertiary)
            VStack(spacing: VitaSpacing.sm) {
                Text("Ton check-in est enregistré.")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("VITA n'a pas pu générer ta recommandation pour l'instant.")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: VitaSpacing.md) {
                Button("Réessayer", action: onRetry)
                    .buttonStyle(VitaPrimaryButtonStyle())
                Button("Fermer", action: onDismiss)
                    .buttonStyle(VitaSecondaryButtonStyle())
            }
            .padding(.horizontal, VitaSpacing.lg)
            Spacer()
        }
    }
}

// MARK: — Notification cross-composants

extension Notification.Name {
    static let vitaCheckInComplete = Notification.Name("vitaCheckInComplete")
    static let vitaOnboardingComplete = Notification.Name("vitaOnboardingComplete")
}
