import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "WritingSessionManager")

final class WritingSessionManager {

    private let analyticsStore: AnalyticsStore
    private let childManager:   ChildManager
    private let progressStore:  WritingProgressStore

    private(set) var sessionMistakes: Int = 0

    // MARK: - Running-average cache
    // Avoids a full Core Data fetch on every session finalize.
    // Each tuple is (runningSum, sessionCount) for that content type.
    private var cachedLettersAvg: (sum: Int, count: Int) = (0, 0)
    private var cachedWordsAvg:   (sum: Int, count: Int) = (0, 0)
    private var cachedNumbersAvg: (sum: Int, count: Int) = (0, 0)
    private var cacheLoaded = false

    // MARK: - Init
    init(analyticsStore: AnalyticsStore,
         childManager: ChildManager,
         progressStore: WritingProgressStore) {
        self.analyticsStore = analyticsStore
        self.childManager   = childManager
        self.progressStore  = progressStore
    }

    // MARK: - Session Lifecycle

    func startNewSession() {
        sessionMistakes = 0
    }

    func trackMistake(index: Int, category: String) {
        sessionMistakes += 1
    }

    func didEarnSticker() -> Bool {
        return sessionMistakes <= 2
    }

    // MARK: - Cache

    /// Call when the active child changes so stale cached averages are not used.
    func resetCache() {
        cachedLettersAvg = (0, 0)
        cachedWordsAvg   = (0, 0)
        cachedNumbersAvg = (0, 0)
        cacheLoaded      = false
    }

    /// Loads the running-average cache from Core Data exactly once per child session.
    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        let all = analyticsStore.fetchWritingSessions()
        cachedLettersAvg = (
            all.reduce(0) { $0 + $1.lettersAccuracy },
            all.filter { $0.lettersAccuracy > 0 }.count
        )
        cachedWordsAvg = (
            all.reduce(0) { $0 + $1.wordsAccuracy },
            all.filter { $0.wordsAccuracy > 0 }.count
        )
        cachedNumbersAvg = (
            all.reduce(0) { $0 + $1.numbersAccuracy },
            all.filter { $0.numbersAccuracy > 0 }.count
        )
        cacheLoaded = true
        logger.debug("WritingSessionManager: cache loaded — letters(\(self.cachedLettersAvg.count)) words(\(self.cachedWordsAvg.count)) numbers(\(self.cachedNumbersAvg.count))")
    }

    // MARK: - Finalize

    func finalizeSession(index: Int,
                         category: String,
                         mistakes: Int,
                         contentType: WritingContentType?,
                         tracingCategory: TracingCategory? = nil) {

        loadCacheIfNeeded()

        let sessionScore = Int((1.0 / Double(mistakes + 1)) * 100.0)

        // Select the relevant cache bucket — no Core Data read needed.
        var cache: (sum: Int, count: Int)
        switch contentType {
        case .letters: cache = cachedLettersAvg
        case .numbers: cache = cachedNumbersAvg
        default:       cache = cachedWordsAvg
        }

        let finalScore: Int
        if cache.count == 0 {
            finalScore = sessionScore
        } else {
            // Weighted running average: blend previous average with this session.
            finalScore = (cache.sum + sessionScore) / (cache.count + 1)
        }

        // Update the in-memory cache so subsequent sessions in the same
        // child session don't need a Core Data read either.
        let updatedCache = (sum: cache.sum + sessionScore, count: cache.count + 1)
        switch contentType {
        case .letters: cachedLettersAvg = updatedCache
        case .numbers: cachedNumbersAvg = updatedCache
        default:       cachedWordsAvg   = updatedCache
        }

        let session = WritingSessionData(
            id: UUID(),
            date: Date(),
            childId: childManager.currentChild.id?.uuidString ?? "default",
            lettersAccuracy: contentType == .letters ? finalScore : 0,
            wordsAccuracy:   tracingCategory != nil  ? finalScore : 0,
            numbersAccuracy: contentType == .numbers ? finalScore : 0
        )

        analyticsStore.appendWritingSession(session)
        sessionMistakes = 0

        logger.debug("WritingSessionManager: session finalized. Score=\(finalScore)")
    }
}
