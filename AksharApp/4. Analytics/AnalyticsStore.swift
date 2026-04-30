import Foundation
import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "AnalyticsStore")

final class AnalyticsStore {

    private let coreData: CoreDataStack
    private let childManager: ChildManager

    // Injected after both objects are created in AppDependencyContainer.
    weak var syncService: FirestoreSyncService?

    init(coreDataStack: CoreDataStack, childManager: ChildManager) {
        self.coreData     = coreDataStack
        self.childManager = childManager
    }

    // MARK: - Migration

    func migrateJSONToCoreData() {
        let legacyURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data   = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode(AnalyticsData.self, from: data)
        else { return }

        // Migration writes are bulk one-off inserts — run them on the main
        // context so the deferred save timer batches them all in one shot.
        legacy.writingSessions.forEach        { appendWritingSession($0) }
        legacy.phonicsSessions.forEach        { appendPhonicsSession($0) }
        legacy.readingSessions.forEach        { appendReadingSession($0) }
        legacy.readingCheckpointResults.forEach { appendCheckpointResult($0) }

        try? FileManager.default.removeItem(at: legacyURL)
        logger.info("AnalyticsStore: legacy JSON migration complete.")
    }

    // MARK: - Writing Sessions

    /// Appends a writing session on a background context so the main thread
    /// is never blocked by the Core Data write + disk flush.
    func appendWritingSession(_ session: WritingSessionData, skipSync: Bool = false) {
        let childObjectID = childManager.currentChild.objectID
        let sync = syncService

        coreData.performBackgroundWrite { ctx in
            let entity = WritingSessionEntity(context: ctx)
            entity.id              = session.id
            entity.date            = session.date
            entity.lettersAccuracy = Int64(session.lettersAccuracy)
            entity.wordsAccuracy   = Int64(session.wordsAccuracy)
            entity.numbersAccuracy = Int64(session.numbersAccuracy)
            entity.child = try? ctx.existingObject(with: childObjectID) as? ChildEntity
            if !skipSync {
                DispatchQueue.main.async { sync?.pushWritingSession(session) }
            }
        }
    }

