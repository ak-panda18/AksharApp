import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "CoreDataStack")

final class CoreDataStack {

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistentStoreRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
    }

    @objc private func persistentStoreRemoteChange(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .coreDataDidSyncFromCloud, object: nil)
        }
    }

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "AksharDataModel")

        let storeURL = NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("AksharDataModel.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically    = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(["journal_mode": "WAL"] as NSDictionary,
                              forKey: NSSQLitePragmasOption)
        
        // CloudKit Sync requirements
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                logger.fault("CoreDataStack: failed to load store – \(error), \(error.userInfo)")
                fatalError("CoreDataStack: failed to load store – \(error), \(error.userInfo)")
            }
        }
        // viewContext automatically picks up changes saved on background contexts.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }()

    // MARK: - Contexts

    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = persistentContainer.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    // MARK: - Background Write
    //
    // Use this for analytics appends and other write-only operations that do
    // not need an immediate return value. The block runs on a private queue so
    // the main thread is never blocked by disk I/O.
    //
    // The caller is responsible for fetching any objects it needs *inside* the
    // block using the supplied context — never pass NSManagedObjects across
    // context boundaries.
    //
    // Because viewContext has automaticallyMergesChangesFromParent = true,
    // UI-bound fetched results controllers update automatically after the
    // background save completes.
    func performBackgroundWrite(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let ctx = newBackgroundContext()
        ctx.perform {
            block(ctx)
            self.save(context: ctx)
        }
    }

    // MARK: - Save

    /// Saves the view (main-thread) context. Always call on the main queue.
    func saveContext() {
        let context = persistentContainer.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            logger.error("CoreDataStack save error: \(nserror), \(nserror.userInfo)")
            assertionFailure("CoreDataStack save error: \(nserror), \(nserror.userInfo)")
        }
    }

    /// Saves an arbitrary context. Safe to call from any queue as long as the
    /// caller is already on that context's queue (i.e. inside a `ctx.perform` block).
    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            logger.error("CoreDataStack background save error: \(nserror), \(nserror.userInfo)")
        }
    }

    // MARK: - Deferred Save

    private var saveTimer: Timer?

    /// Debounces rapid writes (e.g. per-stroke saves during tracing) into a
    /// single disk write after `delay` seconds of inactivity.
    func deferredSave(after delay: TimeInterval = 1.5) {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.saveContext()
        }
    }

    /// Cancels the pending deferred save and writes immediately. Call from
    /// `sceneDidEnterBackground` to prevent data loss on app suspend.
    func flushPendingSave() {
        saveTimer?.invalidate()
        saveTimer = nil
        saveContext()
    }
}
