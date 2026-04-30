import CoreData
import UIKit
import FirebaseAuth
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "ChildManager")

final class ChildManager {

    private let coreData: CoreDataStack
    private let activeKey = "activeChildId"
    private(set) var currentChild: ChildEntity

    // Injected after both objects are created in AppDependencyContainer.
    weak var syncService: FirestoreSyncService?

    // MARK: - Init
    init(coreDataStack: CoreDataStack) {
        self.coreData = coreDataStack
        currentChild  = ChildManager.resolveActiveChild(
            context: coreDataStack.context,
            activeKey: "activeChildId",
            coreDataStack: coreDataStack
        )
    }

    // MARK: - Firebase UID
    func linkFirebaseUID(_ uid: String) {
        currentChild.firebaseUID = uid
        coreData.saveContext()
        UserDefaults.standard.set(uid, forKey: "firebaseUID")
    }

    func resolveChild(uid: String) {
        let request: NSFetchRequest<ChildEntity> = ChildEntity.fetchRequest()
        request.predicate  = NSPredicate(format: "firebaseUID == %@", uid)
        request.fetchLimit = 1

        if let match = try? coreData.context.fetch(request).first {
            logger.info("ChildManager: resolved existing child id=\(match.id?.uuidString ?? "nil")")
            currentChild = match
            UserDefaults.standard.set(match.id?.uuidString, forKey: activeKey)
        } else {
            logger.info("ChildManager: no entity found for uid \(uid) — creating new ChildEntity")
            let child         = ChildEntity(context: coreData.context)
            child.id          = UUID()
            child.firebaseUID = uid
            child.name        = Auth.auth().currentUser?.displayName ?? "Child"
            child.firstName   = Auth.auth().currentUser?.displayName ?? ""
            child.createdAt   = Date()
            coreData.saveContext()
            currentChild = child
            UserDefaults.standard.set(child.id?.uuidString, forKey: activeKey)
            UserDefaults.standard.set(uid, forKey: "firebaseUID")
        }
    }

    // MARK: - Profile data save
    func saveProfileData() {
        coreData.saveContext()
        let child = currentChild
        syncService?.pushProfile(
            firstName: child.firstName ?? "",
            lastName:  child.lastName  ?? "",
            age:       Int(child.age),
            gender:    child.gender    ?? "",
            name:      child.name      ?? ""
        )
    }

    // MARK: - Account deletion
    func deleteCurrentChild() {
        coreData.context.delete(currentChild)
        coreData.saveContext()
        UserDefaults.standard.removeObject(forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: "firebaseUID")
        logger.info("ChildManager: deleted current child and cleared UserDefaults keys")
    }

    // MARK: - Child Management
    func allChildren() -> [ChildEntity] {
        let r: NSFetchRequest<ChildEntity> = ChildEntity.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? coreData.context.fetch(r)) ?? []
    }

    func setActiveChild(_ child: ChildEntity) {
        guard let id = child.id?.uuidString else { return }
        UserDefaults.standard.set(id, forKey: activeKey)
        currentChild = child
    }

    @discardableResult
    func addChild(name: String) -> ChildEntity {
        let child = ChildEntity(context: coreData.context)
        child.id = UUID(); child.name = name; child.createdAt = Date()
        coreData.saveContext()
        return child
    }

    // MARK: - Private
    private static func resolveActiveChild(
        context: NSManagedObjectContext,
        activeKey: String,
        coreDataStack: CoreDataStack
    ) -> ChildEntity {
        let request: NSFetchRequest<ChildEntity> = ChildEntity.fetchRequest()
        if let savedId = UserDefaults.standard.string(forKey: activeKey),
           let uuid = UUID(uuidString: savedId) {
            request.predicate  = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            if let match = try? context.fetch(request).first { return match }
        }
        request.predicate    = nil
        request.fetchLimit   = 0
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let first = try? context.fetch(request).first {
            UserDefaults.standard.set(first.id?.uuidString, forKey: activeKey)
            return first
        }
        let child = ChildEntity(context: context)
        child.id = UUID(); child.name = "Default Child"; child.createdAt = Date()
        coreDataStack.saveContext()
        UserDefaults.standard.set(child.id?.uuidString, forKey: activeKey)
        return child
    }
}
