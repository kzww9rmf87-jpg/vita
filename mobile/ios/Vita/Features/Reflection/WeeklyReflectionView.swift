import SwiftUI

struct WeeklyReflectionView: View {
    @StateObject private var vm = ReflectionViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            Group {
                switch vm.state {
                case .idle, .loading:
                    ReflectionSkeletonView()
                case .available(let reflection):
                    ReflectionScrollView(reflection: reflection)
                case .notReady:
                    ReflectionNotReadyView {
                        Task { await vm.generate() }
                    }
                case .generating:
                    ReflectionGeneratingView()
                case .error(let message):
                    ReflectionErrorView(message: message) {
                        Task { await vm.load() }
                    }
                }
            }
            .animation(.vitaDefault, value: animationKey)
        }
        .navigationTitle("Réflexion")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
    }

    private var animationKey: String {
        switch vm.state {
        case .idle:        return "idle"
        case .loading:     return "loading"
        case .available:   return "available"
        case .notReady:    return "notReady"
        case .generating:  return "generating"
        case .error:       return "error"
        }
    }
}

// MARK: — Carte principale (réflexion disponible)

private struct ReflectionScrollView: View {
    let reflection: WeeklyReflection

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: VitaSpacing.lg) {
                ReflectionCard(reflection: reflection)
                    .padding(.horizontal, VitaSpacing.lg)
            }
            .padding(.vertical, VitaSpacing.md)
            .padding(.bottom, VitaSpacing.xxl)
        }
    }
}

private struct ReflectionCard: View {
    let reflection: WeeklyReflection
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // En-tête
            VStack(alignment: .leading, spacing: VitaSpacing.xs) {
                HStack {
                    Label("Cette semaine", systemImage: "sparkles")
                        .font(VitaFont.caption(12))
                        .foregroundColor(VitaColor.accent)
                    Spacer()
                    Text(reflection.formattedPeriod)
                        .font(VitaFont.caption(12))
                        .foregroundColor(VitaColor.textTertiary)
                }
            }
            .padding([.horizontal, .top], VitaSpacing.lg)
            .padding(.bottom, VitaSpacing.md)

            Divider()
                .background(VitaColor.neutral.opacity(0.15))

            // Contenu de la réflexion
            Text(reflection.content)
                .font(VitaFont.body(16))
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(VitaSpacing.lg)

            // Thèmes
            if !reflection.themes.isEmpty {
                ThemeChipsView(themes: reflection.themes)
                    .padding(.horizontal, VitaSpacing.lg)
                    .padding(.bottom, VitaSpacing.md)
            }

            // Question
            if let question = reflection.question {
                Divider()
                    .background(VitaColor.neutral.opacity(0.15))

                QuestionView(question: question)
                    .padding(VitaSpacing.lg)
            }

            // Actions
            Divider()
                .background(VitaColor.neutral.opacity(0.15))

            ShareLink(
                item: shareText,
                subject: Text("Ma réflexion VITA"),
                message: Text(shareText)
            ) {
                Label("Partager", systemImage: "square.and.arrow.up")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VitaSpacing.md)
            }
        }
        .vitaCard()
    }

    private var shareText: String {
        var parts = [reflection.content]
        if let q = reflection.question {
            parts.append("\n\(q)")
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: — Thèmes

private struct ThemeChipsView: View {
    let themes: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VitaSpacing.xs) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme)
                        .font(VitaFont.caption(12))
                        .foregroundColor(VitaColor.accent)
                        .padding(.horizontal, VitaSpacing.sm)
                        .padding(.vertical, VitaSpacing.xs)
                        .background(VitaColor.accentLight.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: — Question

private struct QuestionView: View {
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Text("Une question pour toi")
                .font(VitaFont.caption(11))
                .foregroundColor(VitaColor.textTertiary)
                .textCase(.uppercase)
                .kerning(0.8)

            Text(question)
                .font(VitaFont.body(15))
                .italic()
                .foregroundColor(VitaColor.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: — Skeleton

private struct ReflectionSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: VitaSpacing.md) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(VitaColor.neutral.opacity(0.2))
                    .frame(width: 120, height: 10)

                Divider().background(VitaColor.neutral.opacity(0.15))

                VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VitaColor.neutral.opacity(0.2))
                            .frame(height: 14)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VitaColor.neutral.opacity(0.15))
                        .frame(width: 180, height: 14)
                }
            }
            .padding(VitaSpacing.lg)
        }
        .vitaCard()
        .padding(.horizontal, VitaSpacing.lg)
        .padding(.top, VitaSpacing.md)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

// MARK: — Pas encore prête

private struct ReflectionNotReadyView: View {
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.xl) {
            Spacer()

            VStack(spacing: VitaSpacing.lg) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(VitaColor.accentLight)

                VStack(spacing: VitaSpacing.xs) {
                    Text("Pas encore de réflexion cette semaine")
                        .font(VitaFont.headline())
                        .foregroundColor(VitaColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("VITA peut tisser une réflexion\nà partir de ta semaine.")
                        .font(VitaFont.body(15))
                        .foregroundColor(VitaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button("Générer ma réflexion", action: onGenerate)
                    .buttonStyle(VitaPrimaryButtonStyle())
                    .padding(.horizontal, VitaSpacing.xl)
            }

            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Génération en cours

private struct ReflectionGeneratingView: View {
    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            ProgressView()
                .tint(VitaColor.accent)
                .scaleEffect(1.3)
            Text("VITA réfléchit…")
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
            Spacer()
        }
    }
}

// MARK: — Erreur

private struct ReflectionErrorView: View {
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
