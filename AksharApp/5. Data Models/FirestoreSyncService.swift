// FirestoreSyncService.swift
//
// SETUP REQUIRED:
// 1. In Xcode: File → Add Package → https://github.com/firebase/firebase-ios-sdk
//    Add FirebaseFirestore to your target (you already have FirebaseAuth).
// 2. In AppDelegate, FirebaseApp.configure() is already called — nothing extra needed.
// 3. In Firestore console: create a database in Native mode.
//    Security rules (development — tighten before production):
//
//    rules_version = '2';
//    service cloud.firestore {
//      match /databases/{database}/documents {
//        match /users/{uid}/{document=**} {
//          allow read, write: if request.auth != null && request.auth.uid == uid;
//        }
//      }
//    }

import Foundation
import FirebaseFirestore
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp",
                            category: "FirestoreSyncService")

// MARK: - Firestore document schema
//
// /users/{uid}/
//   readingProgress/{storyId}   → { lastPageIndex, isCompleted, lastReadDate }
//   writingUnlocks/{category}   → { unlockedIndex }
//   writingMistakes/{key}       → { mistakeCount }       key = "letters_3"
//   writingSessions/{id}        → WritingSessionData fields
//   phonicsSessions/{id}        → PhonicsSessionData fields
//   readingSessions/{id}        → ReadingSessionData fields
//   checkpointResults/{id}      → ReadingCheckpointResultData fields
//   checkpointAttempts/{id}     → CheckpointAttempt fields
//   streakDates/record          → { visitedDates: [String] }   ISO-8601 yyyy-MM-dd

final class FirestoreSyncService {

    // MARK: - Dependencies
    private let analyticsStore:          AnalyticsStore
    private let readingProgressStore:    ReadingProgressStore
    private let writingProgressStore:    WritingProgressStore
    private let checkpointHistoryManager: CheckpointHistoryManager
    private let childManager:            ChildManager

    // MARK: - Firestore
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    // MARK: - User root
    private var uid: String = ""
    private var root: CollectionReference { db.collection("users").document(uid).collection("data") }
    // Helper: sub-collection under the user doc
    private func col(_ name: String) -> CollectionReference {
        db.collection("users").document(uid).collection(name)
    }

    // MARK: - Init
    init(analyticsStore: AnalyticsStore,
         readingProgressStore: ReadingProgressStore,
         writingProgressStore: WritingProgressStore,
         checkpointHistoryManager: CheckpointHistoryManager,
         childManager: ChildManager) {
        self.analyticsStore           = analyticsStore
        self.readingProgressStore     = readingProgressStore
        self.writingProgressStore     = writingProgressStore
        self.checkpointHistoryManager = checkpointHistoryManager
        self.childManager             = childManager
    }

    // MARK: - Lifecycle

    /// Call immediately after resolveChild(uid:) succeeds in SceneDelegate.
    func startSync(uid: String) {
        guard !uid.isEmpty else { return }
        self.uid = uid
        logger.info("FirestoreSyncService: starting sync for uid \(uid)")
        // Step 1: pull remote → local (one-time on login / device switch)
        pullAll {
            // Step 2: start real-time listeners so remote changes appear instantly
            self.attachListeners()
        }
    }

