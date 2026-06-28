import SwiftUI

// MARK: — Écran principal Journal

struct JournalView: View {
    @StateObject private var vm = JournalViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                if vm.isLoading && vm.entries.isEmpty {
                    JournalSkeletonView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: VitaSpacing.lg) {
                            // Invitation à écrire
                            WriteInvitationCard(vm: vm)
                                .padding(.horizontal, VitaSpacing.lg)
                                .padding(.top, VitaSpacing.md)

                            // Mémoire émotionnelle
                            if !vm.memories.isEmpty {
                                EmotionalMemoriesSection(memories: vm.memories)
                            }

                            // Entrées récentes
                            if !vm.entries.isEmpty {
                                RecentEntriesSection(entries: vm.entries)
                            }

                            Spacer(minLength: VitaSpacing.xl)
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Mon journal")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .sheet(isPresented: $vm.showingNewEntry) {
                NewEntrySheet(vm: vm)
            }
            .sheet(isPresented: $vm.showingVitaResponse) {
                if let response = vm.vitaResponse {
                    VitaResponseSheet(response: response, onDismiss: {
                        vm.showingVitaResponse = false
                    })
                }
            }
            .alert("Journal indisponible", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }
}

// MARK: — Carte d'invitation à écrire

private struct WriteInvitationCard: View {
    @ObservedObject var vm: JournalViewModel

    var body: some View {
        Button {
            vm.showingNewEntry = true
        } label: {
            HStack(spacing: VitaSpacing.md) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(VitaColor.accent)

                Text("Comment tu te sens aujourd'hui ?")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(VitaColor.textTertiary)
            }
            .padding(VitaSpacing.md)
            .background(VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        }
    }
}

// MARK: — Mémoire émotionnelle

private struct EmotionalMemoriesSection: View {
    let memories: [EmotionalMemory]

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader(title: "Ce que VITA remarque", icon: "brain.head.profile")
                .padding(.horizontal, VitaSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VitaSpacing.sm) {
                    ForEach(memories.prefix(8)) { memory in
                        EmotionalMemoryChip(memory: memory)
                    }
                }
                .padding(.horizontal, VitaSpacing.lg)
            }
        }
    }
}

private struct EmotionalMemoryChip: View {
    let memory: EmotionalMemory

    var valenceColor: Color {
        guard let v = memory.valence else { return VitaColor.textTertiary }
        if v > 0.2 { return VitaColor.warning }
        if v < -0.2 { return VitaTimelineColor.sleep.swiftColor }
        return VitaColor.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.theme)
                .font(VitaFont.caption(13))
                .foregroundColor(VitaColor.textPrimary)

            if let summary = memory.summary {
                Text(summary)
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 3) {
                Circle()
                    .fill(valenceColor)
                    .frame(width: 6, height: 6)
                Text("\(memory.recurrenceCount)×")
                    .font(VitaFont.caption(10))
                    .foregroundColor(VitaColor.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 140, alignment: .leading)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
    }
}

// MARK: — Entrées récentes

private struct RecentEntriesSection: View {
    let entries: [JournalEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            SectionHeader(title: "Entrées récentes", icon: "clock")
                .padding(.horizontal, VitaSpacing.lg)

            VStack(spacing: VitaSpacing.sm) {
                ForEach(entries.prefix(10)) { entry in
                    JournalEntryRow(entry: entry)
                        .padding(.horizontal, VitaSpacing.lg)
                }
            }
        }
    }
}

private struct JournalEntryRow: View {
    let entry: JournalEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            // En-tête
            HStack(alignment: .top, spacing: VitaSpacing.sm) {
                Image(systemName: entry.moodIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(VitaTimelineColor(rawValue: entry.moodColor)?.swiftColor ?? VitaColor.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.moodLabel?.capitalized ?? "Entrée")
                        .font(VitaFont.caption(14))
                        .foregroundColor(VitaColor.textPrimary)

                    Text(entry.displayDate)
                        .font(VitaFont.caption(11))
                        .foregroundColor(VitaColor.textTertiary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(VitaColor.textTertiary)
                }
            }

            // Contenu (preview ou complet)
            Text(entry.content)
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
                .lineLimit(expanded ? nil : 2)

            // Réponse VITA si disponible et déplié
            if expanded, let response = entry.vitaResponse, !response.isEmpty {
                Divider()
                    .background(VitaColor.neutral.opacity(0.2))

                HStack(alignment: .top, spacing: VitaSpacing.xs) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11))
                        .foregroundColor(VitaColor.accent)
                        .padding(.top, 2)

                    Text(response)
                        .font(VitaFont.body(13))
                        .foregroundColor(VitaColor.textPrimary)
                        .italic()
                }
            }

            // Thèmes
            if let themes = entry.themes, !themes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VitaSpacing.xs) {
                        ForEach(themes, id: \.self) { theme in
                            ThemeTag(text: theme)
                        }
                    }
                }
            }
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
    }
}

