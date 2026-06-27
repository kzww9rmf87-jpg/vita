import HealthKit
import Foundation

// MARK: — HealthKit Manager
// Synchronise automatiquement Apple Health → API VITA

@MainActor
final class HealthKitManager: ObservableObject {

    private let store = HKHealthStore()

    static let shared = HealthKitManager()
    private init() {}

    // MARK: — Autorisation

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let read: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.workoutType(),
        ]

        try await store.requestAuthorization(toShare: [], read: read)
    }

    // MARK: — Synchro données

    func syncToday() async throws {
        async let sleep = fetchLastNightSleep()
        async let steps = fetchTodaySteps()
        async let hrv = fetchLastHRV()

        let (sleepData, stepCount, hrvValue) = try await (sleep, steps, hrv)

        if let sleep = sleepData {
            try await APIClient.shared.post("/sleep", body: sleep) as EmptyResponse
        }

        if let steps = stepCount {
            let body = DailyStepsBody(
                date: Date().isoDateString,
                steps: steps,
                source: "apple_health"
            )
            try await APIClient.shared.post("/activity/steps", body: body) as EmptyResponse
        }
    }

    // MARK: — Sommeil

    func fetchLastNightSleep() async throws -> SleepBody? {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let asleepSamples = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }

                guard !asleepSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let bedtime = asleepSamples.first!.startDate
                let wakeTime = asleepSamples.last!.endDate
                let totalMin = Int(wakeTime.timeIntervalSince(bedtime) / 60)

                let body = SleepBody(
                    date: wakeTime.isoDateString,
                    bedtime: bedtime.iso8601String,
                    wakeTime: wakeTime.iso8601String,
                    durationMinutes: totalMin,
                    qualityScore: 3,
                    source: "apple_health"
                )
                continuation.resume(returning: body)
            }
            self.store.execute(query)
        }
    }

    // MARK: — Pas

    func fetchTodaySteps() async throws -> Int? {
        let stepType = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: Date())

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let steps = stats?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: steps.map { Int($0) })
            }
            self.store.execute(query)
        }
    }

    // MARK: — HRV

    func fetchLastHRV() async throws -> Double? {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: Date())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let hrv = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit(from: "ms"))
                continuation.resume(returning: hrv)
            }
            self.store.execute(query)
        }
    }
}

// MARK: — Corps de requêtes

struct SleepBody: Encodable {
    let date: String
    let bedtime: String?
    let wakeTime: String?
    let durationMinutes: Int?
    let qualityScore: Int
    let source: String
}

struct DailyStepsBody: Encodable {
    let date: String
    let steps: Int
    let source: String
}

// MARK: — Extensions Date

extension Date {
    var isoDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
