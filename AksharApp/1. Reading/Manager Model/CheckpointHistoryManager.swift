import Foundation
import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "CheckpointHistoryManager")

final class CheckpointHistoryManager {

    private let coreData: CoreDataStack

    init(coreDataStack: CoreDataStack) {
        self.coreData = coreDataStack
    }

    // MARK: - Fetching

    func getAllAttempts() -> [CheckpointAttempt] {
        let request: NSFetchRequest<CheckpointAttemptEntity> = CheckpointAttemptEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchBatchSize  = 20
        return fetchAndMap(request: request)
    }

    func getAttempts(for storyTitle: String, checkpointNumber: Int) -> [CheckpointAttempt] {
        let request: NSFetchRequest<CheckpointAttemptEntity> = CheckpointAttemptEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "storyTitle == %@ AND checkpointNumber == %d",
            storyTitle, Int64(checkpointNumber)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchBatchSize  = 20
        return fetchAndMap(request: request)
    }

    func getLastAttempt(for storyTitle: String, checkpointNumber: Int) -> CheckpointAttempt? {
        let request: NSFetchRequest<CheckpointAttemptEntity> = CheckpointAttemptEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "storyTitle == %@ AND checkpointNumber == %d",
            storyTitle, Int64(checkpointNumber)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 1
        return fetchAndMap(request: request).first
    }

    // MARK: - Checkpoint Completion (coordinates all three writes)

    func completeCheckpoint(
        attempt: CheckpointAttempt,
        accuracy: Double,
        storyId: String,
        childId: String,
        checkpointText: String,
        readingSessionId: UUID?,
        readingSessionEndTime: Date,
        additionalTime: TimeInterval,
        storyManager: StoryManager
    ) {
        save(attempt: attempt)

        storyManager.markCheckpointCompleted(storyId: storyId, checkpointText: checkpointText)

        let result = ReadingCheckpointResultData(
            id: UUID(),
            date: Date(),
            storyId: storyId,
            childId: childId,
            accuracy: accuracy * 100,
            checkpointText: checkpointText
        )
        storyManager.analyticsStore.appendCheckpointResult(result)

        if let sessionId = readingSessionId {
            storyManager.analyticsStore.updateReadingSessionEnd(
                sessionId: sessionId,
                endTime: readingSessionEndTime,
                additionalTime: additionalTime
            )
        }
    }

    // MARK: - Saving

    func save(attempt: CheckpointAttempt) {
        let entity = CheckpointAttemptEntity(context: coreData.context)
        entity.id               = UUID()
        entity.storyTitle       = attempt.storyTitle
        entity.checkpointNumber = Int64(attempt.checkpointNumber)
        entity.accuracy         = Int64(attempt.accuracy)
        entity.timestamp        = attempt.timestamp

        // Store each word with its position index so the original spoken
        // order can be recovered on fetch (Set is unordered).
        for (i, word) in attempt.spokenWords.enumerated() {
            let wordEntity = SpokenWordEntity(context: coreData.context)
            wordEntity.word    = word
            wordEntity.order   = Int32(i)
            wordEntity.attempt = entity
        }

        coreData.saveContext()
    }

    // MARK: - Legacy Migration

    func migrateLegacySpokenWords() {}

    // MARK: - Private

    private func fetchAndMap(request: NSFetchRequest<CheckpointAttemptEntity>) -> [CheckpointAttempt] {
        do {
            return try coreData.context.fetch(request).map { entity in
                // Sort by `order` to restore the sequence in which words were spoken.
                // Pre-fix records that have no order value sort stably at position 0.
                let words = ((entity.words as? Set<SpokenWordEntity>) ?? [])
                    .sorted { $0.order < $1.order }
                    .compactMap { $0.word }
                return CheckpointAttempt(
                    storyTitle:       entity.storyTitle ?? "",
                    checkpointNumber: Int(entity.checkpointNumber),
                    accuracy:         Int(entity.accuracy),
                    spokenWords:      words,
                    timestamp:        entity.timestamp ?? Date()
                )
            }
        } catch {
            logger.error("CheckpointHistoryManager: fetch failed – \(error)")
            return []
        }
    }
}
