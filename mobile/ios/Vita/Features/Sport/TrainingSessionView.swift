import SwiftUI

// Carte d'une séance planifiée par l'IA — utilisée dans TrainingWeekView.
struct TrainingSessionCard: View {
    let session: AIPlannedSession
    let dayName:       String
    let durationLabel: String
    let typeIcon:      String

    var body: some View {
        VStack(alignment: .leading, spacing: VitaSpacing.sm) {
            // Ligne principale : icône + activité + durée/jour
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
                    if let intensity = session.intensityLabel {
                        Text(intensity)
                            .font(VitaFont.caption())
                            .foregroundStyle(intensityColor(intensity))
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

            // Objectif de la séance
            if let goal = session.sessionGoal {
                Text(goal)
                    .font(VitaFont.body())
                    .foregroundStyle(VitaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Consigne simple
            if let instruction = session.simpleInstruction {
                HStack(alignment: .top, spacing: VitaSpacing.xs) {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(VitaColor.accent)
                        .padding(.top, 2)
                    Text(instruction)
                        .font(VitaFont.caption())
                        .foregroundStyle(VitaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Pourquoi cette séance
            if let why = session.whyThisSession {
                Text(why)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Note de progression
            if let progression = session.progressionNote {
                Text(progression)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.accent.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Notes pratiques
            if let notes = session.notes {
                Text(notes)
                    .font(VitaFont.caption())
                    .foregroundStyle(VitaColor.textTertiary)
                    .lineLimit(3)
            }
        }
        .padding(VitaSpacing.sm)
        .background(VitaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: VitaRadius.sm))
    }

    private func intensityColor(_ label: String) -> Color {
        switch label {
        case "douce":    return VitaColor.success
        case "modérée":  return VitaColor.accent
        case "soutenue": return VitaColor.warning
        default:         return VitaColor.textSecondary
        }
    }
}
