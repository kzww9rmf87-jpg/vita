import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var recommendation: WeekReco?
    @Published var checkinDone = false
    @Published var avgSleepHours: Double?
    @Published var avgEnergy: Double?
    @Published var avgStress: Double?
    @Published var activitySessions: Int?
    @Published var vitaVoice: String?
    @Published var newPatterns: [PatternItem] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let dashTask: Void = loadDashboard()
        async let profileTask: Void = loadProfile()
        _ = await (dashTask, profileTask)
    }

    func handleCheckInComplete() {
        Task { await load() }
    }

    func markRecommendationDone() {
        // La reco dashboard n'a pas d'id persisté côté backend pour l'instant.
        // Le bouton reste présent pour le feedback haptique — l'état est local.
    }

    // MARK: — Chargement

    private func loadDashboard() async {
        do {
            let data: WeekDashboard = try await APIClient.shared.get("/dashboard/week")

            if let sleep = data.sleep {
                avgSleepHours = sleep.avgDuration.map { $0 / 60 }
            }
            if let checkin = data.checkin {
                avgEnergy = checkin.avgEnergy
                avgStress = checkin.avgStress
                checkinDone = (checkin.checkinDays ?? 0) > 0
            }
            activitySessions = data.activity?.sessions

            recommendation = data.recommendation

            vitaVoice = computeVitaVoice(
                sleep: data.sleep,
                checkin: data.checkin,
                activity: data.activity
            )
        } catch {
            // État vide — l'écran reste utilisable
        }
    }

    private func loadProfile() async {
        do {
            let data: ProfileWrapper = try await APIClient.shared.get("/profile")
            firstName = data.profile?.firstName ?? ""
        } catch {}
    }

    private func loadPatterns() async {
        do {
            let patterns: [PatternResponse] = try await APIClient.shared.get("/dashboard/patterns")
            newPatterns = patterns.map { PatternItem(description: $0.description, confidence: $0.confidence) }
        } catch {}
    }

    // MARK: — Voix proactive de VITA
    // Règles par priorité : ce qui mérite d'être nommé en premier.
    // Ton : observationnel, pas prescriptif. 2 phrases max.

    private func computeVitaVoice(
        sleep: SleepStats?,
        checkin: CheckinStats?,
        activity: ActivityStats?
    ) -> String? {
        let sleepH = sleep?.avgDuration.map { $0 / 60 }
        let energy  = checkin?.avgEnergy
        let stress  = checkin?.avgStress
        let sessions = activity?.sessions

        // Sommeil court + énergie basse — les deux se causent mutuellement
        if let h = sleepH, h < 6.5, let e = energy, e < 3.0 {
            return String(format: "%.1fh de sommeil en moyenne, énergie à %.1f/5. Ces deux chiffres ne sont pas indépendants.", h, e)
        }

        // Stress élevé
        if let s = stress, s >= 4.0 {
            return String(format: "Stress à %.1f/5 cette semaine. Qu'est-ce qui pèse en ce moment ?", s)
        }

        // Sommeil court seul
        if let h = sleepH, h < 6.5 {
            return String(format: "%.1fh de sommeil par nuit en moyenne cette semaine. Ton corps récupère moins vite qu'il ne le pourrait.", h)
        }

        // Bon sommeil
        if let h = sleepH, h >= 7.5 {
            return String(format: "%.1fh de sommeil cette semaine. C'est la base sur laquelle tout le reste repose.", h)
        }

        // Semaine active
        if let n = sessions, n >= 3 {
            return "\(n) séances en 7 jours. Le rythme est là."
        }

        // Énergie stable
        if let e = energy, e >= 4.0 {
            return String(format: "Énergie à %.1f/5 cette semaine. Tu es dans une bonne période.", e)
        }

        return nil
    }
}

// MARK: — Réponses API

struct WeekDashboard: Codable {
    let date: String
    let sleep: SleepStats?
    let activity: ActivityStats?
    let nutrition: NutritionStats?
    let checkin: CheckinStats?
    let recommendation: WeekReco?
}

struct WeekReco: Codable {
    let content: String
    let actionType: String?
    let actions: [String]?
    let createdAt: String?
}

struct SleepStats: Codable {
    let avgDuration: Double?
    let avgQuality: Double?
    let daysLogged: Int?
}

struct ActivityStats: Codable {
    let sessions: Int?
    let totalMinutes: Int?
    let avgRpe: Double?
}

struct NutritionStats: Codable {
    let avgCalories: Int?
    let avgProtein: Double?
    let avgAdherence: Double?
}

struct CheckinStats: Codable {
    let avgEnergy: Double?
    let avgMood: Double?
    let avgStress: Double?
    let checkinDays: Int?
}

struct ProfileWrapper: Codable {
    let profile: ProfileData?
}

struct ProfileData: Codable {
    let firstName: String?
    let primaryGoal: String?
}

struct PatternResponse: Codable {
    let patternType: String
    let description: String
    let confidence: Double
    let direction: String?
}

// MARK: — Modèles locaux

struct PatternItem: Identifiable {
    let id = UUID()
    let description: String
    let confidence: Double
}
