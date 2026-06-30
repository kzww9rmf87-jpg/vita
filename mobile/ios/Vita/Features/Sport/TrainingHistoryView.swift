import SwiftUI

struct TrainingHistoryView: View {
    var body: some View {
        VStack(spacing: VitaSpacing.lg) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VitaColor.accentLight)
            VStack(spacing: VitaSpacing.xs) {
                Text("Historique des séances")
                    .font(VitaFont.headline(20))
                    .foregroundStyle(VitaColor.textPrimary)
                Text("Bientôt disponible — tes séances passées et ta progression apparaîtront ici.")
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VitaSpacing.xl)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VitaColor.background)
        .navigationTitle("Mes séances")
        .navigationBarTitleDisplayMode(.inline)
    }
}
