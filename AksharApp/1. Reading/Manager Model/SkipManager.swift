import Foundation

final class SkipManager {
    static let shared = SkipManager()
    
    private let maxSkips = 3
    private let replenishInterval: TimeInterval = 2 * 24 * 60 * 60
    private let skipsKey = "akshar_available_skips"
    private let lastUsedKey = "akshar_last_skip_used_date"
    
    private init() {
        if UserDefaults.standard.object(forKey: skipsKey) == nil {
            UserDefaults.standard.set(maxSkips, forKey: skipsKey)
        }
        replenishIfNeeded()
    }
    
    var availableSkips: Int {
        replenishIfNeeded()
        let count = UserDefaults.standard.integer(forKey: skipsKey)
        // If it's 0 but no last used date, it means it's the first run, set to 3
        if count == 0 && UserDefaults.standard.object(forKey: lastUsedKey) == nil {
            UserDefaults.standard.set(maxSkips, forKey: skipsKey)
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
            UserDefaults.standard.set(current - 1, forKey: skipsKey)
            UserDefaults.standard.set(Date(), forKey: lastUsedKey)
        }
    }
    
    private func replenishIfNeeded() {
        guard let lastUsed = UserDefaults.standard.object(forKey: lastUsedKey) as? Date else { return }
        
        if Date().timeIntervalSince(lastUsed) >= replenishInterval {
            UserDefaults.standard.set(maxSkips, forKey: skipsKey)
            UserDefaults.standard.removeObject(forKey: lastUsedKey)
        }
    }
    
    func getReplenishMessage() -> String {
        return "You have \(availableSkips) magic ticket\(availableSkips == 1 ? "" : "s") left! If you use one, your next tickets will be ready in 2 days. Use them wisely!"
    }
}
