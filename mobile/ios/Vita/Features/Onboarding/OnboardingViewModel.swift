import Foundation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case goal
    case activity
    case healthConnect
    case wakeTime
    case done
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step = 0
    @Published var firstName = ""
    @Published var primaryGoal = "feel_better"
    @Published var activityLevel = 3
    @Published var healthConnected = false
    @Published var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    @Published var isLoading = false

    var currentStep: OnboardingStep {
        OnboardingStep(rawValue: step) ?? .done
    }

    var buttonLabel: String {
        switch currentStep {
        case .welcome: return "Commencer"
        case .done: return "Accéder à VITA"
        default: return "Continuer"
        }
    }

    var canAdvance: Bool {
        switch currentStep {
        case .welcome: return firstName.count >= 2
        default: return true
        }
    }

    func advance() async {
        if currentStep == .done {
            await completeOnboarding()
            return
        }

        if currentStep == .welcome {
            await saveProfile()
        }

        withAnimation(.vitaDefault) {
            step += 1
        }
    }

    func back() {
        guard step > 0 else { return }
        step -= 1
    }

    func connectHealth() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthConnected = true
        } catch {
            healthConnected = false
        }
    }

    private struct ProfileUpdateBody: Encodable {
        let firstName: String
        let primaryGoal: String
        let activityLevel: Int
        let wakeTime: String
    }

    private func saveProfile() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let body = ProfileUpdateBody(
            firstName: firstName,
            primaryGoal: primaryGoal,
            activityLevel: activityLevel,
            wakeTime: formatter.string(from: wakeTime)
        )

        _ = try? await APIClient.shared.patch("/profile", body: body) as EmptyResponse
    }

    private func completeOnboarding() async {
        isLoading = true
        _ = try? await APIClient.shared.post("/profile/onboarding-complete", body: EmptyBody()) as EmptyResponse
        isLoading = false

        // Navigation vers l'app principale
        UserDefaults.standard.set(true, forKey: "vita.onboarding.complete")
        NotificationCenter.default.post(name: .vitaOnboardingComplete, object: nil)
    }
}

struct EmptyBody: Encodable {}
