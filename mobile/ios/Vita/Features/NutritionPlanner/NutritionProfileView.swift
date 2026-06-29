import SwiftUI

struct NutritionProfileView: View {
    @StateObject private var vm = NutritionProfileViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProfileForm(vm: vm)
                }
            }
            .navigationTitle("Mon profil")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Enregistrer") {
                        Task { await vm.save() }
                    }
                    .disabled(vm.isSaving)
                }
            }
            .alert("Erreur", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
            .overlay(alignment: .top) {
                if let msg = vm.successMessage {
                    SuccessBanner(text: msg) { vm.successMessage = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, VitaSpacing.sm)
                }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: — Formulaire principal

private struct ProfileForm: View {
    @ObservedObject var vm: NutritionProfileViewModel

    var body: some View {
        Form {
            // ── Objectif ──────────────────────────────────────────────────────
            Section {
                ForEach(ObjectiveOption.allCases, id: \.self) { option in
                    ObjectiveRow(
                        option: option,
                        isSelected: vm.formObjective == option
                    ) {
                        vm.formObjective = option
                    }
                }
            } header: {
                SectionHeader(text: "Objectif")
            } footer: {
                Text("VITA utilisera cet objectif pour organiser vos repas, pas pour vous noter.")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }

            // ── Données personnelles ───────────────────────────────────────────
            Section(header: SectionHeader(text: "Informations personnelles")) {
                HStack {
                    Text("Poids (kg)")
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textPrimary)
                    Spacer()
                    TextField("Optionnel", text: $vm.formWeightKg)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textSecondary)
                        .frame(width: 100)
                }
                HStack {
                    Text("Taille (cm)")
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textPrimary)
                    Spacer()
                    TextField("Optionnel", text: $vm.formHeightCm)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textSecondary)
                        .frame(width: 100)
                }
                HStack {
                    Text("Âge")
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textPrimary)
                    Spacer()
                    TextField("Optionnel", text: $vm.formAge)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textSecondary)
                        .frame(width: 100)
                }
                Picker("Sexe", selection: $vm.formSex) {
                    Text("Non précisé").tag("")
                    Text("Homme").tag("male")
                    Text("Femme").tag("female")
                    Text("Autre").tag("other")
                }
                .font(VitaFont.body())
            }

            // ── Niveau d'activité ──────────────────────────────────────────────
            Section(header: SectionHeader(text: "Activité physique")) {
                ForEach(ActivityLevelOption.allCases, id: \.self) { option in
                    ActivityRow(
                        option: option,
                        isSelected: vm.formActivityLevel == option
                    ) {
                        vm.formActivityLevel = option
                    }
                }
            }

            // ── Organisation ──────────────────────────────────────────────────
            Section(header: SectionHeader(text: "Organisation des repas")) {
                Stepper("Repas par jour : \(vm.formMealsPerDay)", value: $vm.formMealsPerDay, in: 1...6)
                    .font(VitaFont.body())
                Toggle("Batch cooking", isOn: $vm.formBatchCooking)
                    .font(VitaFont.body())
                    .tint(VitaColor.accent)

                Picker("Temps de cuisine", selection: $vm.formCookTime) {
                    Text("Non précisé").tag(Optional<CookTimeOption>.none)
                    ForEach(CookTimeOption.allCases, id: \.self) { opt in
                        Text(opt.label).tag(Optional(opt))
                    }
                }
                .font(VitaFont.body())

                Picker("Budget", selection: $vm.formBudget) {
                    Text("Non précisé").tag(Optional<BudgetOption>.none)
                    ForEach(BudgetOption.allCases, id: \.self) { opt in
                        Text(opt.label).tag(Optional(opt))
                    }
                }
                .font(VitaFont.body())
            }

            // ── Contraintes alimentaires ───────────────────────────────────────
            Section {
                TagsField(label: "Allergies", placeholder: "lait, arachides…", text: $vm.formAllergiesText)
                TagsField(label: "Intolérances", placeholder: "gluten, lactose…", text: $vm.formIntolerancesText)
                TagsField(label: "Aliments exclus", placeholder: "porc, champignons…", text: $vm.formExcludedFoodsText)
            } header: {
                SectionHeader(text: "Contraintes alimentaires")
            } footer: {
                Text("Séparez les éléments par des virgules. Ces informations ne sortent jamais de l'application.")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }
        }
    }
}

// MARK: — Sous-vues

private struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VitaFont.caption())
            .foregroundStyle(VitaColor.textSecondary)
            .textCase(.uppercase)
    }
}

private struct ObjectiveRow: View {
    let option:     ObjectiveOption
    let isSelected: Bool
    let onSelect:   () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: VitaSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textPrimary)
                    Text(option.description)
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(VitaColor.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityRow: View {
    let option:     ActivityLevelOption
    let isSelected: Bool
    let onSelect:   () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: VitaSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(VitaFont.body())
                        .foregroundStyle(VitaColor.textPrimary)
                    Text(option.description)
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(VitaColor.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TagsField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.xs) {
            Text(label)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
            TextField(placeholder, text: $text, axis: .vertical)
                .font(VitaFont.body())
                .lineLimit(2, reservesSpace: true)
        }
        .padding(.vertical, VitaSpacing.xs)
    }
}

private struct SuccessBanner: View {
    let text:      String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: VitaSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(VitaColor.accent)
            Text(text)
                .font(VitaFont.body())
                .foregroundStyle(VitaColor.textPrimary)
        }
        .padding(.horizontal, VitaSpacing.md)
        .padding(.vertical, VitaSpacing.sm)
        .background(VitaColor.surface)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { onDismiss() }
        }
    }
}
