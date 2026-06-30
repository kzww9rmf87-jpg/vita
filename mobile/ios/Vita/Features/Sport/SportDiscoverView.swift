import SwiftUI

// MARK: — Modèles réseau

struct ActivityOptionData: Codable, Identifiable {
    var id: String { name }
    let name: String
    let why: String
    let constraintLevel: String
    let firstStep: String
    let suggestedFrequency: String
    let sessionType: String
}

struct SportDiscoverResult: Codable {
    let options: [ActivityOptionData]
    let discoveryQuestion: String
    let usedClaude: Bool
}

// MARK: — ViewModel

@MainActor
final class SportDiscoverViewModel: ObservableObject {

    @Published var result: SportDiscoverResult?
    @Published var selected: Set<String> = []
    @Published var isLoading  = false
    @Published var isSaving   = false
    @Published var errorMessage: String?
    @Published var didSave    = false

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let data: SportDiscoverResult = try await APIClient.shared.post(
                "/sport/training-planner/discover", body: DiscoverEmptyBody()
            )
            result = data
        } catch {
            errorMessage = "VITA n'a pas pu charger les options. Réessaie dans un moment."
        }
    }

    func saveSelection() async {
        guard !isSaving, !selected.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let body = ["attractive_activities": Array(selected)]
        do {
            let _: [String: String] = try await APIClient.shared.put("/sport/profile", body: body)
            didSave = true
        } catch {
            errorMessage = "La sauvegarde a échoué."
        }
    }

    func constraintLabel(_ level: String) -> String {
        switch level {
        case "tres_faible": return "Très accessible"
        case "faible":      return "Accessible"
        case "modere":      return "Modéré"
        case "eleve":       return "Exigeant"
        default:            return level
        }
    }

    func constraintColor(_ level: String) -> Color {
        switch level {
        case "tres_faible": return .green
        case "faible":      return Color(red: 0.3, green: 0.7, blue: 0.3)
        case "modere":      return .orange
        case "eleve":       return .red
        default:            return VitaColor.textSecondary
        }
    }
}

private struct DiscoverEmptyBody: Encodable {}

// MARK: — View

struct SportDiscoverView: View {
    @StateObject private var vm = SportDiscoverViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            if vm.isLoading {
                VStack(spacing: VitaSpacing.md) {
                    ProgressView().tint(VitaColor.accent)
                    Text("VITA cherche ce qui pourrait te convenir…")
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(VitaSpacing.xl)
            } else if let result = vm.result {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.lg) {

                        // Question finale
                        Text(result.discoveryQuestion)
                            .font(VitaFont.headline(18))
                            .foregroundStyle(VitaColor.textPrimary)
                            .padding(VitaSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(VitaColor.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))

                        // Options
                        ForEach(result.options) { option in
                            OptionCard(
                                option: option,
                                isSelected: vm.selected.contains(option.name),
                                constraintLabel: vm.constraintLabel(option.constraintLevel),
                                constraintColor: vm.constraintColor(option.constraintLevel)
                            ) {
                                if vm.selected.contains(option.name) {
                                    vm.selected.remove(option.name)
                                } else {
                                    vm.selected.insert(option.name)
                                }
                            }
                        }

                        // Bouton validation
                        if !vm.selected.isEmpty {
                            Button {
                                Task { await vm.saveSelection() }
                            } label: {
                                HStack(spacing: VitaSpacing.sm) {
                                    if vm.isSaving {
                                        ProgressView().tint(.white).scaleEffect(0.85)
                                    }
                                    Text(vm.isSaving ? "Enregistrement…" : "Ces activités m'intéressent")
                                        .font(VitaFont.body())
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, VitaSpacing.sm)
                                .background(VitaColor.accent)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.isSaving)
                        }
                    }
                    .padding(VitaSpacing.lg)
                }
            } else if vm.errorMessage != nil {
                VStack(spacing: VitaSpacing.md) {
                    Text(vm.errorMessage ?? "")
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Réessayer") {
                        Task { await vm.load() }
                    }
                    .buttonStyle(VitaPrimaryButtonStyle())
                }
                .padding(VitaSpacing.xl)
            }
        }
        .navigationTitle("Trouver mon activité")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .alert("Activités enregistrées", isPresented: $vm.didSave) {
            Button("OK") { dismiss() }
        } message: {
            Text("VITA en tiendra compte pour ton prochain plan d'entraînement.")
        }
    }
}

// MARK: — Carte option

private struct OptionCard: View {
    let option: ActivityOptionData
    let isSelected: Bool
    let constraintLabel: String
    let constraintColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: VitaSpacing.sm) {

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name)
                            .font(VitaFont.headline(16))
                            .foregroundStyle(VitaColor.textPrimary)
                        Text(constraintLabel)
                            .font(VitaFont.caption())
                            .foregroundStyle(constraintColor)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(VitaColor.accent)
                    } else {
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundStyle(VitaColor.textSecondary.opacity(0.4))
                    }
                }

                Text(option.why)
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .lineLimit(4)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(option.firstStep)
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.textSecondary)
                    } icon: {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                            .foregroundStyle(VitaColor.accent)
                    }

                    Label {
                        Text(option.suggestedFrequency)
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.textSecondary)
                    } icon: {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(VitaColor.accent)
                    }
                }
            }
            .padding(VitaSpacing.md)
            .background(isSelected ? VitaColor.accent.opacity(0.06) : VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .stroke(isSelected ? VitaColor.accent : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}
