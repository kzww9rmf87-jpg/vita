import SwiftUI

// MARK: — Check-in matin
// Philosophie : 3 questions, 20 secondes maximum, UX frictionless

struct MorningCheckInView: View {
    @StateObject private var vm = MorningCheckInViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ProgressBar(current: vm.currentStep, total: 3)
                        .padding(.horizontal, VitaSpacing.lg)
                        .padding(.top, VitaSpacing.md)

                    Spacer()

                    // Question courante
                    Group {
                        switch vm.currentStep {
                        case 1:
                            SleepQualityStep(value: $vm.sleepQuality)
                        case 2:
                            EnergyStep(value: $vm.energyLevel)
                        case 3:
                            PainStep(hasPain: $vm.hasPain, areas: $vm.painAreas)
                        default:
                            EmptyView()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.vitaDefault, value: vm.currentStep)

                    Spacer()

                    // Bouton suivant / valider
                    VStack(spacing: VitaSpacing.md) {
                        if vm.currentStep < 3 {
                            Button("Continuer") {
                                withAnimation(.vitaDefault) {
                                    vm.nextStep()
                                }
                            }
                            .buttonStyle(VitaPrimaryButtonStyle())
                        } else {
                            Button("Voir ma recommandation") {
                                Task { await vm.submit() }
                            }
                            .buttonStyle(VitaPrimaryButtonStyle())
                            .disabled(vm.isSubmitting)
                        }

                        Button("Passer") {
                            withAnimation(.vitaDefault) {
                                if vm.currentStep < 3 {
                                    vm.nextStep()
                                } else {
                                    dismiss()
                                }
                            }
                        }
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                    }
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.bottom, VitaSpacing.xl)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.currentStep > 1 {
                        Button {
                            withAnimation(.vitaDefault) { vm.previousStep() }
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(VitaColor.textSecondary)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $vm.showThinking) {
                VitaThinkingView(vm: vm)
            }
            // Erreur technique (réseau, serveur…)
            .alert("Erreur", isPresented: .constant(vm.submitError != nil)) {
                Button("OK") { vm.submitError = nil }
            } message: {
                Text(vm.submitError ?? "")
            }
            // 409 : check-in déjà fait aujourd'hui — pas une erreur, un rappel
            .alert("Check-in déjà effectué", isPresented: $vm.alreadyCheckedIn) {
                Button("Voir ma recommandation") {
                    vm.showExistingRecommendation()
                }
                Button("Retour au dashboard", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Tu as déjà effectué ton check-in aujourd'hui.")
            }
        }
    }
}

// MARK: — Étape 1 : Sommeil

private struct SleepQualityStep: View {
    @Binding var value: Int

    var body: some View {
        VStack(spacing: VitaSpacing.xxl) {
            Text("Comment as-tu dormi ?")
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: VitaSpacing.md) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= value ? "moon.fill" : "moon")
                        .font(.system(size: 36))
                        .foregroundColor(star <= value ? VitaColor.accent : VitaColor.neutral)
                        .onTapGesture {
                            withAnimation(.vitaFast) { value = star }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                }
            }

            Text(sleepLabel(for: value))
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
                .animation(.vitaFast, value: value)
        }
        .padding(.horizontal, VitaSpacing.lg)
    }

    private func sleepLabel(for value: Int) -> String {
        switch value {
        case 1: return "Très mauvaise nuit"
        case 2: return "Nuit difficile"
        case 3: return "Nuit correcte"
        case 4: return "Bonne nuit"
        case 5: return "Excellente nuit"
        default: return ""
        }
    }
}

// MARK: — Étape 2 : Énergie

private struct EnergyStep: View {
    @Binding var value: Int

    let options: [(Int, String, String)] = [
        (1, "Épuisé", "battery.0percent"),
        (3, "Moyen", "battery.50percent"),
        (5, "En forme", "battery.100percent.bolt"),
    ]

    var body: some View {
        VStack(spacing: VitaSpacing.xxl) {
            Text("Ton niveau d'énergie ?")
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: VitaSpacing.md) {
                ForEach(options, id: \.0) { option in
                    EnergyButton(
                        label: option.1,
                        icon: option.2,
                        isSelected: value == option.0
                    ) {
                        withAnimation(.vitaFast) { value = option.0 }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .padding(.horizontal, VitaSpacing.md)
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct EnergyButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: VitaSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                Text(label)
                    .font(VitaFont.caption())
            }
            .foregroundColor(isSelected ? .white : VitaColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VitaSpacing.md)
            .background(isSelected ? VitaColor.accent : VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .stroke(isSelected ? Color.clear : VitaColor.neutral.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: — Étape 3 : Douleur

private struct PainStep: View {
    @Binding var hasPain: Bool
    @Binding var areas: [String]

    let bodyZones = ["Dos", "Épaule", "Genou", "Cheville", "Hanche", "Cou", "Poignet", "Autre"]

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Text("Une douleur aujourd'hui ?")
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: VitaSpacing.md) {
                PainChoiceButton(label: "Non", isSelected: !hasPain) {
                    withAnimation(.vitaFast) { hasPain = false; areas = [] }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                PainChoiceButton(label: "Oui", isSelected: hasPain) {
                    withAnimation(.vitaFast) { hasPain = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .padding(.horizontal, VitaSpacing.md)

            if hasPain {
                VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                    Text("Où ?")
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textSecondary)

                    FlowLayout(spacing: VitaSpacing.sm) {
                        ForEach(bodyZones, id: \.self) { zone in
                            ZoneChip(label: zone, isSelected: areas.contains(zone)) {
                                withAnimation(.vitaFast) {
                                    if areas.contains(zone) {
                                        areas.removeAll { $0 == zone }
                                    } else {
                                        areas.append(zone)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, VitaSpacing.lg)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

private struct PainChoiceButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(VitaFont.headline())
                .foregroundColor(isSelected ? .white : VitaColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VitaSpacing.md)
                .background(isSelected ? VitaColor.accent : VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        }
    }
}

private struct ZoneChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(VitaFont.caption())
                .padding(.horizontal, VitaSpacing.md)
                .padding(.vertical, VitaSpacing.sm)
                .foregroundColor(isSelected ? .white : VitaColor.textSecondary)
                .background(isSelected ? VitaColor.warning : VitaColor.surface)
                .clipShape(Capsule())
        }
    }
}

// MARK: — Barre de progression

private struct ProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(VitaColor.neutral.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(VitaColor.accent)
                    .frame(width: geo.size.width * CGFloat(current) / CGFloat(total), height: 3)
                    .animation(.vitaDefault, value: current)
            }
        }
        .frame(height: 3)
    }
}

// MARK: — Layout fluide pour les chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
