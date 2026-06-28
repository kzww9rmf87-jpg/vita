import SwiftUI

// Sheet "Pourquoi VITA me dit ça ?"
//
// Affiche uniquement les catégories générales utilisées — jamais le contenu brut
// du journal, jamais de citations, jamais de données personnelles identifiables.

struct ExplainabilitySheet: View {
    let categories: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VitaSpacing.xl) {

                        // Introduction
                        Text("Pour formuler cette réponse, VITA a tenu compte de :")
                            .font(VitaFont.body(15))
                            .foregroundColor(VitaColor.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        // Catégories
                        VStack(alignment: .leading, spacing: VitaSpacing.md) {
                            ForEach(categories, id: \.self) { category in
                                HStack(alignment: .center, spacing: VitaSpacing.md) {
                                    Circle()
                                        .fill(VitaColor.accentLight)
                                        .frame(width: 8, height: 8)

                                    Text(category)
                                        .font(VitaFont.body(16))
                                        .foregroundColor(VitaColor.textPrimary)
                                }
                            }
                        }
                        .padding(VitaSpacing.lg)
                        .vitaCard()

                        // Note de confidentialité
                        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
                            Label("Vie privée", systemImage: "lock.fill")
                                .font(VitaFont.caption(11))
                                .foregroundColor(VitaColor.textTertiary)

                            Text("VITA n'affiche ici que des catégories générales. Le contenu de tes journaux, tes échanges personnels et tes données de santé ne transitent jamais dans cette vue.")
                                .font(VitaFont.caption(13))
                                .foregroundColor(VitaColor.textTertiary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(VitaSpacing.md)
                        .background(VitaColor.neutral.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                    }
                    .padding(VitaSpacing.lg)
                    .padding(.bottom, VitaSpacing.xxl)
                }
            }
            .navigationTitle("Pourquoi cette réponse ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(VitaFont.caption())
                        .foregroundColor(VitaColor.textSecondary)
                }
            }
        }
    }
}
