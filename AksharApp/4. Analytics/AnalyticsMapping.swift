import Foundation
import CoreData

extension AnalyticsStore {

    // MARK: Writing
    func mapWritingToStruct(_ entity: WritingSessionEntity) -> WritingSessionData {
        WritingSessionData(
            id: entity.id ?? UUID(),
            date: entity.date ?? Date(),
            childId: entity.child?.id?.uuidString ?? "default",
            lettersAccuracy: Int(entity.lettersAccuracy),
            wordsAccuracy:   Int(entity.wordsAccuracy),
            numbersAccuracy: Int(entity.numbersAccuracy)
        )
    }

    // MARK: Phonics
    func mapPhonicsToStruct(_ entity: PhonicsSessionEntity) -> PhonicsSessionData {
        PhonicsSessionData(
            id: entity.id ?? UUID(),
            date: entity.date ?? Date(),
            childId: entity.child?.id?.uuidString ?? "default",
            exerciseType: entity.exerciseType ?? "",
            correctCount: Int(entity.correctCount),
            totalAttempts: Int(entity.totalAttempts),
            startTime: entity.startTime ?? Date(),
            endTime: entity.endTime
        )
    }

    // MARK: Reading
    func mapReadingToStruct(_ entity: ReadingSessionEntity) -> ReadingSessionData {
        ReadingSessionData(
            id: entity.id ?? UUID(),
            storyId: entity.story?.storyId ?? "",
            childId: entity.child?.id?.uuidString ?? "default",
            totalDuration: entity.totalDuration,
            startTime: entity.startTime ?? Date(),
            endTime: entity.endTime,
            levelUnlocked: Int(entity.levelUnlocked)
        )
    }

    func mapCheckpointResultToStruct(_ entity: CheckpointResultEntity) -> ReadingCheckpointResultData {
        ReadingCheckpointResultData(
            id: entity.id ?? UUID(),
            date: entity.date ?? Date(),
            storyId: entity.storyId ?? "",
            childId: entity.child?.id?.uuidString ?? "default",
            accuracy: entity.accuracy,
            checkpointText: entity.checkpointText ?? ""
        )
    }

    // MARK: Checkpoint Attempt
    func mapAttemptToStruct(_ entity: CheckpointAttemptEntity) -> CheckpointAttempt {
        // Words are sorted by their stored order so spoken-word sequence is preserved.
        let words = ((entity.words as? Set<SpokenWordEntity>) ?? [])
            .sorted { $0.order < $1.order }
            .compactMap { $0.word }
        return CheckpointAttempt(
            storyTitle: entity.storyTitle ?? "",
            checkpointNumber: Int(entity.checkpointNumber),
            accuracy: Int(entity.accuracy),
            spokenWords: words,
            timestamp: entity.timestamp ?? Date()
        )
    }
}

// MARK: - Analytics Aggregation Layer
struct AnalyticsAggregator {

    // MARK: - Shared private helper
    //
    // Both `periodAverage` and `writingGraphData` previously contained an
    // identical copy of this running-average reversal algorithm.
    // It now lives here exactly once.
    //
    // Background: Core Data stores a *cumulative running average* per session
    // rather than the raw session score. This function reverses that to recover
    // the individual session score for each data point so graphs and period
    // averages are computed from real per-session values.
    private static func reconstructRealScores(
        from sessions: [WritingSessionData],
        keyPath: KeyPath<WritingSessionData, Int>
    ) -> [(date: Date, score: Int)] {
        let sorted = sessions
            .filter { $0[keyPath: keyPath] > 0 }
            .sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        var result: [(date: Date, score: Int)] = []
        var runningSum = 0

        for (index, session) in sorted.enumerated() {
            let avg = session[keyPath: keyPath]
            if index == 0 {
                result.append((session.date, avg))
                runningSum += avg
            } else {
                let prevTotalTruncated = (runningSum / index) * index
                let sessionScore = min(max((avg * (index + 1)) - prevTotalTruncated, 0), 100)
                result.append((session.date, sessionScore))
                runningSum += avg
            }
        }
        return result
    }

    // MARK: - Period Average
    static func periodAverage(
        allSessions: [WritingSessionData],
        keyPath: KeyPath<WritingSessionData, Int>,
        startDate: Date,
        endDate: Date
    ) -> Int? {
        let realScores = reconstructRealScores(from: allSessions, keyPath: keyPath)
        guard !realScores.isEmpty else { return nil }

        let periodScores = realScores.filter { $0.date >= startDate && $0.date < endDate }
        guard !periodScores.isEmpty else { return nil }

        let total = periodScores.reduce(0) { $0 + $1.score }
        return total / periodScores.count
    }

    // MARK: - Writing

