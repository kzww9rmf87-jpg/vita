import SwiftUI

// MARK: — Vue principale

struct FirstEncounterView: View {
    @StateObject private var vm = FirstEncounterViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            Group {
                switch vm.state {
                case .loading:
                    EncounterLoadingView()

                case .notStarted:
                    EncounterWelcomeView {
                        Task { await vm.start() }
                    }

                case .conversation, .waitingVita:
                    EncounterConversationView(vm: vm)

                case .portrait(let text):
                    EncounterPortraitView(
                        portrait: text,
                        correctionText: $vm.correctionText,
                        onCorrect: { Task { await vm.sendCorrection() } },
                        onValidate: {
                            vm.validatePortrait()
                            dismiss()
                        }
                    )

                case .correcting:
                    EncounterLoadingView(message: "VITA révise ton portrait…")

                case .completed:
                    EncounterLoadingView(message: "Portrait enregistré.")
                        .onAppear { dismiss() }

                case .error(let message):
                    EncounterErrorView(message: message) {
                        Task { await vm.retry() }
                    }
                }
            }
            .animation(.vitaDefault, value: animationKey)
        }
        .navigationBarHidden(true)
        .task { await vm.loadSession() }
    }

    private var animationKey: String {
        switch vm.state {
        case .loading:      return "loading"
        case .notStarted:   return "notStarted"
        case .conversation: return "conversation"
        case .waitingVita:  return "waitingVita"
        case .portrait:     return "portrait"
        case .correcting:   return "correcting"
        case .completed:    return "completed"
        case .error:        return "error"
        }
    }
}

// MARK: — Écran de bienvenue (avant démarrage)

