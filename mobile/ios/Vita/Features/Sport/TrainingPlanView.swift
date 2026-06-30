import SwiftUI

struct TrainingPlanView: View {
    @StateObject private var vm = TrainingPlanViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(VitaColor.accent)
            } else if vm.plans.isEmpty {
                emptyState
            } else {
                planContent
            }
        }
        .navigationTitle("Plan de la semaine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(VitaColor.accent)
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showCreateSheet) {
            CreatePlanSheet(vm: vm)
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

    // MARK: — État vide

    private var emptyState: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VitaColor.accentLight)
            VStack(spacing: VitaSpacing.xs) {
                Text("Aucun plan d'entraînement")
                    .font(VitaFont.headline())
                    .foregroundStyle(VitaColor.textPrimary)
                Text("Crée une semaine type pour structurer ta pratique.")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.xl)
            }
            Button("Créer un plan") {
                vm.showCreateSheet = true
            }
            .buttonStyle(VitaPrimaryButtonStyle())
            .padding(.horizontal, VitaSpacing.xl)
            Spacer()
        }
    }

    // MARK: — Contenu plans

    private var planContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VitaSpacing.lg) {

                // Plan actif affiché en semaine
                if let active = vm.activePlan {
                    activePlanWeekView(active)
                }

                // Liste de tous les plans
                VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                    Text("Mes plans")
                        .font(VitaFont.headline())
                        .foregroundStyle(VitaColor.textPrimary)

                    ForEach(vm.plans) { plan in
                        PlanRow(
                            plan: plan,
                            onTap: { Task { await vm.loadDetail(id: plan.id) } },
                            onDelete: { Task { await vm.delete(plan) } }
                        )
                    }
                }
            }
            .padding(VitaSpacing.lg)
        }
    }

    private func activePlanWeekView(_ plan: TrainingPlanDetail) -> some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            HStack {
                Text(plan.name)
                    .font(VitaFont.headline(18))
                    .foregroundStyle(VitaColor.textPrimary)
                Spacer()
                Text("Actif")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.accent)
                    .padding(.horizontal, VitaSpacing.sm)
                    .padding(.vertical, 3)
                    .background(VitaColor.accent.opacity(0.10))
                    .clipShape(Capsule())
            }

            ForEach(0..<7, id: \.self) { day in
                let sessions = vm.sessionsForDay(day, in: plan)
                if !sessions.isEmpty {
                    DayRow(dayName: vm.dayNames[day], sessions: sessions, durationLabel: vm.durationLabel)
                }
            }
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: — Sous-vues

private struct PlanRow: View {
    let plan: TrainingPlanSummary
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textPrimary)
                if let desc = plan.description {
                    Text(desc)
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if plan.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VitaColor.accent)
            }
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .onTapGesture { onTap() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

private struct DayRow: View {
    let dayName: String
    let sessions: [TrainingPlanSessionData]
    let durationLabel: (Int) -> String

    var body: some View {
        HStack(alignment: .top, spacing: VitaSpacing.md) {
            Text(dayName)
                .font(VitaFont.caption())
                .foregroundStyle(VitaColor.textTertiary)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sessions) { s in
                    HStack {
                        Text(s.activityName)
                            .font(VitaFont.body())
                            .foregroundStyle(VitaColor.textPrimary)
                        Spacer()
                        Text(durationLabel(s.durationMin))
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: — Feuille de création

struct CreatePlanSheet: View {
    @ObservedObject var vm: TrainingPlanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                Form {
                    Section("Nom du plan") {
                        TextField("Ex : Semaine endurance", text: $vm.formName)
                    }
                    Section("Description (facultatif)") {
                        TextField("Contexte, objectif…", text: $vm.formDescription, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    Section("Séances modèles") {
                        ForEach($vm.formSessions) { $session in
                            DraftSessionRow(
                                session: $session,
                                dayNames: vm.dayNames,
                                durationLabel: vm.durationLabel
                            )
                        }
                        .onDelete { vm.removeDraftSession(at: $0) }
                        Button("Ajouter une séance") {
                            vm.addDraftSession()
                        }
                        .foregroundStyle(VitaColor.accent)
                    }
                    Section {
                        Toggle("Activer ce plan", isOn: $vm.formMakeActive)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Nouveau plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        vm.resetForm()
                        dismiss()
                    }
                    .foregroundStyle(VitaColor.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(vm.isCreating ? "…" : "Créer") {
                        Task {
                            let ok = await vm.create()
                            if ok { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(VitaColor.accent)
                    .disabled(vm.isCreating || vm.formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct DraftSessionRow: View {
    @Binding var session: TrainingPlanViewModel.DraftSession
    let dayNames: [String]
    let durationLabel: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Picker("Jour", selection: $session.dayOfWeek) {
                ForEach(0..<7, id: \.self) { Text(dayNames[$0]).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField("Activité", text: $session.activityName)

            HStack {
                Text("Durée : \(durationLabel(session.durationMin))")
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
                Slider(value: Binding(
                    get: { Double(session.durationMin) },
                    set: { session.durationMin = Int($0) }
                ), in: 10...180, step: 5)
                .tint(VitaColor.accent)
            }
        }
        .padding(.vertical, VitaSpacing.xs)
    }
}
