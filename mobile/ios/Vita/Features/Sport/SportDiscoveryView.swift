import SwiftUI

// MARK: — Vue principale

struct SportDiscoveryView: View {
    @StateObject private var vm = SportDiscoveryViewModel()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                conversationScrollView
                    .frame(maxHeight: .infinity)

                if vm.phase == .reformulating {
                    reformulationCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if vm.phase == .proposing {
                    proposalsPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if vm.phase == .completed {
                    completedPanel
                        .transition(.opacity)
                } else {
                    inputBar
                }
            }
        }
        .background(VitaColor.background)
        .navigationTitle("Découverte")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start() }
        .animation(.easeInOut(duration: 0.3), value: vm.phase)
    }

    // MARK: — Conversation

    private var conversationScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: VitaSpacing.sm) {
                    ForEach(Array(vm.exchanges.enumerated()), id: \.offset) { _, ex in
                        ChatBubble(exchange: ex)
                            .id(ex.content)
                    }
                    if vm.isLoading {
                        TypingIndicator()
                    }
                }
                .padding(VitaSpacing.md)
                .padding(.bottom, 80)
            }
            .onChange(of: vm.exchanges.count) {
                if let last = vm.exchanges.last {
                    withAnimation { proxy.scrollTo(last.content, anchor: .bottom) }
                }
            }
            .onChange(of: vm.isLoading) {
                if vm.isLoading, let last = vm.exchanges.last {
                    withAnimation { proxy.scrollTo(last.content, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: — Barre de saisie

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: VitaSpacing.sm) {
                TextField("Ta réponse…", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textPrimary)
                    .focused($inputFocused)
                    .padding(.horizontal, VitaSpacing.sm)
                    .padding(.vertical, 10)
                    .background(VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))

                Button {
                    Task {
                        let text = inputText.trimmingCharacters(in: .whitespaces)
                        inputText = ""
                        await vm.sendMessage(text)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? VitaColor.textSecondary
                            : VitaColor.accent)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
            }
            .padding(.horizontal, VitaSpacing.md)
            .padding(.vertical, VitaSpacing.sm)
            .background(VitaColor.background)
        }
    }

    // MARK: — Reformulation card

    private var reformulationCard: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: VitaSpacing.md) {
                    if let resume = vm.synthesis?.resumeValide {
                        Text(resume)
                            .font(VitaFont.body())
                            .foregroundStyle(VitaColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: VitaSpacing.sm) {
                        Button {
                            Task { await vm.confirmSynthesis() }
                        } label: {
                            Text("Oui, c'est ça")
                                .font(VitaFont.headline(15))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(VitaColor.accent)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                        }
                        .disabled(vm.isLoading)

                        Button {
                            // L'utilisateur corrige via la barre de texte qui réapparaît
                            vm.phase = .discovering
                            Task { await vm.sendMessage("Ce n'est pas tout à fait ça. Laisse-moi préciser.") }
                        } label: {
                            Text("Pas tout à fait")
                                .font(VitaFont.headline(15))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(VitaColor.surface)
                                .foregroundStyle(VitaColor.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VitaRadius.sm)
                                        .stroke(VitaColor.textSecondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .disabled(vm.isLoading)
                    }
                }
                .padding(VitaSpacing.md)
            }
            .frame(maxHeight: 280)
            .background(VitaColor.background)
        }
    }

    // MARK: — Propositions

    private var proposalsPanel: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                VStack(spacing: VitaSpacing.sm) {
                    ForEach(vm.proposals) { proposal in
                        ProposalCard(
                            proposal:  proposal,
                            accepted:  vm.acceptedNames.contains(proposal.name),
                            refused:   vm.refusedNames.contains(proposal.name),
                            onAccept:  { vm.toggleAccepted(proposal.name) },
                            onRefuse:  { vm.toggleRefused(proposal.name) }
                        )
                    }

                    if !vm.acceptedNames.isEmpty || !vm.refusedNames.isEmpty {
                        Button {
                            Task { await vm.react() }
                        } label: {
                            Text("Valider mes choix")
                                .font(VitaFont.headline(15))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(VitaColor.accent)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                        }
                        .disabled(vm.isLoading)
                        .padding(.top, VitaSpacing.xs)
                    }
                }
                .padding(VitaSpacing.md)
                .padding(.bottom, VitaSpacing.lg)
            }
            .frame(maxHeight: 420)
            .background(VitaColor.background)
        }
    }

    // MARK: — Terminé

    private var completedPanel: some View {
        VStack(spacing: VitaSpacing.md) {
            Divider()
            VStack(spacing: VitaSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(VitaColor.accent)
                Text("Découverte terminée")
                    .font(VitaFont.headline(17))
                    .foregroundStyle(VitaColor.textPrimary)
                if !vm.acceptedNames.isEmpty {
                    Text("Activités retenues : \(vm.acceptedNames.sorted().joined(separator: ", "))")
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, VitaSpacing.md)
            .padding(.bottom, VitaSpacing.lg)
        }
        .background(VitaColor.background)
    }
}