    static func latestScore(
        from sessions: [WritingSessionData],
        contentType: WritingContentType
    ) -> Int? {
        let filtered: [WritingSessionData]
        switch contentType {
        case .letters: filtered = sessions.filter { $0.lettersAccuracy > 0 }
        case .words:   filtered = sessions.filter { $0.wordsAccuracy   > 0 }
        case .numbers: filtered = sessions.filter { $0.numbersAccuracy > 0 }
        }

        guard let latest = filtered.sorted(by: { $0.date > $1.date }).first else {
            return nil
        }

        switch contentType {
        case .letters: return latest.lettersAccuracy
        case .words:   return latest.wordsAccuracy
        case .numbers: return latest.numbersAccuracy
        }
    }

    static func delta(current: Int?, previous: Int?) -> Int? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    static func writingGraphData(
        allSessions: [WritingSessionData],
        keyPath: KeyPath<WritingSessionData, Int>,
        isWeekly: Bool
    ) -> [AccuracyPoint] {
        let realScores = reconstructRealScores(from: allSessions, keyPath: keyPath)
        guard !realScores.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let daysToSubtract = isWeekly ? -7 : -30
        guard let cutoffDate = calendar.date(byAdding: .day, value: daysToSubtract, to: now) else { return [] }

        let filteredScores = realScores.filter { $0.date >= cutoffDate }

        let grouped = Dictionary(grouping: filteredScores) { item -> Date in
            if isWeekly {
                return calendar.startOfDay(for: item.date)
            } else {
                return calendar.dateInterval(of: .weekOfYear, for: item.date)?.start
                    ?? calendar.startOfDay(for: item.date)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = isWeekly ? "E" : "d MMM"

        return grouped.keys.sorted().map { date in
            let values = grouped[date]!.map { $0.score }
            let avg = values.reduce(0, +) / values.count
            return AccuracyPoint(dateLabel: formatter.string(from: date), value: avg)
        }
    }

    // MARK: - Phonics
    static func phonicsOverview(
        sessions: [PhonicsSessionData]
    ) -> (sound: Int?, quiz: Int?, rhyme: Int?, word: Int?, fluency: Int?, hasData: Bool) {

        guard !sessions.isEmpty else {
            return (nil, nil, nil, nil, nil, false)
        }

        func accuracy(type: String) -> Int? {
            let filtered = sessions.filter { $0.exerciseType == type }
            let totalCorrect  = filtered.reduce(0) { $0 + $1.correctCount }
            let totalAttempts = filtered.reduce(0) { $0 + $1.totalAttempts }
            guard totalAttempts > 0 else { return nil }
            return Int((Double(totalCorrect) / Double(totalAttempts)) * 100)
        }

        let fluencySessions = sessions.filter { $0.exerciseType == "fluency_drill" }
        let totalCorrect    = fluencySessions.reduce(0) { $0 + $1.correctCount }
        let totalDuration   = fluencySessions.reduce(0.0) { result, session in
            guard let end = session.endTime else { return result }
            return result + end.timeIntervalSince(session.startTime)
        }
        let minutes = totalDuration / 60
        let fluency: Int? = minutes > 0 ? Int(Double(totalCorrect) / minutes) : nil

        return (
            accuracy(type: "sound_detector"),
            accuracy(type: "quiz_my_story"),
            accuracy(type: "rhyme_words"),
            accuracy(type: "word_builder"),
            fluency,
            true
        )
    }

    // MARK: - Reading Checkpoint Aggregation
    static func weeklyCheckpointStats(attempts: [CheckpointAttempt]) -> [DailyStats] {
        var groupedData: [Date: [Int]] = [:]
        let calendar = Calendar.current

        for attempt in attempts {
            let dateKey = calendar.startOfDay(for: attempt.timestamp)
            groupedData[dateKey, default: []].append(attempt.accuracy)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"

        return groupedData.keys.sorted(by: { $0 > $1 }).prefix(7).map { date in
            let scores  = groupedData[date] ?? []
            let average = scores.reduce(0, +) / scores.count
            return DailyStats(date: date, accuracy: average, formattedDate: formatter.string(from: date))
        }
    }

    static func monthlyCheckpointStats(attempts: [CheckpointAttempt]) -> [DailyStats] {
        let calendar = Calendar.current
        let now      = Date()
        var weeklyBuckets: [[Int]] = [[], [], [], []]

        for attempt in attempts {
            guard let daysAgo = calendar.dateComponents([.day], from: attempt.timestamp, to: now).day else { continue }
            switch daysAgo {
            case  0..<7:  weeklyBuckets[3].append(attempt.accuracy)
            case  7..<14: weeklyBuckets[2].append(attempt.accuracy)
            case 14..<21: weeklyBuckets[1].append(attempt.accuracy)
            case 21..<28: weeklyBuckets[0].append(attempt.accuracy)
            default: break
            }
        }

        let labels = ["3 Weeks Ago", "2 Weeks Ago", "Last Week", "This Week"]
        return (0..<4).compactMap { i -> DailyStats? in
            let scores = weeklyBuckets[i]
            guard !scores.isEmpty else { return nil }
            let average = scores.reduce(0, +) / scores.count
            return DailyStats(date: now, accuracy: average, formattedDate: labels[i])
        }
    }
}
