import Foundation
import UserNotifications
import FirebaseFirestore
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "ProfileStore")

// MARK: - ProfileStore
// Reminder preferences and last-open date are persisted to Firestore so they
// sync across devices automatically. UserDefaults is kept as a fast local cache
// so reads are instant (no async wait on every screen load); Firestore is the
// source of truth and overwrites the cache on fetch.
//
// Firestore document path:  users/{uid}/profile/settings
// Fields:
//   reminderEnabled : Bool
//   reminderDays    : [Bool]   (7 elements, Mon–Sun)
//   reminderHour    : Int
//   reminderMinute  : Int
//   lastOpenDate    : Timestamp

final class ProfileStore {

    // MARK: - Firestore ref helper
    private func settingsRef(uid: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("profile").document("settings")
    }

    // MARK: - Local cache keys (uid-scoped, never "default")
    private func enabledKey(_ uid: String)  -> String { "reminder_enabled_\(uid)" }
    private func daysKey(_ uid: String)     -> String { "reminder_days_\(uid)" }
    private func hourKey(_ uid: String)     -> String { "reminder_hour_\(uid)" }
    private func minuteKey(_ uid: String)   -> String { "reminder_minute_\(uid)" }
    private func lastOpenKey(_ uid: String) -> String { "last_open_date_\(uid)" }

    // MARK: - Fetch from Firestore (call once on profile screen load)
    /// Pulls the latest settings from Firestore and updates the local cache.
    /// Completion is called on the main thread with the refreshed values so
    /// the UI can update without a second round-trip.
    func fetchSettings(uid: String, completion: ((Bool, [Bool], Int, Int) -> Void)? = nil) {
        settingsRef(uid: uid).getDocument { [weak self] snapshot, error in
            guard let self, let data = snapshot?.data(), error == nil else {
                if let error { logger.error("ProfileStore: fetch failed – \(error)") }
                return
            }
            // Cache locally
            let enabled = data["reminderEnabled"] as? Bool ?? true
            let days    = data["reminderDays"]    as? [Bool] ?? Array(repeating: true, count: 7)
            let hour    = data["reminderHour"]    as? Int    ?? 17
            let minute  = data["reminderMinute"]  as? Int    ?? 0

            iCloudKeyValueStore.shared.set(enabled, forKey: self.enabledKey(uid))
            if let encoded = try? JSONEncoder().encode(days) {
                iCloudKeyValueStore.shared.set(encoded, forKey: self.daysKey(uid))
            }
            iCloudKeyValueStore.shared.set(hour,   forKey: self.hourKey(uid))
            iCloudKeyValueStore.shared.set(minute, forKey: self.minuteKey(uid))

            if let ts = data["lastOpenDate"] as? Timestamp {
                if let encoded = try? JSONEncoder().encode(ts.dateValue()) {
                    iCloudKeyValueStore.shared.set(encoded, forKey: self.lastOpenKey(uid))
                }
            }

            DispatchQueue.main.async {
                completion?(enabled, days, hour, minute)
            }
        }
    }

    // MARK: - Reminder Enabled
    func isReminderEnabled(uid: String) -> Bool {
        guard iCloudKeyValueStore.shared.object(forKey: enabledKey(uid)) != nil else { return true }
        return iCloudKeyValueStore.shared.bool(forKey: enabledKey(uid))
    }

    func setReminderEnabled(_ enabled: Bool, uid: String) {
        iCloudKeyValueStore.shared.set(enabled, forKey: enabledKey(uid))
        settingsRef(uid: uid).setData(["reminderEnabled": enabled], merge: true) { error in
            if let error { logger.error("ProfileStore: setReminderEnabled failed – \(error)") }
        }
    }

    // MARK: - Reminder Days
    func reminderDays(uid: String) -> [Bool] {
        guard let data = iCloudKeyValueStore.shared.data(forKey: daysKey(uid)),
              let days = try? JSONDecoder().decode([Bool].self, from: data),
              days.count == 7
        else { return Array(repeating: true, count: 7) }
        return days
    }

    func setReminderDays(_ days: [Bool], uid: String) {
        if let data = try? JSONEncoder().encode(days) {
            iCloudKeyValueStore.shared.set(data, forKey: daysKey(uid))
        }
        settingsRef(uid: uid).setData(["reminderDays": days], merge: true) { error in
            if let error { logger.error("ProfileStore: setReminderDays failed – \(error)") }
        }
    }

    // MARK: - Reminder Time
    func reminderHour(uid: String) -> Int {
        let v = iCloudKeyValueStore.shared.integer(forKey: hourKey(uid))
        return v == 0 ? 17 : v
    }

    func reminderMinute(uid: String) -> Int {
        iCloudKeyValueStore.shared.integer(forKey: minuteKey(uid))
    }

    func setReminderTime(hour: Int, minute: Int, uid: String) {
        iCloudKeyValueStore.shared.set(hour,   forKey: hourKey(uid))
        iCloudKeyValueStore.shared.set(minute, forKey: minuteKey(uid))
        settingsRef(uid: uid).setData(
            ["reminderHour": hour, "reminderMinute": minute],
            merge: true
        ) { error in
            if let error { logger.error("ProfileStore: setReminderTime failed – \(error)") }
        }
    }

    // MARK: - Last Open Date
    func recordAppOpen(uid: String) {
        let today = Calendar.current.startOfDay(for: Date())
        if let data = try? JSONEncoder().encode(today) {
            iCloudKeyValueStore.shared.set(data, forKey: lastOpenKey(uid))
        }
        settingsRef(uid: uid).setData(
            ["lastOpenDate": Timestamp(date: today)],
            merge: true
        ) { error in
            if let error { logger.error("ProfileStore: recordAppOpen failed – \(error)") }
        }
    }

    func wasAppOpenedToday(uid: String) -> Bool {
        guard let data = iCloudKeyValueStore.shared.data(forKey: lastOpenKey(uid)),
              let date = try? JSONDecoder().decode(Date.self, from: data)
        else { return false }
        return Calendar.current.isDateInToday(date)
    }

    // MARK: - Schedule / Cancel
    func scheduleNotifications(uid: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self.reschedule(uid: uid, center: center) }
        }
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allIDs())
    }

    // MARK: - Private
    private func allIDs() -> [String] { (0..<7).map { "akshar_day_\($0)" } }

    private func reschedule(uid: String, center: UNUserNotificationCenter) {
        center.removePendingNotificationRequests(withIdentifiers: allIDs())
        guard isReminderEnabled(uid: uid) else { return }

        let days       = reminderDays(uid: uid)
        let hour       = reminderHour(uid: uid)
        let minute     = reminderMinute(uid: uid)
        let weekdayMap = [2, 3, 4, 5, 6, 7, 1]

        for (i, isOn) in days.enumerated() {
            guard isOn else { continue }

            let content      = UNMutableNotificationContent()
            content.title    = "Time to learn!"
            content.body     = "Akshar is waiting for you. Keep your streak going!"
            content.sound    = .default
            content.userInfo = ["uid": uid]

            var dc        = DateComponents()
            dc.hour       = hour
            dc.minute     = minute
            dc.weekday    = weekdayMap[i]

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let request = UNNotificationRequest(
                identifier: "akshar_day_\(i)",
                content:    content,
                trigger:    trigger
            )
            center.add(request) { error in
                if let error {
                    logger.error("ProfileStore: failed to schedule notification day \(i) – \(error)")
                }
            }
        }
    }
}
