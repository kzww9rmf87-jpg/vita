import SwiftUI

// MARK: — Onboarding conversationnel
//
// Remplace l'onboarding formulaire (OnboardingView) par un dialogue
// avec VITA : bulles de messages, réponses par chips, aucun champ de formulaire
// sauf pour la saisie du prénom.

struct ConversationalOnboardingView: View {
    @StateObject private var vm = ConversationalOnboardingViewModel()
    @FocusState  private var nameFieldFocused: Bool

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // En-tête
                ConversationHeader()

                // Fil de messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            ForEach(vm.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            // Ancre invisible en bas pour l'auto-scroll
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, VitaSpacing.md)
                        .padding(.top, VitaSpacing.sm)
                        .padding(.bottom, VitaSpacing.md)
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        withAnimation(.vitaDefault) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.currentChoices.count) { _, _ in
                        withAnimation(.vitaDefault) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Divider()
                    .background(VitaColor.neutral.opacity(0.15))

                // Zone de saisie — prénom, chips, ou bouton final
                inputArea
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.md)
                    .padding(.bottom, VitaSpacing.xl)
                    .animation(.vitaDefault, value: vm.showNameInput)
                    .animation(.vitaDefault, value: vm.currentChoices.isEmpty)
                    .animation(.vitaDefault, value: vm.showDoneButton)
            }
        }
        .task {
            await vm.start()
        }
    }

    // MARK: — Zone d'entrée

    @ViewBuilder
    private var inputArea: some View {
        if vm.showNameInput {
            NameInputField(text: $vm.nameInput, focused: $nameFieldFocused) {
                Task { await vm.submitName() }
            }
            .onAppear { nameFieldFocused = true }

        } else if !vm.currentChoices.isEmpty {
            ChipsInputView(choices: vm.currentChoices) { choiceId in
                Task { await vm.select(choiceId: choiceId) }
            }

        } else if vm.showDoneButton {
            Button {
                Task { await vm.complete() }
            } label: {
                if vm.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                } else {
                    Text("Commencer avec VITA")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .buttonStyle(VitaPrimaryButtonStyle())
            .disabled(vm.isLoading)

        } else {
            // Indicateur de frappe pendant que VITA prépare sa réponse
            TypingIndicator()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: — En-tête

private struct ConversationHeader: View {
    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            ZStack {
                Circle()
                    .fill(VitaColor.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(VitaColor.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("VITA")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(VitaColor.textPrimary)
                Text("Coach de vie")
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
        .padding(.vertical, VitaSpacing.md)
        .background(VitaColor.background)
        Divider()
            .background(VitaColor.neutral.opacity(0.15))
    }
}

// MARK: — Bulle de message

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: VitaSpacing.sm) {
            if message.isVita {
                vitaBubble
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                userBubble
            }
        }
    }

    private var vitaBubble: some View {
        Text(message.text)
            .font(VitaFont.body())
            .foregroundColor(VitaColor.textPrimary)
            .padding(.horizontal, VitaSpacing.md)
            .padding(.vertical, VitaSpacing.sm + 2)
            .background(VitaColor.surface)
            .clipShape(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .cornerRadii(
                        topLeft: VitaRadius.md,
                        topRight: VitaRadius.md,
                        bottomLeft: 4,
                        bottomRight: VitaRadius.md
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .stroke(VitaColor.neutral.opacity(0.15), lineWidth: 1)
            )
    }

    private var userBubble: some View {
        Text(message.text)
            .font(VitaFont.body())
            .foregroundColor(.white)
            .padding(.horizontal, VitaSpacing.md)
            .padding(.vertical, VitaSpacing.sm + 2)
            .background(VitaColor.accent)
            .clipShape(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .cornerRadii(
                        topLeft: VitaRadius.md,
                        topRight: VitaRadius.md,
                        bottomLeft: VitaRadius.md,
                        bottomRight: 4
                    )
            )
    }
}

// MARK: — Saisie du prénom

private struct NameInputField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            TextField("Ton prénom…", text: $text)
                .font(VitaFont.body())
                .textContentType(.givenName)
                .autocapitalization(.words)
                .focused(focused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .padding(.horizontal, VitaSpacing.md)
                .padding(.vertical, VitaSpacing.sm + 2)
                .background(VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: VitaRadius.md)
                        .stroke(VitaColor.neutral.opacity(0.2), lineWidth: 1)
                )

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(text.trimmingCharacters(in: .whitespaces).count >= 2
                        ? VitaColor.accent
                        : VitaColor.neutral.opacity(0.4))
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).count < 2)
        }
    }
}

// MARK: — Chips de réponse

private struct ChipsInputView: View {
    let choices: [ConversationChoice]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.sm) {
            ForEach(choices) { choice in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(choice.id)
                } label: {
                    Text(choice.label)
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VitaSpacing.md)
                        .padding(.vertical, VitaSpacing.sm + 2)
                        .background(VitaColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: VitaRadius.md)
                                .stroke(VitaColor.neutral.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: — Indicateur de frappe (···)

private struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(VitaColor.neutral.opacity(phase == i ? 0.8 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
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
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) {
                phase = 1
            }
        }
    }
}

// MARK: — Extension coins asymétriques

private extension RoundedRectangle {
    func cornerRadii(
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomLeft: CGFloat,
        bottomRight: CGFloat
    ) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topLeft,
                bottomLeading: bottomLeft,
                bottomTrailing: bottomRight,
                topTrailing: topRight
            )
        )
    }
}