private struct EncounterWelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Spacer()

            VStack(spacing: VitaSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(VitaColor.accent.opacity(0.10))
                        .frame(width: 72, height: 72)
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(VitaColor.accent)
                }

                VStack(spacing: VitaSpacing.sm) {
                    Text("Première rencontre")
                        .font(VitaFont.title(24))
                        .foregroundColor(VitaColor.textPrimary)

                    Text("Une conversation pour mieux te connaître.\nAucun formulaire. Aucune liste.\nJuste une vraie conversation.")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            VStack(spacing: VitaSpacing.sm) {
                Button("Commencer la rencontre", action: onStart)
                    .buttonStyle(VitaPrimaryButtonStyle())
                    .padding(.horizontal, VitaSpacing.xl)

                Text("Environ 20 à 30 minutes · Tu peux faire une pause à tout moment")
                    .font(VitaFont.caption(12))
                    .foregroundColor(VitaColor.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Vue de conversation

private struct EncounterConversationView: View {
    @ObservedObject var vm: FirstEncounterViewModel
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // En-tête avec indicateur discret
            EncounterHeader(progressLabel: vm.progressLabel)

            Divider()
                .background(VitaColor.neutral.opacity(0.15))

            // Fil de messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: VitaSpacing.sm) {
                        ForEach(vm.exchanges) { exchange in
                            EncounterBubble(exchange: exchange)
                                .id(exchange.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        if case .waitingVita = vm.state {
                            EncounterTypingIndicator()
                                .id("typing")
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, VitaSpacing.md)
                    .padding(.top, VitaSpacing.sm)
                    .padding(.bottom, VitaSpacing.md)
                }
                .onChange(of: vm.exchanges.count) { _, _ in
                    withAnimation(.vitaDefault) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: vm.state) { _, _ in
                    withAnimation(.vitaDefault) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            Divider()
                .background(VitaColor.neutral.opacity(0.15))

            // Zone de saisie libre
            EncounterInputBar(
                text: $inputText,
                focused: $inputFocused,
                isDisabled: vm.isSending || vm.state == .waitingVita
            ) {
                let msg = inputText
                inputText = ""
                Task { await vm.sendMessage(msg) }
            }
            .padding(.horizontal, VitaSpacing.md)
            .padding(.top, VitaSpacing.sm)
            .padding(.bottom, VitaSpacing.lg)
        }
        .onAppear { inputFocused = false }
    }
}

// MARK: — En-tête conversation

private struct EncounterHeader: View {
    let progressLabel: String

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            ZStack {
                Circle()
                    .fill(VitaColor.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(VitaColor.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("VITA")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(VitaColor.textPrimary)
                Text(progressLabel)
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
        .padding(.vertical, VitaSpacing.md)
        .background(VitaColor.background)
    }
}

// MARK: — Bulle de message

private struct EncounterBubble: View {
    let exchange: EncounterExchange

    var body: some View {
        HStack(alignment: .bottom, spacing: VitaSpacing.sm) {
            if exchange.isVita {
                vitaBubble
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                userBubble
            }
        }
    }

    private var vitaBubble: some View {
        Text(exchange.content)
            .font(VitaFont.body())
            .foregroundColor(VitaColor.textPrimary)
            .lineSpacing(4)
            .padding(.horizontal, VitaSpacing.md)
            .padding(.vertical, VitaSpacing.sm + 2)
            .background(VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .stroke(VitaColor.neutral.opacity(0.15), lineWidth: 1)
            )
    }

    private var userBubble: some View {
        Text(exchange.content)
            .font(VitaFont.body())
            .foregroundColor(.white)
            .lineSpacing(4)
            .padding(.horizontal, VitaSpacing.md)
            .padding(.vertical, VitaSpacing.sm + 2)
            .background(VitaColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
    }
}

// MARK: — Indicateur de frappe

private struct EncounterTypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(VitaColor.neutral.opacity(phase == i ? 0.7 : 0.25))
                    .frame(width: 7, height: 7)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, VitaSpacing.md)
        .padding(.vertical, VitaSpacing.sm + 2)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.md)
                .stroke(VitaColor.neutral.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever()) { phase = 1 }
        }
    }
}

// MARK: — Barre de saisie libre

private struct EncounterInputBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let isDisabled: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: VitaSpacing.sm) {
            TextField("Ta réponse…", text: $text, axis: .vertical)
                .font(VitaFont.body())
                .lineLimit(1...5)
                .focused(focused)
                .disabled(isDisabled)
                .padding(.horizontal, VitaSpacing.md)
                .padding(.vertical, VitaSpacing.sm + 2)
                .background(VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: VitaRadius.md)
                        .stroke(VitaColor.neutral.opacity(0.2), lineWidth: 1)
                )

            Button(action: {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onSubmit()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(
                        (isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ? VitaColor.neutral.opacity(0.35)
                        : VitaColor.accent
                    )
            }
            .disabled(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: — Portrait

private struct EncounterPortraitView: View {
    let portrait: String
    @Binding var correctionText: String
    let onCorrect: () -> Void
    let onValidate: () -> Void
    @State private var showCorrection = false
    @FocusState private var correctionFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VitaSpacing.xl) {

                // Titre
                VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                    Text("Voilà ce que j'ai compris de toi.")
                        .font(VitaFont.title(22))
                        .foregroundColor(VitaColor.textPrimary)
                    Text("Par VITA — Première rencontre")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textTertiary)
                }

                Divider()
                    .background(VitaColor.neutral.opacity(0.15))

                // Corps du portrait
                Text(portrait)
                    .font(VitaFont.body(17))
                    .foregroundColor(VitaColor.textPrimary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .background(VitaColor.neutral.opacity(0.15))

                // Zone de validation et correction
                VStack(spacing: VitaSpacing.md) {
                    Text("Est-ce que je me trompe sur certains points ?")
                        .font(VitaFont.headline())
                        .foregroundColor(VitaColor.textPrimary)

                    Text("Tu peux corriger, compléter ou supprimer ce qui ne te correspond pas.")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                        .lineSpacing(3)

                    if showCorrection {
                        TextField("Ce que tu veux corriger ou ajouter…", text: $correctionText, axis: .vertical)
                            .font(VitaFont.body())
                            .lineLimit(3...8)
                            .focused($correctionFocused)
                            .padding(VitaSpacing.md)
                            .background(VitaColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: VitaRadius.md)
                                    .stroke(VitaColor.neutral.opacity(0.2), lineWidth: 1)
                            )
                            .onAppear { correctionFocused = true }

                        Button("Envoyer la correction", action: onCorrect)
                            .buttonStyle(VitaSecondaryButtonStyle())
                            .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Corriger quelque chose") {
                            withAnimation(.vitaDefault) { showCorrection = true }
                        }
                        .buttonStyle(VitaSecondaryButtonStyle())
                    }

                    Button("Ce portrait me ressemble", action: onValidate)
                        .buttonStyle(VitaPrimaryButtonStyle())
                }

                Spacer(minLength: VitaSpacing.xxl)
            }
            .padding(.horizontal, VitaSpacing.lg)
            .padding(.top, VitaSpacing.lg)
        }
    }
}

// MARK: — Chargement

private struct EncounterLoadingView: View {
    var message: String = "VITA prépare la rencontre…"

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            ProgressView()
                .tint(VitaColor.accent)
                .scaleEffect(1.2)
            Text(message)
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
            Spacer()
        }
    }
}

// MARK: — Erreur

private struct EncounterErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(VitaColor.textTertiary)

            VStack(spacing: VitaSpacing.xs) {
                Text("Rencontre indisponible")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text(message)
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Réessayer", action: onRetry)
                .buttonStyle(VitaSecondaryButtonStyle())
                .padding(.horizontal, VitaSpacing.xl)

            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}
