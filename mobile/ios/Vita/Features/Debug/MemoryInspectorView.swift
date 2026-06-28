#if DEBUG
import SwiftUI

// MARK: — Modèles (DEBUG uniquement)

struct DebugMemory: Codable, Identifiable {
    let id: String
    let type: String
    let source: String
    let importance: Int
    let confidence: Double
    let lastSeen: Date
    let createdAt: Date
    let updatedAt: Date
    let summary: String
}

private struct DebugMemoriesResponse: Codable {
    let memories: [DebugMemory]
    let count: Int
}

// MARK: — ViewModel (DEBUG uniquement)

@MainActor
final class MemoryInspectorViewModel: ObservableObject {
    @Published var memories: [DebugMemory] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: DebugMemoriesResponse = try await APIClient.shared.get("/debug/memories")
            self.memories = response.memories
        } catch {
            errorMessage = "Impossible de charger les mémoires."
        }
    }
}

// MARK: — Vue principale (DEBUG uniquement)

struct MemoryInspectorView: View {
    @StateObject private var vm = MemoryInspectorViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            Group {
                if vm.isLoading {
                    MemoryInspectorSkeletonView()
                } else if let err = vm.errorMessage {
                    MemoryInspectorErrorView(message: err) {
                        Task { await vm.load() }
                    }
                } else if vm.memories.isEmpty {
                    MemoryInspectorEmptyView()
                } else {
                    MemoryListView(memories: vm.memories)
                }
            }
        }
        .navigationTitle("Memory Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Label("DEBUG", systemImage: "ladybug.fill")
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.warning)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

// MARK: — Liste

private struct MemoryListView: View {
    let memories: [DebugMemory]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text("\(memories.count) mémoire(s)")
                    .font(VitaFont.caption(11))
                    .foregroundColor(VitaColor.textTertiary)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.top, VitaSpacing.sm)

                LazyVStack(spacing: VitaSpacing.sm) {
                    ForEach(memories) { memory in
                        MemoryDebugCard(memory: memory)
                            .padding(.horizontal, VitaSpacing.lg)
                    }
                }
                .padding(.bottom, VitaSpacing.xxl)
            }
        }
    }
}

// MARK: — Carte mémoire debug

private struct MemoryDebugCard: View {
    let memory: DebugMemory

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {

            // En-tête : type + source + importance
            HStack(spacing: VitaSpacing.sm) {
                TagPill(text: memory.type, color: VitaColor.accent)
                TagPill(text: memory.source, color: VitaColor.neutral)
                Spacer()
                ImportanceDots(importance: memory.importance)
            }

            // Résumé
            Text(memory.summary)
                .font(VitaFont.body(14))
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(VitaColor.neutral.opacity(0.15))

            // Métriques techniques
            VStack(alignment: .leading, spacing: 4) {
                DebugRow(label: "confidence", value: String(format: "%.2f", memory.confidence))
                DebugRow(label: "last_seen",  value: memory.lastSeen.formatted(.relative(presentation: .named)))
                DebugRow(label: "created_at", value: memory.createdAt.formatted(.dateTime.day().month().year()))
                DebugRow(label: "id",         value: String(memory.id.prefix(8)) + "…")
            }
        }
        .padding(VitaSpacing.md)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.md)
                .stroke(VitaColor.neutral.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct TagPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(VitaFont.caption(10))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

private struct ImportanceDots: View {
    let importance: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= importance ? VitaColor.warning : VitaColor.neutral.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct DebugRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(VitaFont.mono(11))
                .foregroundColor(VitaColor.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(VitaFont.mono(11))
                .foregroundColor(VitaColor.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: — Skeleton

private struct MemoryInspectorSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: VitaSpacing.sm) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                        HStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(VitaColor.neutral.opacity(0.2))
                                .frame(width: 50, height: 18)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(VitaColor.neutral.opacity(0.15))
                                .frame(width: 40, height: 18)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VitaColor.neutral.opacity(0.2))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VitaColor.neutral.opacity(0.15))
                            .frame(width: 200, height: 14)
                    }
                    .padding(VitaSpacing.md)
                    .background(VitaColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                    .padding(.horizontal, VitaSpacing.lg)
                }
            }
            .padding(.top, VitaSpacing.sm)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

// MARK: — État vide

private struct MemoryInspectorEmptyView: View {
    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(VitaColor.textTertiary)
            Text("Aucune mémoire consolidée")
                .font(VitaFont.headline())
                .foregroundColor(VitaColor.textPrimary)
            Text("Commence à utiliser VITA pour que des mémoires apparaissent ici.")
                .font(VitaFont.body(14))
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.xl)
    }
}

// MARK: — État erreur

private struct MemoryInspectorErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(VitaColor.warning)
            Text(message)
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: onRetry)
                .buttonStyle(VitaSecondaryButtonStyle())
                .frame(maxWidth: 200)
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.xl)
    }
}
#endif
