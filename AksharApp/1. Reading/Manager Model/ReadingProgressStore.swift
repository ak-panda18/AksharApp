import Foundation
import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "ReadingProgressStore")

final class ReadingProgressStore {

    private let coreData: CoreDataStack
    private let childManager: ChildManager

    // Injected after both objects are created in AppDependencyContainer.
    weak var syncService: FirestoreSyncService?

    init(coreDataStack: CoreDataStack, childManager: ChildManager) {
        self.coreData     = coreDataStack
        self.childManager = childManager
    }

    // MARK: - Story Progress

    func getProgress(for storyId: String) -> (Int, Bool) {
        let request = storyRequest(storyId: storyId)
        do {
            if let result = try coreData.context.fetch(request).first {
                return (Int(result.lastPageIndex), result.isCompleted)
            }
        } catch {
            logger.error("ReadingProgressStore: getProgress failed – \(error)")
        }
        return (0, false)
    }

    func saveProgress(storyId: String, pageIndex: Int, didComplete: Bool? = nil) {
        let request = storyRequest(storyId: storyId)
        do {
            let entity: StoryEntity
            if let existing = try coreData.context.fetch(request).first {
                entity = existing
            } else {
                entity = StoryEntity(context: coreData.context)
                entity.storyId = storyId
                entity.childId = childManager.currentChild.id?.uuidString ?? ""
            }
            entity.lastPageIndex = Int16(pageIndex)
            entity.lastReadDate  = Date()
            if let completed = didComplete { entity.isCompleted = completed }
            coreData.saveContext()
            syncService?.pushReadingProgress(storyId: storyId, pageIndex: pageIndex, isCompleted: entity.isCompleted)
        } catch {
            logger.error("ReadingProgressStore: saveProgress failed – \(error)")
        }
    }

    func lastReadEntity() -> StoryEntity? {
        let request: NSFetchRequest<StoryEntity> = StoryEntity.fetchRequest()
        let childId = childManager.currentChild.id?.uuidString ?? ""
        request.predicate       = NSPredicate(format: "childId == %@", childId)
        request.sortDescriptors = [NSSortDescriptor(key: "lastReadDate", ascending: false)]
        request.fetchLimit      = 1
        do {
            return try coreData.context.fetch(request).first
        } catch {
            logger.error("ReadingProgressStore: lastReadEntity failed – \(error)")
            return nil
        }
    }

    // MARK: - Checkpoint Completion

    func isCheckpointCompleted(storyId: String, checkpointText: String) -> Bool {
        let checkId = makeCheckpointId(from: checkpointText)
        let request = storyRequest(storyId: storyId)
        do {
            guard let storyEntity = try coreData.context.fetch(request).first else { return false }
            let completionRequest: NSFetchRequest<CheckpointCompletionEntity> =
                CheckpointCompletionEntity.fetchRequest()
            completionRequest.predicate = NSPredicate(
                format: "story == %@ AND checkpointId == %@", storyEntity, checkId
            )
            completionRequest.fetchLimit = 1
            return (try coreData.context.fetch(completionRequest).first) != nil
        } catch {
            logger.error("ReadingProgressStore: isCheckpointCompleted failed – \(error)")
            return false
        }
    }

    func markCheckpointCompleted(storyId: String, checkpointText: String) {
        let checkId = makeCheckpointId(from: checkpointText)
        let request = storyRequest(storyId: storyId)
        do {
            guard let storyEntity = try coreData.context.fetch(request).first else { return }
            guard !isCheckpointCompleted(storyId: storyId, checkpointText: checkpointText) else { return }
            let completion = CheckpointCompletionEntity(context: coreData.context)
            completion.checkpointId = checkId
            completion.story = storyEntity
            coreData.saveContext()
        } catch {
            logger.error("ReadingProgressStore: markCheckpointCompleted failed – \(error)")
        }
    }

    // MARK: - Stale record cleanup (called on login to remove pre-isolation records)

    /// Deletes all StoryEntity rows whose childId doesn't match the current child.
    /// Handles the migration period where old records had no childId set.
    func clearStaleRecords(keepingChildId childId: String) {
        coreData.performBackgroundWrite { ctx in
            let request: NSFetchRequest<StoryEntity> = StoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "childId == nil OR (childId != %@)", childId)
            if let stale = try? ctx.fetch(request) {
                stale.forEach { ctx.delete($0) }
                logger.info("ReadingProgressStore: deleted \(stale.count) stale StoryEntity records")
            }
        }
    }

    // MARK: - Legacy Migration
    func migrateLegacyCheckpointStrings() {}

    // MARK: - Private Helpers

    private func storyRequest(storyId: String) -> NSFetchRequest<StoryEntity> {
        let childId = childManager.currentChild.id?.uuidString ?? ""
        let r: NSFetchRequest<StoryEntity> = StoryEntity.fetchRequest()
        r.predicate  = NSPredicate(format: "storyId == %@ AND childId == %@", storyId, childId)
        r.fetchLimit = 1
        return r
    }

    private func makeCheckpointId(from text: String) -> String {
        String(text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                   .joined()
                   .prefix(50))
    }
}
