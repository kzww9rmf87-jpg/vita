import SwiftUI

struct LifeStoryView: View {
    @StateObject private var vm = LifeStoryViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            Group {
                if vm.isLoading {
                    LifeStorySkeletonView()
                } else if let err = vm.errorMessage {
                    LifeStoryErrorView(message: err) {
                        Task { await vm.load() }
                    }
                } else if vm.groups.isEmpty {
                    LifeStoryEmptyView()
                } else {
                    LifeStoryScrollView(groups: vm.groups)
                }
            }
        }
        .navigationTitle("Mon Histoire")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
    }
}

// MARK: — Contenu principal

private struct LifeStoryScrollView: View {
    let groups: [LifeStoryGroup]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: VitaSpacing.lg, pinnedViews: []) {
                ForEach(groups) { group in
                    MonthSection(group: group)
                }
            }
            .padding(.horizontal, VitaSpacing.lg)
            .padding(.vertical, VitaSpacing.md)
            .padding(.bottom, VitaSpacing.xxl)
        }
    }
}

// MARK: — Section mensuelle

private struct MonthSection: View {
    let group: LifeStoryGroup

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Text(group.label.uppercased())
                .font(VitaFont.caption(11))
                .foregroundColor(VitaColor.textTertiary)
                .kerning(1.2)
                .padding(.top, VitaSpacing.sm)

            ForEach(group.memories) { memory in
                MemoryCard(memory: memory)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

// MARK: — Carte mémoire narrative

private struct MemoryCard: View {
    let memory: LifeMemory

    private var icon: String {
        switch memory.type {
        case "event":      return "calendar"
        case "goal":       return "scope"
        case "person":     return "person.fill"
        case "work":       return "briefcase.fill"
        case "family":     return "house.fill"
        case "health":     return "heart.fill"
        case "habit":      return "repeat"
        case "fear":       return "cloud.rain.fill"
        case "motivation": return "flame.fill"
        case "value":      return "star.fill"
        case "emotion":    return "face.smiling"
        case "project":    return "folder.fill"
        default:           return "circle.fill"
        }
    }

    private var formattedDate: String {
        memory.lastSeen.formatted(.dateTime.day().month(.wide))
    }

    var body: some View {
        HStack(alignment: .top, spacing: VitaSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(VitaColor.accent)
                .frame(width: 28, height: 28)
                .background(VitaColor.accentLight.opacity(0.15))
                .clipShape(Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                Text(memory.summary)
                    .font(VitaFont.body(15))
                    .foregroundColor(VitaColor.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formattedDate)
                    .font(VitaFont.caption(12))
                    .foregroundColor(VitaColor.textTertiary)
            }
        }
        .padding(VitaSpacing.md)
        .vitaCard()
    }
}

// MARK: — Skeleton

private struct LifeStorySkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VitaSpacing.lg) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VitaColor.neutral.opacity(0.2))
                            .frame(width: 80, height: 10)

                        ForEach(0..<2, id: \.self) { _ in
                            HStack(alignment: .top, spacing: VitaSpacing.md) {
                                Circle()
                                    .fill(VitaColor.neutral.opacity(0.2))
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(VitaColor.neutral.opacity(0.2))
                                        .frame(height: 14)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(VitaColor.neutral.opacity(0.15))
                                        .frame(width: 80, height: 10)
                                }
                            }
                            .padding(VitaSpacing.md)
                            .background(VitaColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
                        }
                    }
                }
            }
            .padding(VitaSpacing.lg)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

// MARK: — État vide

private struct LifeStoryEmptyView: View {
    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(VitaColor.accentLight)

            VStack(spacing: VitaSpacing.xs) {
                Text("Ton histoire commence ici")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text("Au fil de nos conversations et de tes journaux,\nVITA construira progressivement ton récit.")
                    .font(VitaFont.body(15))
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
        }
        .padding(.horizontal, VitaSpacing.xl)
    }
}

// MARK: — État erreur

private struct LifeStoryErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(VitaColor.textTertiary)
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
