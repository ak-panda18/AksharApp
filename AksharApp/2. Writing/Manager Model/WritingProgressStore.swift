import Foundation
import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "WritingProgressStore")

// MARK: - WritingProgressStore
//
// MIGRATION REQUIRED — before shipping this file, add two new entities to
// AksharDataModel.xcdatamodeld:
//
// Entity: WritingUnlockEntity
//   Attributes:  category       String
//                unlockedIndex  Integer 32
//   Relationship: progress → WritingProgressEntity  (to-one, inverse: unlocks)
//
// Entity: WritingMistakeEntity
//   Attributes:  compositeKey  String   (format: "<category>_<index>", e.g. "letters_3")
//                mistakeCount  Integer 32
//   Relationship: progress → WritingProgressEntity  (to-one, inverse: mistakes)
//
// On WritingProgressEntity, add:
//   Relationship: unlocks → WritingUnlockEntity  (to-many, delete rule: Cascade, inverse: progress)
//   Relationship: mistakes → WritingMistakeEntity (to-many, delete rule: Cascade, inverse: progress)
//
// Then bump the Core Data model version so lightweight migration runs automatically.
// The `migrateJSONIfNeeded` method below handles converting any existing JSON blob
// data into the new relational rows on first launch.

final class WritingProgressStore {

    private let coreData: CoreDataStack
    private let childManager: ChildManager

    // Injected after both objects are created in AppDependencyContainer.
    weak var syncService: FirestoreSyncService?

    // MARK: - Init

    init(coreDataStack: CoreDataStack, childManager: ChildManager) {
        self.coreData     = coreDataStack
        self.childManager = childManager
        migrateJSONIfNeeded()
    }

    // MARK: - Category

    var lastActiveCategory: String {
        get { progressEntity().lastActiveCategory ?? "letters" }
        set { progressEntity().lastActiveCategory = newValue; coreData.saveContext() }
    }

    // MARK: - Unlock