    /// Call on sign-out to remove all listeners.
    func stopSync() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        uid = ""
        logger.info("FirestoreSyncService: stopped sync")
    }

    // MARK: - Pull (remote → local, runs once at login)

    private func pullAll(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter(); pullProfile           { group.leave() }
        group.enter(); pullReadingProgress   { group.leave() }
        group.enter(); pullWritingProgress   { group.leave() }
        group.enter(); pullWritingSessions   { group.leave() }
        group.enter(); pullPhonicsSessions   { group.leave() }
        group.enter(); pullReadingSessions   { group.leave() }
        group.enter(); pullCheckpointResults { group.leave() }
        group.enter(); pullStreakDates       { group.leave() }

        group.notify(queue: .main) {
            logger.info("FirestoreSyncService: initial pull complete")
            completion()
        }
    }

    // MARK: - Profile push / pull

    func pushProfile(firstName: String, lastName: String, age: Int, gender: String, name: String) {
        guard !uid.isEmpty else { return }
        db.collection("users").document(uid).setData([
            "firstName": firstName,
            "lastName":  lastName,
            "age":       age,
            "gender":    gender,
            "name":      name,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in
            if let error { logger.error("FirestoreSyncService [pushProfile]: \(error)") }
        }
    }

    private func pullProfile(completion: @escaping () -> Void) {
        db.collection("users").document(uid).getDocument { [weak self] snap, error in
            defer { completion() }
            guard let self, let data = snap?.data(), error == nil else { return }
            let child = self.childManager.currentChild
            // Only overwrite local fields if Firestore has non-empty values
            if let fn = data["firstName"] as? String, !fn.isEmpty { child.firstName = fn }
            if let ln = data["lastName"]  as? String, !ln.isEmpty { child.lastName  = ln }
            if let nm = data["name"]      as? String, !nm.isEmpty { child.name      = nm }
            if let gn = data["gender"]    as? String, !gn.isEmpty { child.gender    = gn }
            if let ag = data["age"]       as? Int                 { child.age       = Int16(ag) }
            self.childManager.saveProfileData()
        }
    }

    // MARK: - Reading Progress pull

    private func pullReadingProgress(completion: @escaping () -> Void) {
        col("readingProgress").getDocuments { [weak self] snap, error in
            defer { completion() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullReadingProgress]: \(error)") }
                return
            }
            for doc in docs {
                let data         = doc.data()
                let storyId      = doc.documentID
                let pageIndex    = data["lastPageIndex"] as? Int ?? 0
                let isCompleted  = data["isCompleted"]   as? Bool ?? false
                // Only update local if remote is ahead
                let (localPage, localDone) = self.readingProgressStore.getProgress(for: storyId)
                if pageIndex > localPage || (isCompleted && !localDone) {
                    self.readingProgressStore.saveProgress(
                        storyId: storyId,
                        pageIndex: pageIndex,
                        didComplete: isCompleted
                    )
                }
            }
        }
    }

    // MARK: - Writing Progress pull

    private func pullWritingProgress(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter()
        col("writingUnlocks").getDocuments { [weak self] snap, error in
            defer { group.leave() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullWritingUnlocks]: \(error)") }; return
            }
            for doc in docs {
                let category      = doc.documentID
                let remoteIndex   = doc.data()["unlockedIndex"] as? Int ?? 0
                let localIndex    = self.writingProgressStore.getHighestUnlockedIndex(category: category)
                if remoteIndex > localIndex {
                    // Replay unlock so the store's own logic sets the new high-water mark
                    self.writingProgressStore.unlockNextItem(
                        category: category,
                        currentIndex: remoteIndex - 1
                    )
                }
            }
        }

        group.enter()
        col("writingMistakes").getDocuments { [weak self] snap, error in
            defer { group.leave() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullWritingMistakes]: \(error)") }; return
            }
            for doc in docs {
                // compositeKey format: "letters_3"
                let parts = doc.documentID.split(separator: "_", maxSplits: 1)
                guard parts.count == 2,
                      let idx = Int(parts[1]) else { continue }
                let category = String(parts[0])
                let count    = doc.data()["mistakeCount"] as? Int ?? 0
                self.writingProgressStore.saveMistakeCount(count, index: idx, category: category)
            }
        }

        group.notify(queue: .main, execute: completion)
    }

    // MARK: - Sessions pull (writing / phonics / reading)

    private func pullWritingSessions(completion: @escaping () -> Void) {
        col("writingSessions").getDocuments { [weak self] snap, error in
            defer { completion() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullWritingSessions]: \(error)") }; return
            }
            let existingIds = Set(self.analyticsStore.fetchWritingSessions().map { $0.id })
            for doc in docs {
                guard let session = WritingSessionData(firestoreData: doc.data(), id: doc.documentID),
                      !existingIds.contains(session.id) else { continue }
                self.analyticsStore.appendWritingSession(session, skipSync: true)
            }
        }
    }

    private func pullPhonicsSessions(completion: @escaping () -> Void) {
        col("phonicsSessions").getDocuments { [weak self] snap, error in
            defer { completion() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullPhonicsSessions]: \(error)") }; return
            }
            let existingIds = Set(self.analyticsStore.fetchPhonicsSessions().map { $0.id })
            for doc in docs {
                guard let session = PhonicsSessionData(firestoreData: doc.data(), id: doc.documentID),
                      !existingIds.contains(session.id) else { continue }
                self.analyticsStore.appendPhonicsSession(session, skipSync: true)
            }
        }
    }

    private func pullReadingSessions(completion: @escaping () -> Void) {
        col("readingSessions").getDocuments { [weak self] snap, error in
            defer { completion() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullReadingSessions]: \(error)") }; return
            }
            let existingIds = Set(self.analyticsStore.fetchReadingSessions().map { $0.id })
            for doc in docs {
                guard let session = ReadingSessionData(firestoreData: doc.data(), id: doc.documentID),
                      !existingIds.contains(session.id) else { continue }
                self.analyticsStore.appendReadingSession(session, skipSync: true)
            }
        }
    }

    private func pullCheckpointResults(completion: @escaping () -> Void) {
        col("checkpointResults").getDocuments { [weak self] snap, error in
            defer { completion() }
            guard let self, let docs = snap?.documents, error == nil else {
                if let error { logger.error("FirestoreSyncService [pullCheckpointResults]: \(error)") }; return
            }
            let existing = Set(self.analyticsStore.fetchCheckpointResults().map { $0.id })
            for doc in docs {
                guard let result = ReadingCheckpointResultData(firestoreData: doc.data(), id: doc.documentID),
                      !existing.contains(result.id) else { continue }
                self.analyticsStore.appendCheckpointResult(result, skipSync: true)
            }
        }
    }

    private func pullStreakDates(completion: @escaping () -> Void) {
        col("streak").document("record").getDocument { [weak self] snap, error in
            defer { completion() }
            guard let self, let data = snap?.data(), error == nil else { return }
            let remoteDates = data["visitedDates"] as? [String] ?? []
            StreakStore.shared.mergeRemoteDates(remoteDates)
        }
    }

    // MARK: - Real-time listeners (remote → local, ongoing)

    private func attachListeners() {
        // Reading progress
        let rpListener = col("readingProgress").addSnapshotListener { [weak self] snap, _ in
            guard let self, let changes = snap?.documentChanges else { return }
            for change in changes where change.type == .modified || change.type == .added {
                let doc         = change.document
                let pageIndex   = doc.data()["lastPageIndex"] as? Int ?? 0
                let isCompleted = doc.data()["isCompleted"]   as? Bool ?? false
                self.readingProgressStore.saveProgress(
                    storyId: doc.documentID,
                    pageIndex: pageIndex,
                    didComplete: isCompleted
                )
            }
        }
        listeners.append(rpListener)

        // Streak dates
        let streakListener = col("streak").document("record")
            .addSnapshotListener { [weak self] snap, _ in
                guard let data = snap?.data() else { return }
                let remoteDates = data["visitedDates"] as? [String] ?? []
                StreakStore.shared.mergeRemoteDates(remoteDates)
                NotificationCenter.default.post(name: .streakDidUpdate, object: nil)
            }
        listeners.append(streakListener)
    }

    // MARK: - Push (local → remote)
    // Call these from the store/manager right after writing to Core Data.

    func pushReadingProgress(storyId: String, pageIndex: Int, isCompleted: Bool) {
        guard !uid.isEmpty else { return }
        col("readingProgress").document(storyId).setData([
            "lastPageIndex": pageIndex,
            "isCompleted":   isCompleted,
            "updatedAt":     FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in if let error { logger.error("FirestoreSyncService [pushReadingProgress]: \(error)") } }
    }

    func pushWritingUnlock(category: String, index: Int) {
        guard !uid.isEmpty else { return }
        col("writingUnlocks").document(category).setData([
            "unlockedIndex": index,
            "updatedAt":     FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in if let error { logger.error("FirestoreSyncService [pushWritingUnlock]: \(error)") } }
    }

    func pushWritingMistake(category: String, index: Int, count: Int) {
        guard !uid.isEmpty else { return }
        let key = "\(category)_\(index)"
        col("writingMistakes").document(key).setData([
            "mistakeCount": count,
            "updatedAt":    FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in if let error { logger.error("FirestoreSyncService [pushWritingMistake]: \(error)") } }
    }

    func pushWritingSession(_ session: WritingSessionData) {
        guard !uid.isEmpty else { return }
        col("writingSessions").document(session.id.uuidString)
            .setData(session.firestoreData(), merge: true) { [weak self] error in
                if let error { logger.error("FirestoreSyncService [pushWritingSession]: \(error)") }
            }
    }

    func pushPhonicsSession(_ session: PhonicsSessionData) {
        guard !uid.isEmpty else { return }
        col("phonicsSessions").document(session.id.uuidString)
            .setData(session.firestoreData(), merge: true) { [weak self] error in
                if let error { logger.error("FirestoreSyncService [pushPhonicsSession]: \(error)") }
            }
    }

    func pushReadingSession(_ session: ReadingSessionData) {
        guard !uid.isEmpty else { return }
        col("readingSessions").document(session.id.uuidString)
            .setData(session.firestoreData(), merge: true) { [weak self] error in
                if let error { logger.error("FirestoreSyncService [pushReadingSession]: \(error)") }
            }
    }

    func pushCheckpointResult(_ result: ReadingCheckpointResultData) {
        guard !uid.isEmpty else { return }
        col("checkpointResults").document(result.id.uuidString)
            .setData(result.firestoreData(), merge: true) { [weak self] error in
                if let error { logger.error("FirestoreSyncService [pushCheckpointResult]: \(error)") }
            }
    }

    func pushStreakDates(_ dates: [String]) {
        guard !uid.isEmpty else { return }
        col("streak").document("record").setData([
            "visitedDates": dates,
            "updatedAt":    FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in if let error { logger.error("FirestoreSyncService [pushStreakDates]: \(error)") } }
    }

    // MARK: - Error helper

    private func map(_ error: Error?, context: String) {
        guard let error else { return }
        logger.error("FirestoreSyncService [\(context)]: \(error)")
    }
}

// MARK: - Firestore ↔ Model serialisation extensions

extension WritingSessionData {
    func firestoreData() -> [String: Any] {
        [
            "date":            date.iso8601,
            "childId":         childId,
            "lettersAccuracy": lettersAccuracy,
            "wordsAccuracy":   wordsAccuracy,
            "numbersAccuracy": numbersAccuracy
        ]
    }
    init?(firestoreData d: [String: Any], id: String) {
        guard let uuid = UUID(uuidString: id),
              let dateStr = d["date"] as? String,
              let date    = DateFormatter.iso8601Full.date(from: dateStr)
        else { return nil }
        self.init(
            id:              uuid,
            date:            date,
            childId:         d["childId"]         as? String ?? "",
            lettersAccuracy: d["lettersAccuracy"] as? Int ?? 0,
            wordsAccuracy:   d["wordsAccuracy"]   as? Int ?? 0,
            numbersAccuracy: d["numbersAccuracy"] as? Int ?? 0
        )
    }
}

extension PhonicsSessionData {
    func firestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "date":          date.iso8601,
            "childId":       childId,
            "exerciseType":  exerciseType,
            "correctCount":  correctCount,
            "totalAttempts": totalAttempts,
            "startTime":     startTime.iso8601
        ]
        if let end = endTime { d["endTime"] = end.iso8601 }
        return d
    }
    init?(firestoreData d: [String: Any], id: String) {
        guard let uuid     = UUID(uuidString: id),
              let dateStr  = d["date"]      as? String,
              let date     = DateFormatter.iso8601Full.date(from: dateStr),
              let startStr = d["startTime"] as? String,
              let start    = DateFormatter.iso8601Full.date(from: startStr)
        else { return nil }
        self.init(
            id:            uuid,
            date:          date,
            childId:       d["childId"]       as? String ?? "",
            exerciseType:  d["exerciseType"]  as? String ?? "",
            correctCount:  d["correctCount"]  as? Int ?? 0,
            totalAttempts: d["totalAttempts"] as? Int ?? 0,
            startTime:     start,
            endTime:       (d["endTime"] as? String).flatMap { DateFormatter.iso8601Full.date(from: $0) }
        )
    }
}

extension ReadingSessionData {
    func firestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "storyId":       storyId,
            "childId":       childId,
            "totalDuration": totalDuration,
            "startTime":     startTime.iso8601,
            "levelUnlocked": levelUnlocked
        ]
        if let end = endTime { d["endTime"] = end.iso8601 }
        return d
    }
    init?(firestoreData d: [String: Any], id: String) {
        guard let uuid     = UUID(uuidString: id),
              let startStr = d["startTime"] as? String,
              let start    = DateFormatter.iso8601Full.date(from: startStr)
        else { return nil }
        self.init(
            id:            uuid,
            storyId:       d["storyId"]       as? String ?? "",
            childId:       d["childId"]       as? String ?? "",
            totalDuration: d["totalDuration"] as? TimeInterval ?? 0,
            startTime:     start,
            endTime:       (d["endTime"] as? String).flatMap { DateFormatter.iso8601Full.date(from: $0) },
            levelUnlocked: d["levelUnlocked"] as? Int ?? 0
        )
    }
}

extension ReadingCheckpointResultData {
    func firestoreData() -> [String: Any] {
        [
            "date":           date.iso8601,
            "storyId":        storyId,
            "childId":        childId,
            "accuracy":       accuracy,
            "checkpointText": checkpointText
        ]
    }
    init?(firestoreData d: [String: Any], id: String) {
        guard let uuid    = UUID(uuidString: id),
              let dateStr = d["date"] as? String,
              let date    = DateFormatter.iso8601Full.date(from: dateStr)
        else { return nil }
        self.init(
            id:             uuid,
            date:           date,
            storyId:        d["storyId"]        as? String ?? "",
            childId:        d["childId"]        as? String ?? "",
            accuracy:       d["accuracy"]       as? Double ?? 0,
            checkpointText: d["checkpointText"] as? String ?? ""
        )
    }
}

// MARK: - Date helpers

private extension Date {
    var iso8601: String { DateFormatter.iso8601Full.string(from: self) }
}

private extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Notification

extension Notification.Name {
    static let streakDidUpdate = Notification.Name("streakDidUpdate")
}
