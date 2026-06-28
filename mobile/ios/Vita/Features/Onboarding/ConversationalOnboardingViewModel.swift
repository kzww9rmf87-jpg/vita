import Foundation
import SwiftUI

// MARK: — Modèles de la conversation

struct ConversationMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isVita: Bool
}

struct ConversationChoice: Identifiable {
    let id: String
    let label: String
}

// MARK: — ViewModel

// Script de la conversation d'onboarding VITA.
// 5 échanges : prénom → objectif → activité → réveil → Apple Santé → conclusion.
// Chaque réponse est persistée immédiatement via PATCH /profile.

@MainActor
final class ConversationalOnboardingViewModel: ObservableObject {

    // — État de l'interface
    @Published var messages:      [ConversationMessage] = []
    @Published var currentChoices: [ConversationChoice] = []
    @Published var showNameInput  = false
    @Published var showDoneButton = false
    @Published var nameInput      = ""
    @Published var isLoading      = false

    // — Valeurs collectées
    private(set) var firstName    = ""
    private(set) var primaryGoal  = "feel_better"
    private(set) var activityLevel = 3
    private(set) var wakeTime     = "07:00"

    // Indice du tour de questions (goal=1, activity=2, wakeTime=3, health=4)
    private var currentTurn = 0

    // MARK: — Démarrage

    func start() async {
        await vitaMessage("Bonjour. Je suis VITA,\nton coach de vie personnel.")
        await vitaMessage("Comment tu t'appelles ?")
        withAnimation(.vitaDefault) { showNameInput = true }
    }

    // MARK: — Tour 0 : Prénom

    func submitName() async {
        let name = nameInput.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else { return }
        firstName = name
        withAnimation(.vitaDefault) { showNameInput = false }
        userMessage(name)
        await patchProfile()
        await askGoal()
    }

    // MARK: — Tours 1–4 : Chips

    func select(choiceId: String) async {
        withAnimation(.vitaDefault) { currentChoices = [] }
        currentTurn += 1

        switch currentTurn {

        case 1: // Objectif
            primaryGoal = choiceId
            userMessage(goalLabel(for: choiceId))
            await patchProfile()
            await askActivity()

        case 2: // Activité
            activityLevel = Int(choiceId) ?? 3
            userMessage(activityLabel(for: activityLevel))
            await patchProfile()
            await askWakeTime()

        case 3: // Réveil
            wakeTime = choiceId
            userMessage(wakeTimeLabel(for: choiceId))
            await patchProfile()
            await askHealth()

        case 4: // Apple Santé
            if choiceId == "health_yes" {
                userMessage("Autoriser l'accès")
                do {
                    try await HealthKitManager.shared.requestAuthorization()
                } catch {
                    // L'utilisateur a refusé ou la donnée est indisponible — on continue
                }
            } else {
                userMessage("Pas maintenant")
            }
            await showConclusion()

        default:
            break
        }
    }

    // MARK: — Conclusion

    func complete() async {
        isLoading = true
        _ = try? await APIClient.shared.post(
            "/profile/onboarding-complete",
            body: EmptyBody()
        ) as EmptyResponse
        isLoading = false
        UserDefaults.standard.set(true, forKey: "vita.onboarding.complete")
        NotificationCenter.default.post(name: .vitaOnboardingComplete, object: nil)
    }

    // MARK: — Turns privés

    private func askGoal() async {
        await vitaMessage("Enchanté, \(firstName). Qu'est-ce qui t'a amené à ouvrir VITA aujourd'hui ?")
        withAnimation(.vitaDefault) {
            currentChoices = [
                ConversationChoice(id: "feel_better", label: "Me sentir mieux au quotidien"),
                ConversationChoice(id: "perform",     label: "Progresser dans le sport"),
                ConversationChoice(id: "lose_weight", label: "Perdre du poids"),
                ConversationChoice(id: "recover",     label: "Récupérer d'une période difficile"),
            ]
        }
    }

