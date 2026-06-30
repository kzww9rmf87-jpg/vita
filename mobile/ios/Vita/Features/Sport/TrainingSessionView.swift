import SwiftUI

// Carte d'une séance planifiée par l'IA — utilisée dans TrainingWeekView.
struct TrainingSessionCard: View {
    let session: AIPlannedSession
    let dayName:       String
    let durationLabel: String
    let typeIcon:      String

    var body: some View {
        HStack(spacing: VitaSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: VitaRadius.sm)
                    .fill(VitaColor.accent.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: typeIcon)
                    .font(.body)
                    .foregroundStyle(VitaColor.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.activityName)
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textPrimary)
                if let notes = session.notes {
                    Text(notes)
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(dayName)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textTertiary)
                Text(durationLabel)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textSecondary)
            }
        }
        .padding(VitaSpacing.sm)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
    }
}
