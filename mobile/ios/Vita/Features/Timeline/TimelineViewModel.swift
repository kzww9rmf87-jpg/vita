import Foundation

// MARK: — Modèle

struct TimelineEvent: Decodable, Identifiable {
    let id: String
    let type: String
    let time: String      // ISO8601 — formaté côté Vue
    let title: String
    let subtitle: String?
    let icon: String      // SF Symbol
    let colorKey: String
    // meta ignoré à l'affichage : les infos utiles sont dans title/subtitle

    var displayTime: String {
        // Formats tentés dans l'ordre : avec ms / sans ms / date only
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        let date = isoFull.date(from: time) ?? isoBasic.date(from: time)
        guard let d = date else { return "" }

        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: d)
    }

    var accentColor: VitaTimelineColor {
        switch colorKey {
        case "accent", "vita": return .accent
        case "activity":       return .activity
        case "sleep":          return .sleep
        case "nutrition":      return .nutrition
        case "purple":         return .purple
        default:               return .accent
        }
    }
}

// Couleurs nommées pour la timeline — extensible sans modifier TimelineEvent
enum VitaTimelineColor {
    case accent, activity, sleep, nutrition, purple
}

// MARK: — ViewModel

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var events: [TimelineEvent] = []
    @Published var isLoading = false
    @Published var selectedDate = Date()

    var displayedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        if Calendar.current.isDateInToday(selectedDate) {
            return "Aujourd'hui"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Hier"
        } else {
            f.dateFormat = "EEEE d MMMM"
            return f.string(from: selectedDate).capitalized
        }
    }

    var isoSelectedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await APIClient.shared.get(
                "/timeline",
                queryParams: ["date": isoSelectedDate]
            )
        } catch {
            events = []
        }
    }

    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        Task { await load() }
    }

    func goToNextDay() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        guard selectedDate < Calendar.current.startOfDay(for: tomorrow) else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        Task { await load() }
    }

    var canGoToNextDay: Bool {
        !Calendar.current.isDateInToday(selectedDate)
    }
}
