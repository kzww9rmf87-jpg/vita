import SwiftUI

struct TrainingWeekView: View {
    @StateObject private var planVM    = TrainingPlanViewModel()
    @StateObject private var plannerVM = TrainingPlannerViewModel()
    @StateObject private var profileVM = SportProfileViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: VitaSpacing.lg) {
                    vitaSuggestSection
                    activePlanSection
                    allPlansSection
                }
                .padding(VitaSpacing.lg)
            }
        }
        .navigationTitle("Semaine d'entraînement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    planVM.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(VitaColor.accent)
                }
            }
        }
        .task {
            async let plans: () = planVM.load()
            async let profile: () = profileVM.load()
            _ = await (plans, profile)
        }
        .sheet(isPresented: $planVM.showCreateSheet) {
            CreatePlanSheet(vm: planVM)
        }
        .sheet(isPresented: $plannerVM.showSuggestion) {
            if let plan = plannerVM.suggestedPlan {
                SuggestionSheet(plan: plan, plannerVM: plannerVM, planVM: planVM)
            }
        }
        .alert("Erreur", isPresented: .init(
            get: { planVM.errorMessage != nil || plannerVM.errorMessage != nil },
            set: { if !$0 { planVM.errorMessage = nil; plannerVM.errorMessage = nil } }
        )) {
            Button("OK") { planVM.errorMessage = nil; plannerVM.errorMessage = nil }
        } message: {
            Text(planVM.errorMessage ?? plannerVM.errorMessage ?? "")
        }
    }

    // MARK: — Sections

    private var vitaSuggestSection: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {

            // Titre de la carte
            HStack(spacing: VitaSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: VitaRadius.sm)
                        .fill(VitaColor.accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(VitaColor.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("VITA peut organiser ta semaine sportive")
                        .font(VitaFont.headline(15))
                        .foregroundStyle(VitaColor.textPrimary)
                    // Message doux si aucun profil renseigné
                    if !profileVM.isLoading && profileVM.profile == nil {
                        Text("Suggestion basée sur des valeurs par défaut. Complète ton profil pour affiner.")
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.textSecondary)
                    } else {
                        Text("Un plan adapté à tes préférences, prêt en quelques secondes.")
                            .font(VitaFont.caption())
                            .foregroundStyle(VitaColor.textSecondary)
                    }
                }
            }

            // Bouton principal — toujours visible
            Button {
                Task { await plannerVM.suggest() }
            } label: {
                HStack(spacing: VitaSpacing.sm) {
                    if plannerVM.isSuggesting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("VITA organise ta semaine…")
                            .font(VitaFont.body())
                            .fontWeight(.semibold)
                    } else {
                        Text("Laisser VITA suggérer")
                            .font(VitaFont.body())
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VitaSpacing.sm)
                .background(plannerVM.isSuggesting ? VitaColor.accent.opacity(0.6) : VitaColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
            }
            .buttonStyle(.plain)
            .disabled(plannerVM.isSuggesting)
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private var activePlanSection: some View {
        if planVM.isLoading {
            ProgressView().tint(VitaColor.accent)
        } else if let active = planVM.activePlan {
            VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                HStack {
                    Text(active.name)
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
                    let sessions = planVM.sessionsForDay(day, in: active)
                    if !sessions.isEmpty {
                        ForEach(sessions) { s in
                            TrainingSessionCard(
                                session: AIPlannedSession(
                                    dayOfWeek:    s.dayOfWeek,
                                    activityName: s.activityName,
                                    sessionType:  "unknown",
                                    durationMin:  s.durationMin,
                                    notes:        s.notes,
                                    sortOrder:    s.sortOrder
                                ),
                                dayName:       planVM.dayNames[day],
                                durationLabel: planVM.durationLabel(s.durationMin),
                                typeIcon:      plannerVM.sessionIconFromActivity(s.activityName)
                            )
                        }
                    }
                }
            }
            .padding(VitaSpacing.md)
            .background(VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    @ViewBuilder
    private var allPlansSection: some View {
        if !planVM.plans.isEmpty {
            VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                Text("Mes plans")
                    .font(VitaFont.headline())
                    .foregroundStyle(VitaColor.textPrimary)

                ForEach(planVM.plans) { plan in
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await planVM.delete(plan) }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: — Feuille suggestion IA

struct SuggestionSheet: View {
    let plan:      AITrainingWeekPlan
    @ObservedObject var plannerVM: TrainingPlannerViewModel
    @ObservedObject var planVM:    TrainingPlanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var planName   = "Plan VITA"
    @State private var makeActive = true

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.lg) {

                        // Message doux si plan basé sur valeurs par défaut
                        if !plan.hasProfile {
                            HStack(spacing: VitaSpacing.sm) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(VitaColor.accent)
                                Text("Ce plan est basé sur des valeurs par défaut. Complète ton profil sportif pour une proposition plus adaptée.")
                                    .font(VitaFont.caption())
                                    .foregroundStyle(VitaColor.textSecondary)
                            }
                            .padding(VitaSpacing.sm)
                            .background(VitaColor.accent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                        }

                        // Rationale
                        Text(plan.rationale)
                            .font(VitaFont.body())
                            .foregroundStyle(VitaColor.textSecondary)
                            .padding(VitaSpacing.md)
                            .background(VitaColor.accent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))

                        // Séances
                        VStack(spacing: VitaSpacing.sm) {
                            ForEach(plan.sessions) { s in
                                TrainingSessionCard(
                                    session:       s,
                                    dayName:       plannerVM.dayNames[s.dayOfWeek],
                                    durationLabel: plannerVM.durationLabel(s.durationMin),
                                    typeIcon:      plannerVM.sessionTypeIcon(s.sessionType)
                                )
                            }
                        }

                        // Nom + activation
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Enregistrer sous")
                                .font(VitaFont.headline())
                                .foregroundStyle(VitaColor.textPrimary)

                            TextField("Nom du plan", text: $planName)
                                .padding(VitaSpacing.sm)
                                .background(VitaColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))

                            Toggle("Activer ce plan", isOn: $makeActive)
                                .tint(VitaColor.accent)
                        }
                    }
                    .padding(VitaSpacing.lg)
                }
            }
            .navigationTitle("Suggestion VITA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ignorer") {
                        plannerVM.suggestedPlan  = nil
                        plannerVM.showSuggestion = false
                        dismiss()
                    }
                    .foregroundStyle(VitaColor.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(plannerVM.isSaving ? "…" : "Enregistrer") {
                        Task {
                            let ok = await plannerVM.saveAsPlan(
                                name:      planName,
                                makeActive: makeActive,
                                planVM:    planVM
                            )
                            if ok { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(VitaColor.accent)
                    .disabled(plannerVM.isSaving || planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
