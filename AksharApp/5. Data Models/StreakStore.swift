// StreakStore.swift
//
// Single source of truth for streak state.
// - Persists visited dates to UserDefaults under a UID-scoped key (safe for multi-account)
// - Merges with Firestore remote dates on login / listener fire
// - Exposes the week grid (Mon–Sun) for the UI
// - Resets automatically: the 7-day window always starts on the current Monday

import Foundation

final class StreakStore {

    // MARK: - Singleton
    // Streak data is per-user; configure(uid:) must be called after resolveChild
    // so the store reads/writes from the correct UID-scoped UserDefaults key.
    static let shared = StreakStore()
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudReloadNotification),
            name: .streakStoreNeedsReload,
            object: nil
        )
    }

    @objc private func iCloudReloadNotification() {
        loadFromDefaults()
        NotificationCenter.default.post(name: .streakDidUpdate, object: nil)
    }

    // MARK: - Storage (UID-scoped)
    private var currentUID: String = ""
    private var defaultsKey: String { "streakVisitedDates_\(currentUID)" }

    /// All dates the user has opened the app, kept as a Set for O(1) lookup.
    private(set) var visitedDates: Set<String> = []

    // MARK: - Configuration

    /// Must be called after resolveChild(uid:) so the store reads from the correct key.
    func configure(uid: String) {
        guard uid != currentUID else { return }
        currentUID = uid
        loadFromDefaults()
    }

    // MARK: - Reset (call on logout)

    /// Clears in-memory state and removes the current UID-scoped UserDefaults entry.
    func reset() {
        if !currentUID.isEmpty {
            iCloudKeyValueStore.shared.removeObject(forKey: defaultsKey)
        }
        visitedDates = []
        currentUID   = ""
    }

    // MARK: - Record today

    /// Call once per app-open (from SceneDelegate.sceneDidBecomeActive).
    /// Returns true if today was newly recorded.
    @discardableResult
    func recordToday() -> Bool {
        guard !currentUID.isEmpty else { return false }
        let today = dateKey(for: Date())
        guard !visitedDates.contains(today) else { return false }
        visitedDates.insert(today)
        persist()
        return true
    }

    // MARK: - Merge with remote

    /// Merges Firestore-sourced dates into the local set (union — never removes local dates).
    func mergeRemoteDates(_ remoteDates: [String]) {
        guard !currentUID.isEmpty else { return }
        let before = visitedDates.count
        visitedDates.formUnion(remoteDates)
        if visitedDates.count != before { persist() }
    }

    /// All dates as sorted array — use this when pushing to Firestore.
    var allDatesForSync: [String] { visitedDates.sorted() }

    // MARK: - Week grid

    struct DayState {
        let date: Date
        let dateKey: String          // yyyy-MM-dd
        let weekdayLabel: String     // "M", "T", "W", "T", "F", "S", "S"
        let status: Status
        let streakNumber: Int        // consecutive streak count ending on this day (0 if missed/future)

        enum Status {
            case today       // current day → blue
            case visited     // past day where app was opened → green
            case missed      // past day where app was NOT opened → grey
            case future      // days after today → empty/dim
        }
    }

    /// Returns the 7 DayState entries for the current Mon–Sun week.
    func currentWeekGrid() -> [DayState] {
        let calendar = Calendar.current
        let today    = Date()
        let monday   = startOfCurrentWeek(calendar: calendar, from: today)

        return (0..<7).map { offset in
            let date    = calendar.date(byAdding: .day, value: offset, to: monday)!
            let key     = dateKey(for: date)
            let isToday = calendar.isDateInToday(date)
            let isPast  = date < calendar.startOfDay(for: today) && !isToday
            let isFuture = !isToday && !isPast

            let status: DayState.Status
            if isToday {
                status = .today
            } else if isFuture {
                status = .future
            } else if visitedDates.contains(key) {
                status = .visited
            } else {
                status = .missed
            }

            // Streak number = how many consecutive days (including this one)
            // going backwards have been visited.
            let streak = status == .missed || status == .future
                ? 0
                : consecutiveStreak(endingOn: date, calendar: calendar)

            let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            return DayState(
                date:          date,
                dateKey:       key,
                weekdayLabel:  weekdayLabels[offset],
                status:        status,
                streakNumber:  streak
            )
        }
    }

    /// Current streak length: consecutive days up to and including today.
    var currentStreakLength: Int {
        consecutiveStreak(endingOn: Date(), calendar: Calendar.current)
    }

    // MARK: - Private helpers

    private func startOfCurrentWeek(calendar: Calendar, from date: Date) -> Date {
        // ISO week starts on Monday (weekday 2 in Gregorian)
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private func consecutiveStreak(endingOn date: Date, calendar: Calendar) -> Int {
        var count   = 0
        var current = calendar.startOfDay(for: date)
        while true {
            let key = dateKey(for: current)
            // today counts even if not yet recorded (the badge should show optimistically)
            let counts = visitedDates.contains(key) || calendar.isDateInToday(current)
            guard counts else { break }
            count  += 1
            current = calendar.date(byAdding: .day, value: -1, to: current)!
        }
        return count
    }

    private func dateKey(for date: Date) -> String {
        Self.keyFormatter.string(from: date)
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func persist() {
        iCloudKeyValueStore.shared.set(Array(visitedDates), forKey: defaultsKey)
    }

    private func loadFromDefaults() {
        let stored = iCloudKeyValueStore.shared.stringArray(forKey: defaultsKey) ?? []
        visitedDates = Set(stored)
    }
}
