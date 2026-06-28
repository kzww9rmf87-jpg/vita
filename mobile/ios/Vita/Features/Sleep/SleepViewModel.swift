import Foundation

// MARK: — Modèles

struct SleepEntry: Identifiable, Codable, Equatable {
    var id: String { date }
    let date: String
    let bedtime: String?
    let wakeTime: String?
    let durationMinutes: Int?
    let qualityScore: Int
    let awakenings: Int?
    let energyOnWake: Int?
    let napDurationMin: Int?
    let notes: String?
    let source: String?
}

struct SleepEntryCreate: Encodable {
    let date: String
    let bedtime: String?
    let wakeTime: String?
    let durationMinutes: Int?
    let qualityScore: Int
    let awakenings: Int?
    let energyOnWake: Int?
    let napDurationMin: Int?
    let notes: String?
}

// MARK: — ViewModel

@MainActor
final class SleepViewModel: ObservableObject {

    @Published var entries: [SleepEntry] = []
    @Published var latest: SleepEntry?
    @Published var isLoading = false
    @Published var isSaving  = false
    @Published var errorMessage: String?

    // Formulaire de saisie rapide
    @Published var formDate           = Calendar.current.startOfDay(for: Date())
    @Published var formQuality: Int   = 3
    @Published var formDurationHours: Double = 7.5
    @Published var formAwakenings: Int = 0
    @Published var formEnergyOnWake: Int = 3
    @Published var formNotes          = ""

    // MARK: — Chargement

    func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result: [SleepEntry] = try await APIClient.shared.get("/sleep/history?days=30")
            entries = result
            latest = result.first
        } catch {
            errorMessage = "Impossible de charger l'historique."
        }
    }

    // MARK: — Création

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let dateStr = ISO8601DateFormatter.vitaDate.string(from: formDate)
        let body = SleepEntryCreate(
            date: dateStr,
            bedtime: nil,
            wakeTime: nil,
            durationMinutes: Int(formDurationHours * 60),
            qualityScore: formQuality,
            awakenings: formAwakenings,
            energyOnWake: formEnergyOnWake,
            napDurationMin: nil,
            notes: formNotes.isEmpty ? nil : formNotes
        )
        do {
            let _: [String: String] = try await APIClient.shared.post("/sleep", body: body)
            await loadHistory()
            resetForm()
            return true
        } catch {
            errorMessage = "L'enregistrement a échoué."
            return false
        }
    }

    // MARK: — Suppression

    func delete(_ entry: SleepEntry) async {
        do {
            try await APIClient.shared.delete("/sleep/\(entry.date)")
            entries.removeAll { $0.date == entry.date }
            if latest?.date == entry.date { latest = entries.first }
        } catch {
            errorMessage = "Impossible de supprimer cette nuit."
        }
    }

    // MARK: — Utilitaires

    func resetForm() {
        formDate          = Calendar.current.startOfDay(for: Date())
        formQuality       = 3
        formDurationHours = 7.5
        formAwakenings    = 0
        formEnergyOnWake  = 3
        formNotes         = ""
    }

    var formattedDuration: String {
        let h = Int(formDurationHours)
        let m = Int((formDurationHours - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    func durationLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    var latestQualityLabel: String {
        guard let q = latest?.qualityScore else { return "—" }
        return String(repeating: "●", count: q) + String(repeating: "○", count: 5 - q)
    }
}

// MARK: — Helpers

private extension ISO8601DateFormatter {
    static let vitaDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