    func getHighestUnlockedIndex(category: String) -> Int {
        let request: NSFetchRequest<WritingUnlockEntity> = WritingUnlockEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "progress == %@ AND category == %@",
                                          progressEntity(), category)
        request.sortDescriptors = [NSSortDescriptor(key: "unlockedIndex", ascending: false)]
        request.fetchLimit = 1
        return Int((try? coreData.context.fetch(request).first?.unlockedIndex) ?? 0)
    }

    func unlockNextItem(category: String, currentIndex: Int) {
        let current = getHighestUnlockedIndex(category: category)
        guard currentIndex >= current else { return }

        let request: NSFetchRequest<WritingUnlockEntity> = WritingUnlockEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "progress == %@ AND category == %@",
                                          progressEntity(), category)
        request.fetchLimit = 1

        let entity: WritingUnlockEntity
        if let existing = try? coreData.context.fetch(request).first {
            entity = existing
        } else {
            entity          = WritingUnlockEntity(context: coreData.context)
            entity.category = category
            entity.progress = progressEntity()
        }
        entity.unlockedIndex = Int32(currentIndex + 1)
        coreData.saveContext()
        syncService?.pushWritingUnlock(category: category, index: currentIndex + 1)
    }

    func isIndexUnlocked(index: Int, category: String) -> Bool {
        return index <= getHighestUnlockedIndex(category: category)
    }

    // MARK: - Mistakes

    func getMistakeCount(index: Int, category: String) -> Int {
        let key     = compositeKey(category: category, index: index)
        let request: NSFetchRequest<WritingMistakeEntity> = WritingMistakeEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "progress == %@ AND compositeKey == %@",
                                          progressEntity(), key)
        request.fetchLimit = 1
        return Int((try? coreData.context.fetch(request).first?.mistakeCount) ?? 0)
    }

    func saveMistakeCount(_ count: Int, index: Int, category: String) {
        let key     = compositeKey(category: category, index: index)
        let request: NSFetchRequest<WritingMistakeEntity> = WritingMistakeEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "progress == %@ AND compositeKey == %@",
                                          progressEntity(), key)
        request.fetchLimit = 1

        let entity: WritingMistakeEntity
        if let existing = try? coreData.context.fetch(request).first {
            entity = existing
        } else {
            entity              = WritingMistakeEntity(context: coreData.context)
            entity.compositeKey = key
            entity.progress     = progressEntity()
        }
        entity.mistakeCount = Int32(count)
        coreData.saveContext()
        syncService?.pushWritingMistake(category: category, index: index, count: count)
    }

    // MARK: - Character Helpers

    func characterString(for index: Int, contentType: WritingContentType) -> String {
        switch contentType {
        case .words:
            preconditionFailure("WritingProgressStore: words handled by WordTraceContentProvider")
        case .letters:
            let base       = index / 2
            let isLower    = (index % 2 != 0)
            let asciiStart = isLower ? 97 : 65
            return String(UnicodeScalar(asciiStart + base)!)
        case .numbers:
            return "\(index)"
        }
    }

    // MARK: - Progress Fraction

    func progress(for category: String, total: Int) -> Float {
        guard total > 0 else { return 0 }
        return min(max(Float(getHighestUnlockedIndex(category: category)) / Float(total), 0), 1)
    }

    // MARK: - Private Helpers

    private func compositeKey(category: String, index: Int) -> String {
        "\(category)_\(index)"
    }

    /// Returns the WritingProgressEntity for the current child, creating one if needed.
    private func progressEntity() -> WritingProgressEntity {
        let childId = childManager.currentChild.id?.uuidString ?? "default"
        let request: NSFetchRequest<WritingProgressEntity> = WritingProgressEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "childId == %@", childId)
        request.fetchLimit = 1

        if let existing = try? coreData.context.fetch(request).first {
            return existing
        }

        let e               = WritingProgressEntity(context: coreData.context)
        e.lastActiveCategory = "letters"
        e.childId            = childId
        coreData.saveContext()
        logger.info("WritingProgressStore: created new entity for child \(childId)")
        return e
    }

    // MARK: - One-time JSON Migration
    //
    // Converts the old JSON blob data stored in `unlockedIndicesData` and
    // `mistakeCountsData` into proper WritingUnlockEntity / WritingMistakeEntity
    // rows. Runs once on first launch after the app update; no-ops thereafter.

    private func migrateJSONIfNeeded() {
        // Phase 1 — migrate from the external writing_progress.json file (pre-CoreData era).
        migrateExternalJSONIfNeeded()

        // Phase 2 — migrate from the JSON-blob-in-CoreData era to proper relational rows.
        migrateBlobsToRelationalRowsIfNeeded()
    }

    private func migrateExternalJSONIfNeeded() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("writing_progress.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data   = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(LegacyWritingProgressState.self, from: data)
        else { return }

        let e = progressEntity()
        e.lastActiveCategory = legacy.lastActiveCategory

        // Write unlock rows
        for (category, index) in legacy.unlockedIndices {
            let unlockEntity          = WritingUnlockEntity(context: coreData.context)
            unlockEntity.category     = category
            unlockEntity.unlockedIndex = Int32(index)
            unlockEntity.progress     = e
        }

        // Write mistake rows
        for (key, count) in legacy.mistakeCounts {
            let mistakeEntity          = WritingMistakeEntity(context: coreData.context)
            mistakeEntity.compositeKey = key
            mistakeEntity.mistakeCount = Int32(count)
            mistakeEntity.progress     = e
        }

        coreData.saveContext()
        try? FileManager.default.removeItem(at: url)
        logger.info("WritingProgressStore: migrated legacy JSON file to Core Data.")
    }

    private func migrateBlobsToRelationalRowsIfNeeded() {
        // Fetch any WritingProgressEntity that still has blob data populated.
        let request: NSFetchRequest<WritingProgressEntity> = WritingProgressEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "unlockedIndicesData != nil AND unlockedIndicesData != %@", "{}"
        )

        guard let entities = try? coreData.context.fetch(request),
              !entities.isEmpty else { return }

        for e in entities {
            // Decode the old JSON blobs.
            let unlockedIndices = decodeBlob(e.unlockedIndicesData)
            let mistakeCounts   = decodeBlob(e.mistakeCountsData)

            // Insert relational rows only if none exist yet (idempotent).
            for (category, index) in unlockedIndices {
                let dupeCheck: NSFetchRequest<WritingUnlockEntity> = WritingUnlockEntity.fetchRequest()
                dupeCheck.predicate  = NSPredicate(format: "progress == %@ AND category == %@", e, category)
                dupeCheck.fetchLimit = 1
                guard (try? coreData.context.fetch(dupeCheck).first) == nil else { continue }

                let unlockEntity           = WritingUnlockEntity(context: coreData.context)
                unlockEntity.category      = category
                unlockEntity.unlockedIndex = Int32(index)
                unlockEntity.progress      = e
            }

            for (key, count) in mistakeCounts {
                let dupeCheck: NSFetchRequest<WritingMistakeEntity> = WritingMistakeEntity.fetchRequest()
                dupeCheck.predicate  = NSPredicate(format: "progress == %@ AND compositeKey == %@", e, key)
                dupeCheck.fetchLimit = 1
                guard (try? coreData.context.fetch(dupeCheck).first) == nil else { continue }

                let mistakeEntity           = WritingMistakeEntity(context: coreData.context)
                mistakeEntity.compositeKey  = key
                mistakeEntity.mistakeCount  = Int32(count)
                mistakeEntity.progress      = e
            }

            // Nil out the blob columns so this migration won't run again for this entity.
            e.unlockedIndicesData = nil
            e.mistakeCountsData   = nil
        }

        coreData.saveContext()
        logger.info("WritingProgressStore: migrated \(entities.count) blob entity/entities to relational rows.")
    }

    private func decodeBlob(_ string: String?) -> [String: Int] {
        guard let s = string,
              let data = s.data(using: .utf8),
              let result = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return result
    }
}

// MARK: - Legacy model (external JSON file era)

private struct LegacyWritingProgressState: Codable {
    var unlockedIndices:    [String: Int] = [:]
    var mistakeCounts:      [String: Int] = [:]
    var lastActiveCategory: String = "letters"
}
