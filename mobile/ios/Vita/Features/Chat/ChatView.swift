import SwiftUI

// MARK: — Interface conversationnelle VITA
// Permet de poser des questions naturelles sur sa santé

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Suggestions rapides (si conversation vide)
                    if vm.messages.isEmpty {
                        SuggestionsList { suggestion in
                            vm.send(suggestion)
                        }
                    } else {
                        // Historique des messages
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: VitaSpacing.md) {
                                    ForEach(vm.messages) { message in
                                        MessageBubble(message: message)
                                            .id(message.id)
                                    }
                                    if vm.isTyping {
                                        TypingIndicator()
                                    }
                                }
                                .padding(VitaSpacing.md)
                            }
                            .onChange(of: vm.messages.count) { _ in
                                withAnimation(.vitaFast) {
                                    proxy.scrollTo(vm.messages.last?.id)
                                }
                            }
                        }
                    }

                    // Barre de saisie
                    InputBar(text: $vm.inputText, isLoading: vm.isTyping) {
                        vm.send(vm.inputText)
                    }
                    .focused($isInputFocused)
                }
            }
            .navigationTitle("VITA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Effacer") {
                        vm.clearConversation()
                    }
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
                    .disabled(vm.messages.isEmpty)
                }
            }
        }
    }
}

// MARK: — Suggestions rapides

private struct SuggestionsList: View {
    let onSelect: (String) -> Void

    let suggestions = [
        ("Pourquoi suis-je fatigué cette semaine ?", "moon.zzz.fill"),
        ("Pourquoi je stagne au développé couché ?", "dumbbell.fill"),
        ("Que dois-je manger aujourd'hui ?", "fork.knife"),
        ("Mon sommeil est-il suffisant ?", "chart.line.uptrend.xyaxis"),
        ("Pourquoi mon poids augmente ?", "scalemass.fill"),
        ("Suis-je en train de surentraîner ?", "figure.run"),
    ]

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()

            VStack(spacing: VitaSpacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundColor(VitaColor.accent)

                Text("Pose-moi une question")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)

                Text("J'analyse tes données pour te répondre avec précision.")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.lg)
            }

            VStack(spacing: VitaSpacing.sm) {
                ForEach(suggestions, id: \.0) { suggestion, icon in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .foregroundColor(VitaColor.accent)
                                .frame(width: 24)
                            Text(suggestion)
                                .font(VitaFont.body())
                                .foregroundColor(VitaColor.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundColor(VitaColor.textTertiary)
                        }
                        .padding(VitaSpacing.md)
                        .vitaCard()
                    }
                }
            }
            .padding(.horizontal, VitaSpacing.lg)

            Spacer()
        }
    }
}

// MARK: — Bulle de message

private struct MessageBubble: View {
    let message: ChatMessage
    @State private var showExplainability = false

    var body: some View {
        HStack(alignment: .bottom, spacing: VitaSpacing.sm) {
            if message.role == .assistant {
                Circle()
                    .fill(VitaColor.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("V")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: VitaSpacing.xs) {
                Text(message.content)
                    .font(VitaFont.body())
                    .foregroundColor(message.role == .user ? .white : VitaColor.textPrimary)
                    .padding(VitaSpacing.md)
                    .background(message.role == .user ? VitaColor.accent : VitaColor.surface)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: VitaRadius.lg,
                            style: .continuous
                        )
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)

                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.textTertiary)

                if message.role == .assistant && !message.contextCategories.isEmpty {
                    Button {
                        showExplainability = true
                    } label: {
                        Text("Pourquoi ?")
                            .font(VitaFont.caption(11))
                            .foregroundColor(VitaColor.textTertiary)
                            .underline()
                    }
                    .sheet(isPresented: $showExplainability) {
                        ExplainabilitySheet(categories: message.contextCategories)
                    }
                }
            }

            if message.role == .user { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: — Indicateur de frappe

private struct TypingIndicator: View {
    @State private var opacity1 = 0.3
    @State private var opacity2 = 0.3
    @State private var opacity3 = 0.3

    var body: some View {
        HStack(alignment: .bottom, spacing: VitaSpacing.sm) {
            Circle()
                .fill(VitaColor.accent)
                .frame(width: 28, height: 28)
                .overlay(Text("V").font(.system(size: 13, weight: .bold)).foregroundColor(.white))

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(VitaColor.textTertiary)
                        .frame(width: 7, height: 7)
                        .opacity(i == 0 ? opacity1 : i == 1 ? opacity2 : opacity3)
                }
            }
            .padding(VitaSpacing.md)
            .background(VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))

            Spacer()
        }
        .onAppear { animateDots() }
    }

    private func animateDots() {
        let delay = 0.15
        withAnimation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0)) {
            opacity1 = 1
        }
        withAnimation(Animation.easeInOut(duration: 0.5).repeatForever().delay(delay)) {
            opacity2 = 1
        }
        withAnimation(Animation.easeInOut(duration: 0.5).repeatForever().delay(delay * 2)) {
            opacity3 = 1
        }
    }
}

// MARK: — Barre de saisie

private struct InputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            TextField("Pose ta question...", text: $text, axis: .vertical)
                .font(VitaFont.body())
                .lineLimit(1...4)
                .padding(VitaSpacing.md)
                .background(VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
                .onSubmit { if !text.isEmpty { onSend() } }

            Button {
                onSend()
            } label: {
                Image(systemName: isLoading ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(text.isEmpty ? VitaColor.neutral : VitaColor.accent)
            }
            .disabled(text.isEmpty || isLoading)
        }
        .padding(.horizontal, VitaSpacing.md)
        .padding(.vertical, VitaSpacing.sm)
        .background(VitaColor.background)
    }
}