// MARK: — Bulle de conversation

private struct ChatBubble: View {
    let exchange: DiscoveryExchangeData

    private var isVita: Bool { exchange.role == "vita" }

    var body: some View {
        HStack(alignment: .top, spacing: VitaSpacing.sm) {
            if isVita {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(VitaColor.accent)
                    .frame(width: 28, height: 28)
                    .background(VitaColor.accent.opacity(0.12))
                    .clipShape(Circle())
            }

            Text(exchange.content)
                .font(VitaFont.body())
                .foregroundStyle(isVita ? VitaColor.textPrimary : VitaColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isVita ? VitaColor.surface : VitaColor.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.78,
                       alignment: isVita ? .leading : .trailing)

            if !isVita { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: isVita ? .leading : .trailing)
    }
}

// MARK: — Indicateur de saisie

private struct TypingIndicator: View {
    @State private var dots = ""
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(VitaColor.accent)
                .frame(width: 28, height: 28)
                .background(VitaColor.accent.opacity(0.12))
                .clipShape(Circle())

            Text("VITA réfléchit\(dots)")
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in
            dots = dots.count < 3 ? dots + "." : ""
        }
    }
}

// MARK: — Carte de proposition

private struct ProposalCard: View {
    let proposal: ActivityProposalData
    let accepted: Bool
    let refused:  Bool
    let onAccept: () -> Void
    let onRefuse: () -> Void

    private var borderColor: Color {
        if accepted { return .green }
        if refused  { return .red.opacity(0.5) }
        return Color.clear
    }

    private var constraintColor: Color {
        switch proposal.constraintLevel {
        case "tres_faible": return .green
        case "faible":      return Color(red: 0.4, green: 0.7, blue: 0.3)
        case "modere":      return .orange
        default:            return .red
        }
    }

    private var constraintLabel: String {
        switch proposal.constraintLevel {
        case "tres_faible": return "Très accessible"
        case "faible":      return "Accessible"
        case "modere":      return "Effort modéré"
        default:            return "Engagement élevé"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            HStack {
                Text(proposal.name)
                    .font(VitaFont.headline(16))
                    .foregroundStyle(VitaColor.textPrimary)
                Spacer()
                Text(constraintLabel)
                    .font(VitaFont.caption())
                    .foregroundStyle(constraintColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(constraintColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(proposal.whyItFits)
                .font(VitaFont.body())
                .foregroundStyle(VitaColor.textSecondary)

            HStack {
                Image(systemName: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(VitaColor.accent)
                Text(proposal.firstStep)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }

            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(VitaColor.accent)
                Text(proposal.frequency)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }

            HStack(spacing: VitaSpacing.sm) {
                Button(action: onAccept) {
                    Label(accepted ? "Sélectionné" : "Choisir", systemImage: accepted ? "checkmark" : "plus")
                        .font(VitaFont.caption())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accepted ? Color.green : VitaColor.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }

                Button(action: onRefuse) {
                    Label(refused ? "Refusé" : "Pas pour moi", systemImage: refused ? "xmark" : "xmark")
                        .font(VitaFont.caption())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(refused ? Color.red.opacity(0.2) : VitaColor.surface)
                        .foregroundStyle(refused ? .red : VitaColor.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: VitaRadius.sm)
                                .stroke(refused ? Color.red.opacity(0.4) : VitaColor.textSecondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.md)
                .stroke(borderColor, lineWidth: accepted || refused ? 2 : 0)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}
