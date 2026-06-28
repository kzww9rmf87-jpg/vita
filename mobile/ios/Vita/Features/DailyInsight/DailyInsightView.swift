import SwiftUI

// MARK: — Écran principal

struct DailyInsightView: View {
    @StateObject private var vm: DailyInsightViewModel

    init(date: String? = nil) {
        _vm = StateObject(wrappedValue: DailyInsightViewModel(date: date))
    }

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            Group {
                switch vm.state {
                case .idle, .loading:
                    DailyInsightSkeletonView()

                case .available(let insight):
                    InsightContentView(insight: insight) {
                        Task { await vm.reload() }
                    }

                case .notGenerated:
                    InsightNotGeneratedView {
                        Task { await vm.generate() }
                    }

                case .generating:
                    InsightGeneratingView()

                case .error(let message):
                    InsightErrorView(message: message) {
                        Task { await vm.reload() }
                    }
                }
            }
            .animation(.vitaDefault, value: animationKey)
        }
        .navigationTitle("Synthèse du jour")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private var animationKey: String {
        switch vm.state {
        case .idle:           return "idle"
        case .loading:        return "loading"
        case .available:      return "available"
        case .notGenerated:   return "notGenerated"
        case .generating:     return "generating"
        case .error:          return "error"
        }
    }
}

// MARK: — Contenu principal

private struct InsightContentView: View {
    let insight: DailyInsight
    let onRefresh: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: VitaSpacing.lg) {

                ClimateHeaderCard(insight: insight)

                SummaryCard(summary: insight.summary)

                if !insight.drivers.isEmpty {
                    DriversCard(drivers: insight.drivers)
                }

                ReflectionCard(reflection: insight.reflection)

                QuestionCard(question: insight.question)

                Spacer(minLength: VitaSpacing.xxl)
            }
            .padding(.horizontal, VitaSpacing.lg)
            .padding(.top, VitaSpacing.md)
        }
        .refreshable { onRefresh() }
    }
}

// MARK: — Carte en-tête climat

private struct ClimateHeaderCard: View {
    let insight: DailyInsight

    private var climate: InsightClimate { insight.typedClimate }

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.md) {
            HStack(spacing: VitaSpacing.sm) {
                Image(systemName: climate.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(climate.accentColor)
                Text("Climat intérieur")
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
            }

            Text(climate.label)
                .font(VitaFont.title(26))
                .foregroundColor(VitaColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VitaSpacing.lg)
        .background(climate.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.lg)
                .stroke(climate.accentColor.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: — Résumé

private struct SummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Text(summary)
                .font(VitaFont.body(17))
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VitaSpacing.lg)
        .vitaCard()
    }
}

// MARK: — Facteurs principaux

private struct DriversCard: View {
    let drivers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Text("Facteurs principaux")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.textSecondary)

            FlowLayout(spacing: VitaSpacing.sm) {
                ForEach(drivers, id: \.self) { driver in
                    DriverChip(label: driver)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VitaSpacing.lg)
        .vitaCard()
    }
}

private struct DriverChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(VitaFont.caption(13))
            .foregroundColor(VitaColor.accent)
            .padding(.horizontal, VitaSpacing.md)
            .padding(.vertical, VitaSpacing.xs)
            .background(VitaColor.accentLight.opacity(0.18))
            .clipShape(Capsule())
    }
}

// MARK: — Réflexion

private struct ReflectionCard: View {
    let reflection: String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Label("Réflexion", systemImage: "text.quote")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.textSecondary)

            Text(reflection)
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VitaSpacing.lg)
        .vitaCard()
    }
}

// MARK: — Question du jour

private struct QuestionCard: View {
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            Label("Question du jour", systemImage: "questionmark.circle")
                .font(VitaFont.caption())
                .foregroundColor(VitaColor.textSecondary)

