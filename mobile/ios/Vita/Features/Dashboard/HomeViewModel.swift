import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recommendation: DailyRecommendation?
    @Published var checkinDone = false
    @Published var dayScore = 0
    @Published var level = 1
    @Published var firstName = ""
    @Published var sleepSummary = "—"
    @Published var activitySummary = "—"
    @Published var nutritionSummary = "—"
    @Published var newPatterns: [PatternItem] = []
    @Published var streaks: [StreakItem] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let dashboardTask = loadDashboard()
        async let patternsTask = loadPatterns()
        let _ = await (dashboardTask, patternsTask)
    }

    // Appelé par VitaThinkingView via NotificationCenter quand le check-in est terminé
    func handleCheckInComplete() {
        Task { await load() }
    }

    private func loadDashboard() async {
        do {
            let data: WeekDashboard = try await APIClient.shared.get("/dashboard/week")

            firstName = data.profile?.firstName ?? ""
            dayScore = data.score
            level = data.xp?.level ?? 1

            if let sleep = data.sleep {
                let hours = (sleep.avgDuration ?? 0) / 60
                sleepSummary = String(format: "%.1fh", hours)
            }

            if let act = data.activity {
                activitySummary = "\(act.sessions ?? 0) séances"
            }

            if let nut = data.nutrition {
                let pct = Int((nut.avgAdherence ?? 0) * 100)
                nutritionSummary = "\(pct)%"
            }

            recommendation = data.recommendation
            checkinDone = data.checkin != nil

            streaks = (data.streaks ?? []).map { s in
                StreakItem(
                    streakType: s.streakType,
                    currentCount: s.currentCount,
                    label: labelFor(s.streakType)
                )
            }
        } catch {
            // Silencieux — afficher état vide
        }
    }

    private func loadPatterns() async {
        do {
            let patterns: [PatternResponse] = try await APIClient.shared.get("/dashboard/patterns")
            newPatterns = patterns.map { PatternItem(description: $0.description, confidence: $0.confidence) }
        } catch {}
    }

    func markRecommendationDone() {
        guard let id = recommendation?.id else { return }
        Task {
            _ = try? await APIClient.shared.patch(
                "/recommendations/\(id)/complete",
                body: ["completed": true]
            ) as EmptyResponse
        }
    }

    private func labelFor(_ type: String) -> String {
        switch type {
        case "checkin": return "Check-ins"
        case "sleep": return "Sommeil"
        case "protein": return "Protéines"
        case "activity": return "Activité"
        case "no_skip": return "Sans saut"
        default: return type
        }
    }
}

// MARK: — Réponses API

struct WeekDashboard: Codable {
    let date: String
    let score: Int
    let sleep: SleepStats?
    let activity: ActivityStats?
    let nutrition: NutritionStats?
    let checkin: CheckinStats?
    let recommendation: DailyRecommendation?
    let streaks: [StreakResponse]?
    let xp: XPResponse?
    let profile: ProfileResponse?
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
}

struct StreakResponse: Codable {
    let streakType: String
    let currentCount: Int
    let bestCount: Int
}

struct XPResponse: Codable {
    let totalXp: Int
    let level: Int
}

struct ProfileResponse: Codable {
    let firstName: String?
    let primaryGoal: String?
}

struct PatternResponse: Codable {
    let patternType: String
    let description: String
    let confidence: Double
    let direction: String?
}
