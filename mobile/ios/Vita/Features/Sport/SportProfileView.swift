import SwiftUI

struct SportProfileView: View {
    @StateObject private var vm = SportProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(VitaColor.accent)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.xl) {
                        levelSection
                        activitiesSection
                        scheduleSection
                        daysSection
                        contextSection
                        saveButton
                    }
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.vertical, VitaSpacing.lg)
                }
            }
        }
        .navigationTitle("Mon profil sportif")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .alert("Profil enregistré", isPresented: $vm.savedSuccessfully) {
            Button("OK") {}
        }
        .alert("Erreur", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: — Sections

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Niveau")
            HStack(spacing: VitaSpacing.sm) {
                ForEach(vm.fitnessLevels, id: \.id) { level in
                    let selected = vm.formLevel == level.id
                    Button(level.label) {
                        vm.formLevel = level.id
                    }
                    .font(VitaFont.body())
                    .foregroundStyle(selected ? Color.white : VitaColor.textSecondary)
                    .padding(.vertical, VitaSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(selected ? VitaColor.accent : VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }
            }
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Activités préférées")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: VitaSpacing.sm) {
                ForEach(vm.suggestedActivities, id: \.self) { name in
                    let selected = vm.formActivities.contains(name)
                    Button(name) {
                        vm.toggleActivity(name)
                    }
                    .font(VitaFont.body())
                    .foregroundStyle(selected ? Color.white : VitaColor.textSecondary)
                    .padding(.vertical, VitaSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(selected ? VitaColor.accent : VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.md) {
            SectionHeader("Objectif")
            HStack {
                Text("Séances par semaine")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textPrimary)
                Spacer()
                Stepper("\(vm.formSessions)", value: $vm.formSessions, in: 1...14)
                    .labelsHidden()
                Text("\(vm.formSessions)")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundStyle(VitaColor.textPrimary)
                    .frame(width: 28)
            }
            HStack {
                Text("Durée visée")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textPrimary)
                Spacer()
                Text(durationLabel(vm.formDuration))
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundStyle(VitaColor.textPrimary)
            }
            Slider(value: Binding(
                get: { Double(vm.formDuration) },
                set: { vm.formDuration = Int($0) }
            ), in: 10...180, step: 5)
            .tint(VitaColor.accent)
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Jours disponibles")
            HStack(spacing: VitaSpacing.xs) {
                ForEach(0..<7, id: \.self) { day in
                    let selected = vm.formDays.contains(day)
                    Button(vm.dayNames[day]) {
                        vm.toggleDay(day)
                    }
                    .font(VitaFont.caption())
                    .foregroundStyle(selected ? Color.white : VitaColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? VitaColor.accent : VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Contexte (facultatif)")
            TextField("Reprise après blessure, préparation compétition…",
                      text: $vm.formContext, axis: .vertical)
                .font(VitaFont.body())
                .lineLimit(2...5)
                .padding(VitaSpacing.md)
                .background(VitaColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        }
    }

    private var saveButton: some View {
        Button(vm.isSaving ? "Enregistrement…" : "Enregistrer") {
            Task { await vm.save() }
        }
        .buttonStyle(VitaPrimaryButtonStyle())
        .disabled(vm.isSaving)
        .padding(.top, VitaSpacing.sm)
    }

    // MARK: — Utilitaires

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60; let rem = minutes % 60
        return rem == 0 ? "\(h)h" : "\(h)h\(rem)"
    }
}

// MARK: — Composant local

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(VitaFont.headline())
            .foregroundStyle(VitaColor.textPrimary)
    }
}
