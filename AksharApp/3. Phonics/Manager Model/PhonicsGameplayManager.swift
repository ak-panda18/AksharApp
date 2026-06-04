import Foundation

final class PhonicsGameplayManager {

    // MARK: - Dependencies
    private let analyticsStore: AnalyticsStore
    private let childManager: ChildManager

    // MARK: - State
    private var cycle: RandomizedQuestionCycle?
    private var session: PhonicsSessionData?
    private var currentCycleKey: String = ""
    private var hasSavedSession = false

    // MARK: - Init
    init(analyticsStore: AnalyticsStore, childManager: ChildManager) {
        self.analyticsStore = analyticsStore
        self.childManager   = childManager
    }

    // MARK: - Session Lifecycle
    func startSession(for exercise: ExerciseType, totalQuestions: Int, startPointer: Int) {
        hasSavedSession  = false
        // Scope the cycle key to the current child's UID to prevent cross-profile leaks.
        let uid = childManager.currentChild.firebaseUID ?? childManager.currentChild.id?.uuidString ?? "unknown"
        currentCycleKey  = exercise.cycleKey(uid: uid)

        cycle = loadCycle(key: currentCycleKey)
            ?? RandomizedQuestionCycle(count: totalQuestions, startPointer: startPointer)

        session = PhonicsSessionData(
            id: UUID(),
            date: Date(),
            childId: childManager.currentChild.id?.uuidString ?? "unknown",
            exerciseType: exercise.exerciseKey,
            correctCount: 0,
            totalAttempts: 0,
            startTime: Date(),
            endTime: nil
        )
    }

    func endSession() {
        guard !hasSavedSession, var s = session else { return }
        s.endTime = Date()
        analyticsStore.appendPhonicsSession(s)
        hasSavedSession = true
    }

    func clearCycleProgress() {
        iCloudKeyValueStore.shared.removeObject(forKey: currentCycleKey)
    }

    /// Clears all cycle keys for all exercise types for this child. Call on logout.
    func clearAllCycleProgress() {
        let uid = childManager.currentChild.firebaseUID ?? childManager.currentChild.id?.uuidString ?? "unknown"
        ExerciseType.allCases.forEach {
            iCloudKeyValueStore.shared.removeObject(forKey: $0.cycleKey(uid: uid))
        }
    }

    // MARK: - Game Loop
    func getCurrentIndex() -> Int {
        return cycle?.currentIndex() ?? 0
    }

    func getCyclePointer() -> Int {
        return cycle?.pointer ?? 0
    }

    func advanceToNext() {
        cycle?.moveToNext()
        if let c = cycle { saveCycle(c, key: currentCycleKey) }
    }

    func recordSuccess() { session?.correctCount += 1 }
    func recordAttempt() { session?.totalAttempts += 1 }

    // MARK: - Persistence
    private func saveCycle(_ cycle: RandomizedQuestionCycle, key: String) {
        if let data = try? JSONEncoder().encode(cycle) {
            iCloudKeyValueStore.shared.set(data, forKey: key)
        }
    }

    private func loadCycle(key: String) -> RandomizedQuestionCycle? {
        guard let data = iCloudKeyValueStore.shared.data(forKey: key),
              let cycle = try? JSONDecoder().decode(RandomizedQuestionCycle.self, from: data)
        else { return nil }
        return cycle
    }
}

// MARK: - RandomizedQuestionCycle
struct RandomizedQuestionCycle: Codable {
    private(set) var indices: [Int]
    private(set) var pointer: Int

    init(count: Int, startPointer: Int = 0) {
        indices = Array(0..<count).shuffled()
        pointer = min(startPointer, max(count - 1, 0))
    }

    func currentIndex() -> Int { indices[pointer] }

    mutating func moveToNext() {
        pointer += 1
        if pointer >= indices.count {
            indices.shuffle()
            pointer = 0
        }
    }
}
