import SwiftUI

struct ShoppingListView: View {
    let planId: String
    @StateObject private var vm = ShoppingListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.items.isEmpty {
                    ShoppingEmptyState {
                        Task { await vm.generate(planId: planId) }
                    }
                    .overlay(alignment: .bottom) {
                        if vm.isGenerating {
                            ProgressView("Génération de la liste…")
                                .padding()
                        }
                    }
                } else {
                    ShoppingListContent(vm: vm)
                }
            }
            .navigationTitle(titleLabel)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await vm.generate(planId: planId) }
                    } label: {
                        if vm.isGenerating {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(vm.isGenerating)
                }
                if !vm.items.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        ShareLink(
                            item: vm.shareText,
                            subject: Text("Liste de courses"),
                            message: Text("Voici ma liste pour la semaine.")
                        ) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .alert("Erreur", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
            .overlay(alignment: .top) {
                if let banner = vm.readyBanner {
                    HStack(spacing: VitaSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VitaColor.accent)
                        Text(banner)
                            .font(VitaFont.body())
                            .foregroundStyle(VitaColor.textPrimary)
                    }
                    .padding(.horizontal, VitaSpacing.md)
                    .padding(.vertical, VitaSpacing.sm)
                    .background(VitaColor.surface)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                    .padding(.top, VitaSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .task { await vm.load(planId: planId) }
    }

    private var titleLabel: String {
        guard !vm.items.isEmpty else { return "Liste de courses" }
        return "Liste (\(vm.uncheckedCount) restants)"
    }
}

// MARK: — Contenu

private struct ShoppingListContent: View {
    @ObservedObject var vm: ShoppingListViewModel

    var body: some View {
        List {
            ForEach(vm.itemsByCategory, id: \.category) { group in
                Section(header: Text(group.category.label)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
                ) {
                    ForEach(group.items) { item in
                        ShoppingItemRow(item: item) {
                            Task { await vm.toggle(itemId: item.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: VitaSpacing.md) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? VitaColor.accent : VitaColor.textSecondary)

                Text(item.ingredientName.capitalized)
                    .font(VitaFont.body())
                    .foregroundStyle(item.isChecked ? VitaColor.textSecondary : VitaColor.textPrimary)
                    .strikethrough(item.isChecked)

                Spacer()

                if let qty = item.quantity, let unit = item.unit {
                    Text("\(Int(qty)) \(unit)")
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: — État vide

private struct ShoppingEmptyState: View {
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.md) {
            Image(systemName: "cart")
                .font(.system(size: 48))
                .foregroundStyle(VitaColor.textSecondary)
            Text("Liste de courses vide")
                .font(VitaFont.headline())
                .foregroundStyle(VitaColor.textPrimary)
            Text("Planifiez vos repas, puis générez la liste de courses consolidée.")
                .font(VitaFont.body())
                .foregroundStyle(VitaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VitaSpacing.xl)
            Button("Générer la liste", action: onGenerate)
                .buttonStyle(.borderedProminent)
                .tint(VitaColor.accent)
        }
    }
}