private struct ThemeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(VitaFont.caption(11))
            .foregroundColor(VitaColor.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VitaColor.accent.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: — Section header commun

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: VitaSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(VitaColor.textSecondary)
            Text(title)
                .font(VitaFont.headline(15))
                .foregroundColor(VitaColor.textSecondary)
        }
    }
}

// MARK: — Sheet nouvelle entrée

struct NewEntrySheet: View {
    @ObservedObject var vm: JournalViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    TextEditor(text: $vm.draftText)
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, VitaSpacing.lg)
                        .padding(.top, VitaSpacing.md)
                        .focused($isFocused)
                        .overlay(alignment: .topLeading) {
                            if vm.draftText.isEmpty {
                                Text("Écris ce que tu ressens…")
                                    .font(VitaFont.body())
                                    .foregroundColor(VitaColor.textTertiary)
                                    .padding(.horizontal, VitaSpacing.lg + 5)
                                    .padding(.top, VitaSpacing.md + 8)
                                    .allowsHitTesting(false)
                            }
                        }

                    Divider()
                        .background(VitaColor.neutral.opacity(0.2))
                        .padding(.horizontal, VitaSpacing.lg)

                    PrivacyNote()
                        .padding(.horizontal, VitaSpacing.lg)
                        .padding(.vertical, VitaSpacing.sm)
                }
            }
            .navigationTitle("Nouvelle entrée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        vm.draftText = ""
                        vm.showingNewEntry = false
                    }
                    .foregroundColor(VitaColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSending {
                        ProgressView()
                            .tint(VitaColor.accent)
                            .scaleEffect(0.8)
                    } else {
                        Button("Envoyer") {
                            Task { await vm.submitEntry() }
                        }
                        .disabled(!vm.canSubmit)
                        .foregroundColor(vm.canSubmit ? VitaColor.accent : VitaColor.textTertiary)
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct PrivacyNote: View {
    var body: some View {
        HStack(spacing: VitaSpacing.xs) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundColor(VitaColor.textTertiary)
            Text("Ton journal est privé. VITA l'analyse uniquement pour te répondre.")
                .font(VitaFont.caption(11))
                .foregroundColor(VitaColor.textTertiary)
        }
    }
}

// MARK: — Sheet réponse VITA

struct VitaResponseSheet: View {
    let response: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                VStack(spacing: VitaSpacing.xl) {
                    Spacer()

                    VStack(spacing: VitaSpacing.lg) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 32))
                            .foregroundColor(VitaColor.accent)

                        Text(response)
                            .font(VitaFont.body())
                            .foregroundColor(VitaColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, VitaSpacing.xl)
                    }

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Text("Merci VITA")
                            .font(VitaFont.headline())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VitaSpacing.md)
                            .background(VitaColor.accent)
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                    }
                    .padding(.horizontal, VitaSpacing.xl)
                    .padding(.bottom, VitaSpacing.xl)
                }
            }
            .navigationTitle("VITA t'a lu")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: — Skeleton chargement

private struct JournalSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: VitaSpacing.lg) {

                // Invitation à écrire (placeholder)
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .fill(VitaColor.surface)
                    .frame(height: 52)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.md)

                // Section mémoires
                VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VitaColor.neutral.opacity(0.2))
                        .frame(width: 140, height: 12)
                        .padding(.horizontal, VitaSpacing.lg)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: VitaSpacing.sm) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: VitaRadius.sm)
                                    .fill(VitaColor.surface)
                                    .frame(width: 140, height: 72)
                            }
                        }
                        .padding(.horizontal, VitaSpacing.lg)
                    }
                }

                // Entrées récentes
                VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VitaColor.neutral.opacity(0.2))
                        .frame(width: 110, height: 12)
                        .padding(.horizontal, VitaSpacing.lg)

                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            HStack {
                                Circle()
                                    .fill(VitaColor.neutral.opacity(0.2))
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(VitaColor.neutral.opacity(0.2))
                                        .frame(width: 80, height: 12)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(VitaColor.neutral.opacity(0.15))
                                        .frame(width: 120, height: 10)
                                }
                            }
                            RoundedRectangle(cornerRadius: 4)
                                .fill(VitaColor.neutral.opacity(0.15))
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(VitaColor.neutral.opacity(0.1))
                                .frame(width: 200, height: 12)
                        }
                        .padding(VitaSpacing.md)
                        .background(VitaColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                        .padding(.horizontal, VitaSpacing.lg)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

// MARK: — Extension VitaTimelineColor (raw value pour lookup)

extension VitaTimelineColor: RawRepresentable {
    typealias RawValue = String
    init?(rawValue: String) {
        switch rawValue {
        case "accent":    self = .accent
        case "activity":  self = .activity
        case "sleep":     self = .sleep
        case "nutrition": self = .nutrition
        case "purple":    self = .purple
        default:          return nil
        }
    }
    var rawValue: String {
        switch self {
        case .accent:    return "accent"
        case .activity:  return "activity"
        case .sleep:     return "sleep"
        case .nutrition: return "nutrition"
        case .purple:    return "purple"
        }
    }
}
