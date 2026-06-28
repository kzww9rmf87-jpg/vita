import SwiftUI

// MARK: — Vue principale

struct SleepView: View {
    @StateObject private var vm = SleepViewModel()
    @State private var showQuickLog = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SleepHeaderView(latest: vm.latest, durationLabel: vm.durationLabel)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.lg)

                Divider()
                    .background(VitaColor.neutral.opacity(0.15))
                    .padding(.top, VitaSpacing.md)

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(VitaColor.accent)
                    Spacer()
                } else if vm.entries.isEmpty {
                    SleepEmptyStateView { showQuickLog = true }
                } else {
                    SleepHistoryView(entries: vm.entries, durationLabel: vm.durationLabel) { entry in
                        Task { await vm.delete(entry) }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showQuickLog) {
            SleepQuickLogSheet(vm: vm)
        }
        .task { await vm.loadHistory() }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showQuickLog = true
            } label: {
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

// MARK: — En-tête résumé

private struct SleepHeaderView: View {
    let latest: SleepEntry?
    let durationLabel: (Int?) -> String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("Sommeil")
                    .font(VitaFont.title(22))
                    .foregroundColor(VitaColor.textPrimary)
                Text("Dernière nuit")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textTertiary)
            }

            Spacer()

            if let entry = latest {
                VStack(alignment: .trailing, spacing: VitaSpacing.xs) {
                    Text(durationLabel(entry.durationMinutes))
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundColor(VitaColor.textPrimary)
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Circle()
                                .fill(i <= entry.qualityScore ? VitaColor.accent : VitaColor.neutral.opacity(0.25))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            } else {
                Text("Aucune donnée")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textTertiary)
            }
        }
    }
}

// MARK: — État vide

private struct SleepEmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(VitaColor.accentLight)
            VStack(spacing: VitaSpacing.xs) {
                Text("Aucune nuit enregistrée")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text("Comment s'est passée ta nuit ?")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
            }
            Button("Enregistrer une nuit", action: onAdd)
                .buttonStyle(VitaPrimaryButtonStyle())
                .padding(.horizontal, VitaSpacing.xl)
            Spacer()
        }
    }
}

// MARK: — Historique

private struct SleepHistoryView: View {
    let entries: [SleepEntry]
    let durationLabel: (Int?) -> String
    let onDelete: (SleepEntry) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: VitaSpacing.sm) {
                ForEach(entries) { entry in
                    SleepEntryRow(entry: entry, durationLabel: durationLabel)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(entry)
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

private struct SleepEntryRow: View {
    let entry: SleepEntry
    let durationLabel: (Int?) -> String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text(formattedDate(entry.date))
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textPrimary)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Circle()
                            .fill(i <= entry.qualityScore ? VitaColor.accent : VitaColor.neutral.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            Spacer()
            Text(durationLabel(entry.durationMinutes))
                .font(.system(size: 18, weight: .light, design: .rounded))
                .foregroundColor(VitaColor.textSecondary)
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

struct SleepQuickLogSheet: View {
    @ObservedObject var vm: SleepViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.xl) {

                        // Durée
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Durée de sommeil")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            HStack {
                                Text(vm.formattedDuration)
                                    .font(.system(size: 28, weight: .light, design: .rounded))
                                    .foregroundColor(VitaColor.textPrimary)
                                Spacer()
                            }
                            Slider(value: $vm.formDurationHours, in: 2...12, step: 0.5)
                                .tint(VitaColor.accent)
                        }

                        // Qualité
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Qualité perçue")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            HStack(spacing: VitaSpacing.md) {
                                ForEach(1...5, id: \.self) { i in
                                    Button {
                                        vm.formQuality = i
                                    } label: {
                                        Circle()
                                            .fill(i <= vm.formQuality ? VitaColor.accent : VitaColor.neutral.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Text("\(i)")
                                                    .font(VitaFont.caption(12))
                                                    .foregroundColor(i <= vm.formQuality ? .white : VitaColor.textTertiary)
                                            )
                                    }
                                }
                                Spacer()
                            }
                        }

                        // Réveils
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Réveils nocturnes")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            HStack(spacing: VitaSpacing.sm) {
                                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { n in
                                    Button {
                                        vm.formAwakenings = n
                                    } label: {
                                        Text(n == 5 ? "5+" : "\(n)")
                                            .font(VitaFont.body())
                                            .foregroundColor(vm.formAwakenings == n ? .white : VitaColor.textSecondary)
                                            .frame(width: 44, height: 36)
                                            .background(vm.formAwakenings == n ? VitaColor.accent : VitaColor.surface)
                                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
                                    }
                                }
                                Spacer()
                            }
                        }

                        // Énergie au réveil
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Text("Énergie au réveil")
                                .font(VitaFont.headline())
                                .foregroundColor(VitaColor.textPrimary)
                            HStack(spacing: VitaSpacing.md) {
                                ForEach(1...5, id: \.self) { i in
                                    Button {
                                        vm.formEnergyOnWake = i
                                    } label: {
                                        Circle()
                                            .fill(i <= vm.formEnergyOnWake ? VitaColor.accent.opacity(0.7) : VitaColor.neutral.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Text("\(i)")
                                                    .font(VitaFont.caption(12))
                                                    .foregroundColor(i <= vm.formEnergyOnWake ? .white : VitaColor.textTertiary)
                                            )
                                    }
                                }
                                Spacer()
                            }
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
                        .disabled(vm.isSaving)
                    }
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.vertical, VitaSpacing.lg)
                }
            }
            .navigationTitle("Sommeil")
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
