import Foundation

struct DailyPlan {
    let order: [AksharModule]
}

final class LearningPathEngine {
    private let analyticsStore: AnalyticsStore
    
    init(analyticsStore: AnalyticsStore) {
        self.analyticsStore = analyticsStore
    }
    
    func buildDailyPlan() -> DailyPlan {
        let phonics = analyticsStore.fetchPhonicsSessions().prefix(10)
        let phonicsAvg = phonics.isEmpty ? 0 : Double(phonics.reduce(0) { $0 + (Double($1.correctCount) / Double(max(1, $1.totalAttempts))) * 100 }) / Double(phonics.count)
        
        let writing = analyticsStore.fetchWritingSessions().prefix(10)
        let writingAvg = writing.isEmpty ? 0 : Double(writing.reduce(0) { $0 + Double($1.lettersAccuracy) }) / Double(writing.count)
        
        let readingCheckpoints = analyticsStore.fetchCheckpointResults().prefix(10)
        let readingAvg = readingCheckpoints.isEmpty ? 0 : Double(readingCheckpoints.reduce(0) { $0 + Double($1.accuracy) }) / Double(readingCheckpoints.count)
        
        var moduleScores: [(AksharModule, Double)] = [
            (.phonics, phonicsAvg),
            (.writing, writingAvg),
            (.reading, readingAvg)
        ]
        
        moduleScores.sort { $0.1 < $1.1 }
        
        return DailyPlan(order: moduleScores.map { $0.0 })
    }
}