    private func askActivity() async {
        await vitaMessage("Compris. Tu bouges combien de fois par semaine en ce moment ?")
        withAnimation(.vitaDefault) {
            currentChoices = [
                ConversationChoice(id: "1", label: "Rarement ou jamais"),
                ConversationChoice(id: "2", label: "1 à 2 fois par semaine"),
                ConversationChoice(id: "3", label: "3 à 4 fois par semaine"),
                ConversationChoice(id: "5", label: "Tous les jours ou presque"),
            ]
        }
    }

    private func askWakeTime() async {
        await vitaMessage("Dernière question. Tu te lèves habituellement à quelle heure ?")
        withAnimation(.vitaDefault) {
            currentChoices = [
                ConversationChoice(id: "06:00", label: "Avant 6h30"),
                ConversationChoice(id: "07:00", label: "Entre 6h30 et 7h30"),
                ConversationChoice(id: "08:30", label: "Entre 7h30 et 9h"),
                ConversationChoice(id: "09:30", label: "Après 9h"),
            ]
        }
    }

    private func askHealth() async {
        await vitaMessage("Pour des recommandations plus précises, je peux synchroniser tes données Apple Santé — sommeil, activité, fréquence cardiaque.")
        await vitaMessage("C'est facultatif. Tu peux changer d'avis à tout moment dans tes réglages.")
        withAnimation(.vitaDefault) {
            currentChoices = [
                ConversationChoice(id: "health_yes", label: "Autoriser l'accès"),
                ConversationChoice(id: "health_no",  label: "Pas maintenant"),
            ]
        }
    }

    private func showConclusion() async {
        await vitaMessage("Parfait, \(firstName). Tout est prêt.")
        await vitaMessage("Je vais maintenant préparer ta première recommandation.")
        withAnimation(.vitaDefault) { showDoneButton = true }
    }

    // MARK: — Helpers

    private func vitaMessage(_ text: String) async {
        // Délai avant apparition (simule la frappe)
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.vitaDefault) {
            messages.append(ConversationMessage(text: text, isVita: true))
        }
        // Temps de lecture proportionnel à la longueur, entre 600ms et 1600ms
        let readMs = max(600, min(1_600, text.count * 28))
        try? await Task.sleep(for: .milliseconds(readMs))
    }

    private func userMessage(_ text: String) {
        withAnimation(.vitaDefault) {
            messages.append(ConversationMessage(text: text, isVita: false))
        }
    }

    // Persiste l'état courant à chaque étape — les champs non encore remplis
    // gardent leurs valeurs par défaut, qui seront écrasées aux étapes suivantes.
    private func patchProfile() async {
        struct ProfileBody: Encodable {
            let firstName: String
            let primaryGoal: String
            let activityLevel: Int
            let wakeTime: String
        }
        _ = try? await APIClient.shared.patch(
            "/profile",
            body: ProfileBody(
                firstName: firstName,
                primaryGoal: primaryGoal,
                activityLevel: activityLevel,
                wakeTime: wakeTime
            )
        ) as EmptyResponse
    }

    // MARK: — Labels

    private func goalLabel(for id: String) -> String {
        switch id {
        case "feel_better": return "Me sentir mieux au quotidien"
        case "perform":     return "Progresser dans le sport"
        case "lose_weight": return "Perdre du poids"
        case "recover":     return "Récupérer d'une période difficile"
        default:            return id
        }
    }

    private func activityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Rarement ou jamais"
        case 2: return "1 à 2 fois par semaine"
        case 3: return "3 à 4 fois par semaine"
        case 5: return "Tous les jours ou presque"
        default: return "\(level) fois par semaine"
        }
    }

    private func wakeTimeLabel(for id: String) -> String {
        switch id {
        case "06:00": return "Avant 6h30"
        case "07:00": return "Entre 6h30 et 7h30"
        case "08:30": return "Entre 7h30 et 9h"
        case "09:30": return "Après 9h"
        default:      return id
        }
    }
}