    func fetchWritingSessions() -> [WritingSessionData] {
        let request: NSFetchRequest<WritingSessionEntity> = WritingSessionEntity.fetchRequest()
        request.predicate       = childPredicate()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapWritingToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchWritingSessions failed – \(error)")
            return []
        }
    }

    func fetchWritingSessions(from date: Date) -> [WritingSessionData] {
        let request: NSFetchRequest<WritingSessionEntity> = WritingSessionEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            childPredicate(),
            NSPredicate(format: "date >= %@", date as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapWritingToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchWritingSessions(from:) failed – \(error)")
            return []
        }
    }

    // MARK: - Phonics Sessions

    /// Appends a phonics session on a background context.
    func appendPhonicsSession(_ session: PhonicsSessionData, skipSync: Bool = false) {
        let childObjectID = childManager.currentChild.objectID
        let sync = syncService

        coreData.performBackgroundWrite { ctx in
            let entity = PhonicsSessionEntity(context: ctx)
            entity.id            = session.id
            entity.date          = session.date
            entity.exerciseType  = session.exerciseType
            entity.correctCount  = Int64(session.correctCount)
            entity.totalAttempts = Int64(session.totalAttempts)
            entity.startTime     = session.startTime
            entity.endTime       = session.endTime
            entity.child         = try? ctx.existingObject(with: childObjectID) as? ChildEntity
            if !skipSync {
                DispatchQueue.main.async { sync?.pushPhonicsSession(session) }
            }
        }
    }

    func fetchPhonicsSessions() -> [PhonicsSessionData] {
        let request: NSFetchRequest<PhonicsSessionEntity> = PhonicsSessionEntity.fetchRequest()
        request.predicate       = childPredicate()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapPhonicsToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchPhonicsSessions failed – \(error)")
            return []
        }
    }

    func fetchPhonicsSessions(from date: Date) -> [PhonicsSessionData] {
        let request: NSFetchRequest<PhonicsSessionEntity> = PhonicsSessionEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            childPredicate(),
            NSPredicate(format: "date >= %@", date as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapPhonicsToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchPhonicsSessions(from:) failed – \(error)")
            return []
        }
    }

    // MARK: - Reading Sessions

    func appendReadingSession(_ session: ReadingSessionData, skipSync: Bool = false) {
        let childObjectID = childManager.currentChild.objectID
        let storyId       = session.storyId
        let sync = syncService

        coreData.performBackgroundWrite { ctx in
            let entity = ReadingSessionEntity(context: ctx)
            entity.id            = session.id
            entity.startTime     = session.startTime
            entity.endTime       = session.endTime
            entity.levelUnlocked = Int64(session.levelUnlocked)
            entity.totalDuration = session.totalDuration
            entity.child         = try? ctx.existingObject(with: childObjectID) as? ChildEntity

            let storyReq: NSFetchRequest<StoryEntity> = StoryEntity.fetchRequest()
            storyReq.predicate  = NSPredicate(format: "storyId == %@", storyId)
            storyReq.fetchLimit = 1
            if let story = try? ctx.fetch(storyReq).first {
                entity.story = story
            }
            if !skipSync {
                DispatchQueue.main.async { sync?.pushReadingSession(session) }
            }
        }
    }

    func fetchReadingSessions() -> [ReadingSessionData] {
        let request: NSFetchRequest<ReadingSessionEntity> = ReadingSessionEntity.fetchRequest()
        request.predicate       = childPredicate()
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapReadingToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchReadingSessions failed – \(error)")
            return []
        }
    }

    func fetchReadingSessions(from date: Date) -> [ReadingSessionData] {
        let request: NSFetchRequest<ReadingSessionEntity> = ReadingSessionEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            childPredicate(),
            NSPredicate(format: "startTime >= %@", date as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapReadingToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchReadingSessions(from:) failed – \(error)")
            return []
        }
    }

    func updateReadingSessionEnd(sessionId: UUID, endTime: Date, additionalTime: TimeInterval = 0) {
        // This is a targeted update that needs an immediate save (not deferred),
        // because the checkpoint flow depends on the updated value being persisted
        // before the next read. Keep it on the main context for simplicity.
        let request: NSFetchRequest<ReadingSessionEntity> = ReadingSessionEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "id == %@", sessionId as CVarArg)
        request.fetchLimit = 1
        do {
            if let entity = try coreData.context.fetch(request).first {
                entity.endTime       = endTime
                entity.totalDuration += additionalTime
                coreData.saveContext()
            }
        } catch {
            logger.error("AnalyticsStore: updateReadingSessionEnd failed – \(error)")
        }
    }

    // MARK: - Checkpoint Results

    func appendCheckpointResult(_ result: ReadingCheckpointResultData, skipSync: Bool = false) {
        let childObjectID = childManager.currentChild.objectID
        let sync = syncService

        coreData.performBackgroundWrite { ctx in
            let entity = CheckpointResultEntity(context: ctx)
            entity.id             = result.id
            entity.date           = result.date
            entity.storyId        = result.storyId
            entity.accuracy       = result.accuracy
            entity.checkpointText = result.checkpointText
            entity.child          = try? ctx.existingObject(with: childObjectID) as? ChildEntity
            if !skipSync {
                DispatchQueue.main.async { sync?.pushCheckpointResult(result) }
            }
        }
    }

    func fetchCheckpointResults() -> [ReadingCheckpointResultData] {
        let request: NSFetchRequest<CheckpointResultEntity> = CheckpointResultEntity.fetchRequest()
        request.predicate       = childPredicate()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize  = 20
        do {
            return try coreData.context.fetch(request).map(mapCheckpointResultToStruct)
        } catch {
            logger.error("AnalyticsStore: fetchCheckpointResults failed – \(error)")
            return []
        }
    }

    // MARK: - Private Helpers

    private func childPredicate() -> NSPredicate {
        NSPredicate(format: "child == %@", childManager.currentChild)
    }
}
