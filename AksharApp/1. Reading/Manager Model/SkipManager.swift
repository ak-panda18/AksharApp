import Foundation

final class SkipManager {

    private let maxSkips = 3
    private let replenishInterval: TimeInterval = 2 * 24 * 60 * 60
    private let uid: String

    private var skipsKey:    String { "akshar_available_skips_\(uid)" }
    private var lastUsedKey: String { "akshar_last_skip_used_date_\(uid)" }

    init(uid: String) {
        self.uid = uid
        if iCloudKeyValueStore.shared.object(forKey: skipsKey) == nil {
            iCloudKeyValueStore.shared.set(maxSkips, forKey: skipsKey)
        }
        replenishIfNeeded()
    }

    var availableSkips: Int {
        replenishIfNeeded()
        let count = iCloudKeyValueStore.shared.integer(forKey: skipsKey)
        // If it's 0 but no last used date, it means it's the first run for this user, set to max
        if count == 0 && iCloudKeyValueStore.shared.object(forKey: lastUsedKey) == nil {
            iCloudKeyValueStore.shared.set(maxSkips, forKey: skipsKey)
            return maxSkips
        }
        return count
    }

    func canSkip() -> Bool {
        return availableSkips > 0
    }

    func useSkip() {
        let current = availableSkips
        if current > 0 {
            iCloudKeyValueStore.shared.set(current - 1, forKey: skipsKey)
            iCloudKeyValueStore.shared.set(Date(), forKey: lastUsedKey)
        }
    }

    /// Clears skip data for this user. Call on logout.
    func reset() {
        iCloudKeyValueStore.shared.removeObject(forKey: skipsKey)
        iCloudKeyValueStore.shared.removeObject(forKey: lastUsedKey)
    }

    private func replenishIfNeeded() {
        guard let lastUsed = iCloudKeyValueStore.shared.object(forKey: lastUsedKey) as? Date else { return }

        if Date().timeIntervalSince(lastUsed) >= replenishInterval {
            iCloudKeyValueStore.shared.set(maxSkips, forKey: skipsKey)
            iCloudKeyValueStore.shared.removeObject(forKey: lastUsedKey)
        }
    }

    func getReplenishMessage() -> String {
        return "You have \(availableSkips) magic ticket\(availableSkips == 1 ? "" : "s") left! If you use one, your next tickets will be ready in 2 days. Use them wisely!"
    }
}
