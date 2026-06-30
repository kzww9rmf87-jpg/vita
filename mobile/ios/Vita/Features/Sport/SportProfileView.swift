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
                        motivationSection
                        activitiesSection
                        rejectedActivitiesSection
                        preferredContextSection
                        apprehensionSection
                        scheduleSection
                        realisticTimeSection
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

    private var motivationSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Objectif de départ")
            Text("Ce qui te motive à bouger, sans jugement.")
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
            ForEach(vm.motivationOptions, id: \.id) { opt in
                let selected = vm.formMotivation == opt.id
                Button {
                    vm.formMotivation = selected ? nil : opt.id
                } label: {
                    HStack {
                        Text(opt.label)
                            .font(VitaFont.body())
                            .foregroundStyle(selected ? Color.white : VitaColor.textPrimary)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(VitaSpacing.md)
                    .background(selected ? VitaColor.accent : VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }
                .buttonStyle(.plain)
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

    private var rejectedActivitiesSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Activités à éviter")
            Text("VITA ne les proposera jamais.")
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: VitaSpacing.sm) {
                ForEach(vm.suggestedActivities, id: \.self) { name in
                    let selected = vm.formRejectedActivities.contains(name)
                    Button(name) {
                        vm.toggleRejectedActivity(name)
                    }
                    .font(VitaFont.body())
                    .foregroundStyle(selected ? Color.white : VitaColor.textSecondary)
                    .padding(.vertical, VitaSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(selected ? Color.red.opacity(0.7) : VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                }
            }
        }
    }

    private var preferredContextSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Contexte préféré")
            Text("Plusieurs choix possibles.")
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: VitaSpacing.sm) {
                ForEach(vm.contextOptions, id: \.id) { opt in
                    let selected = vm.formPreferredContext.contains(opt.id)
                    Button(opt.label) {
                        vm.togglePreferredContext(opt.id)
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

    private var apprehensionSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader("Appréhension face à l'activité physique")
            HStack(spacing: VitaSpacing.sm) {
                ForEach(vm.apprehensionOptions, id: \.id) { opt in
                    let selected = vm.formApprehension == opt.id
                    Button(opt.label) {
                        vm.formApprehension = opt.id
                    }
                    .font(VitaFont.caption())
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

    private var realisticTimeSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            HStack {
                SectionHeader("Temps réaliste par séance")
                Spacer()
                if let t = vm.formRealisticTime {
                    Text("\(t) min")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(VitaColor.textSecondary)
                } else {
                    Text("Non défini")
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                }
            }
            Slider(value: Binding(
                get: { Double(vm.formRealisticTime ?? 30) },
                set: { vm.formRealisticTime = Int($0) }
            ), in: 10...120, step: 5)
            .tint(VitaColor.accent)
            Button("Ne pas préciser") {
                vm.formRealisticTime = nil
            }
            .font(VitaFont.caption())
            .foregroundStyle(VitaColor.textSecondary)
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
