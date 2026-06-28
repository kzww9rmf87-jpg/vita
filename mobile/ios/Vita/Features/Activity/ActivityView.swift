import SwiftUI

// MARK: — Vue principale

struct ActivityView: View {
    @StateObject private var vm = ActivityViewModel()
    @State private var showQuickLog = false

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ActivityHeaderView(sessionCount: vm.weekSessionCount)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.lg)

                Divider()
                    .background(VitaColor.neutral.opacity(0.15))
                    .padding(.top, VitaSpacing.md)

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(VitaColor.accent)
                    Spacer()
                } else if vm.sessions.isEmpty {
                    ActivityEmptyStateView { showQuickLog = true }
                } else {
                    ActivityHistoryView(
                        sessions: vm.sessions,
                        durationLabel: vm.durationLabel,
                        onDelete: { s in Task { await vm.delete(s) } }
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showQuickLog) {
            ActivityQuickLogSheet(vm: vm)
        }
        .task { await vm.loadHistory() }
        .overlay(alignment: .bottomTrailing) {
            Button { showQuickLog = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(VitaColor.accent)
                    .clipShape(Circle())
                    .shadow(color: VitaColor.accent.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.trailing, VitaSpacing.lg)
            .padding(.bottom, VitaSpacing.xl)
        }
    }
}

// MARK: — En-tête

private struct ActivityHeaderView: View {
    let sessionCount: Int

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("Activité")
                    .font(VitaFont.title(22))
                    .foregroundColor(VitaColor.textPrimary)
                Text("Cette semaine")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: VitaSpacing.xs) {
                Text("\(sessionCount)")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundColor(VitaColor.textPrimary)
                Text(sessionCount == 1 ? "session" : "sessions")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }
        }
    }
}

// MARK: — État vide

private struct ActivityEmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "figure.walk")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(VitaColor.accentLight)
            VStack(spacing: VitaSpacing.xs) {
                Text("Aucune session enregistrée")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text("Tu as bougé aujourd'hui ?")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
            }
            Button("Enregistrer une session", action: onAdd)
                .buttonStyle(VitaPrimaryButtonStyle())
                .padding(.horizontal, VitaSpacing.xl)
            Spacer()
        }
    }
}

// MARK: — Historique

private struct ActivityHistoryView: View {
    let sessions: [ActivitySession]
    let durationLabel: (Int?) -> String
    let onDelete: (ActivitySession) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: VitaSpacing.sm) {
                ForEach(sessions) { session in
                    ActivitySessionRow(session: session, durationLabel: durationLabel)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(session)
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, VitaSpacing.lg)
            .padding(.vertical, VitaSpacing.md)
        }
    }
}

private struct ActivitySessionRow: View {
    let session: ActivitySession
    let durationLabel: (Int?) -> String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text(session.activityName)
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textPrimary)
                Text(formattedDate(session.date))
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: VitaSpacing.xs) {
                Text(durationLabel(session.durationMinutes))
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundColor(VitaColor.textSecondary)
                if let rpe = session.rpe {
                    Text("Effort \(rpe)/10")
                        .font(VitaFont.caption(11))
                        .foregroundColor(VitaColor.textTertiary)
                }
            }
        }
        .padding(VitaSpacing.md)
        .vitaCard()
    }

    private func formattedDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "fr_FR")
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.locale = Locale(identifier: "fr_FR")
        return out.string(from: d)
    }
}

// MARK: — Saisie rapide

struct ActivityQuickLogSheet: View {
    @ObservedObject var vm: ActivityViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.xl) {

                        // Suggestions rapides
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Type d'activité")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: VitaSpacing.sm) {
                                ForEach(vm.quickActivities, id: \.self) { name in
                                    Button(name) {
                                        vm.formName = name
                                    }
                                    .font(VitaFont.body())
                                    .foregroundColor(vm.formName == name ? .white : VitaColor.textSecondary)
                                    .padding(.vertical, VitaSpacing.sm)
                                    .frame(maxWidth: .infinity)
                                    .background(vm.formName == name ? VitaColor.accent : VitaColor.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                                }
                            }

                            TextField("Autre activité…", text: $vm.formName)
                                .font(VitaFont.body())
                                .padding(VitaSpacing.md)
                                .background(VitaColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                        }

                        // Durée
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            HStack {
                                Text("Durée")
                                    .font(VitaFont.headline())
                                    .foregroundColor(VitaColor.textPrimary)
                                Spacer()
                                Text(vm.durationLabel(vm.formDuration))
                                    .font(.system(size: 18, weight: .light, design: .rounded))
                                    .foregroundColor(VitaColor.textPrimary)
                            }
                            Slider(value: Binding(
                                get: { Double(vm.formDuration) },
                                set: { vm.formDuration = Int($0) }
                            ), in: 5...180, step: 5)
                            .tint(VitaColor.accent)
                        }

                        // Effort perçu
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Effort ressenti (\(vm.formRpe)/10)")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            Slider(value: Binding(
                                get: { Double(vm.formRpe) },
                                set: { vm.formRpe = Int($0) }
                            ), in: 1...10, step: 1)
                            .tint(VitaColor.accent)
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Notes (facultatif)")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            TextField("Ce que tu veux noter…", text: $vm.formNotes, axis: .vertical)
                                .font(VitaFont.body())
                                .lineLimit(2...4)
                                .padding(VitaSpacing.md)
                                .background(VitaColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                        }

                        Button("Enregistrer") {
                            Task {
                                let ok = await vm.save()
                                if ok { dismiss() }
                            }
                        }
                        .buttonStyle(VitaPrimaryButtonStyle())
                        .disabled(vm.isSaving || vm.formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.vertical, VitaSpacing.lg)
                }
            }
            .navigationTitle("Activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundColor(VitaColor.textSecondary)
                }
            }
        }
    }
}