            Text(question)
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textPrimary)
                .italic()
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VitaSpacing.lg)
        .background(VitaColor.accentLight.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VitaRadius.lg)
                .stroke(VitaColor.accentLight.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: — État : non généré

private struct InsightNotGeneratedView: View {
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(VitaColor.accentLight)

            VStack(spacing: VitaSpacing.xs) {
                Text("Synthèse du jour")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text("VITA peut interpréter ta journée\nà partir de tes données.")
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button("Générer la synthèse", action: onGenerate)
                .buttonStyle(VitaPrimaryButtonStyle())
                .padding(.horizontal, VitaSpacing.xl)

            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — État : en cours de génération

private struct InsightGeneratingView: View {
    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            ProgressView()
                .tint(VitaColor.accent)
                .scaleEffect(1.3)
            Text("VITA analyse ta journée…")
                .font(VitaFont.body())
                .foregroundColor(VitaColor.textSecondary)
            Spacer()
        }
    }
}

// MARK: — État : erreur

private struct InsightErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(VitaColor.textTertiary)

            VStack(spacing: VitaSpacing.xs) {
                Text("Synthèse indisponible")
                    .font(VitaFont.headline())
                    .foregroundColor(VitaColor.textPrimary)
                Text(message)
                    .font(VitaFont.caption())
                    .foregroundColor(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Réessayer", action: onRetry)
                .buttonStyle(VitaSecondaryButtonStyle())
                .padding(.horizontal, VitaSpacing.xl)

            Spacer()
        }
        .padding(.horizontal, VitaSpacing.lg)
    }
}

// MARK: — Squelette de chargement

private struct DailyInsightSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: VitaSpacing.lg) {
                // Carte climat
                RoundedRectangle(cornerRadius: VitaRadius.lg)
                    .fill(VitaColor.surface)
                    .frame(height: 100)
                    .redacted(reason: .placeholder)

                // Résumé
                RoundedRectangle(cornerRadius: VitaRadius.lg)
                    .fill(VitaColor.surface)
                    .frame(height: 80)
                    .redacted(reason: .placeholder)

                // Drivers
                RoundedRectangle(cornerRadius: VitaRadius.lg)
                    .fill(VitaColor.surface)
                    .frame(height: 70)
                    .redacted(reason: .placeholder)

                // Réflexion
                RoundedRectangle(cornerRadius: VitaRadius.lg)
                    .fill(VitaColor.surface)
                    .frame(height: 120)
                    .redacted(reason: .placeholder)
            }
            .padding(.horizontal, VitaSpacing.lg)
            .padding(.top, VitaSpacing.md)
        }
    }
}

// MARK: — FlowLayout (chips multi-lignes)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                totalHeight += lineHeight + spacing
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            currentY = totalHeight + lineHeight
        }
        return CGSize(width: maxWidth, height: currentY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentY += lineHeight + spacing
                currentX = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: — Couleurs par climat

extension InsightClimate {
    /// Couleur d'accent accompagnant le climat.
    /// Jamais rouge. Jamais évaluatif. Toujours évocateur.
    var accentColor: Color {
        switch self {
        case .calm:         return Color(red: 0.58, green: 0.68, blue: 0.78) // gris bleuté
        case .constructive: return Color(red: 0.42, green: 0.56, blue: 0.44) // vert sauge (VitaColor.accent)
        case .demanding:    return Color(red: 0.82, green: 0.63, blue: 0.25) // ambre (VitaColor.warning)
        case .recovery:     return Color(red: 0.38, green: 0.58, blue: 0.82) // bleu doux
        case .uncertain:    return Color(red: 0.65, green: 0.65, blue: 0.68) // gris neutre
        case .energized:    return Color(red: 0.40, green: 0.72, blue: 0.48) // vert vif
        case .reflective:   return Color(red: 0.55, green: 0.40, blue: 0.75) // violet discret
        case .transition:   return Color(red: 0.60, green: 0.38, blue: 0.70) // violet discret (chaud)
        case .balanced:     return Color(red: 0.30, green: 0.42, blue: 0.32) // VitaColor.accentDark
        }
    }
}
