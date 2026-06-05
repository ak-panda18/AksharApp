import Foundation

extension Notification.Name {
    static let streakStoreNeedsReload = Notification.Name("streakStoreNeedsReload")
    static let phonicsFlowNeedsReload = Notification.Name("phonicsFlowNeedsReload")
    static let skipManagerNeedsReload = Notification.Name("skipManagerNeedsReload")
    static let profileStoreNeedsReload = Notification.Name("profileStoreNeedsReload")
    
    // CoreData remote notifications
    static let coreDataDidSyncFromCloud = Notification.Name("coreDataDidSyncFromCloud")
}

final class iCloudKeyValueStore {
    static let shared = iCloudKeyValueStore()
    
    private init() {}
    
    func startSyncing() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudStoreDidChangeExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    @objc private func iCloudStoreDidChangeExternally(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        else { return }
        
        guard reason == NSUbiquitousKeyValueStoreServerChange || reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }
        
        let defaults = UserDefaults.standard
        let cloud = NSUbiquitousKeyValueStore.default
        
        var shouldPostStreakUpdate = false
        var shouldPostPhonicsUpdate = false
        var shouldPostSkipUpdate = false
        var shouldPostProfileUpdate = false
        
        for key in changedKeys {
            if let val = cloud.object(forKey: key) {
                defaults.set(val, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            
            if key.hasPrefix("streakVisitedDates_") {
                shouldPostStreakUpdate = true
            } else if key.hasPrefix("phonics_flow_state_v2_") || key.contains("cycle_") {
                shouldPostPhonicsUpdate = true
            } else if key.hasPrefix("akshar_available_skips_") || key.hasPrefix("akshar_last_skip_used_date_") {
                shouldPostSkipUpdate = true
            } else if key.hasPrefix("reminder_") || key.hasPrefix("userPIN_") {
                shouldPostProfileUpdate = true
            }
        }
        
        if shouldPostStreakUpdate {
            NotificationCenter.default.post(name: .streakStoreNeedsReload, object: nil)
        }
        if shouldPostPhonicsUpdate {
            NotificationCenter.default.post(name: .phonicsFlowNeedsReload, object: nil)
        }
        if shouldPostSkipUpdate {
            NotificationCenter.default.post(name: .skipManagerNeedsReload, object: nil)
        }
        if shouldPostProfileUpdate {
            NotificationCenter.default.post(name: .profileStoreNeedsReload, object: nil)
        }
    }
    
    // MARK: - Drop-in Methods mimicking UserDefaults API
    
    func set(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func removeObject(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func object(forKey key: String) -> Any? {
        return UserDefaults.standard.object(forKey: key)
    }
    
    func string(forKey key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }
    
    func integer(forKey key: String) -> Int {
        return UserDefaults.standard.integer(forKey: key)
    }
    
    func bool(forKey key: String) -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }
    
    func data(forKey key: String) -> Data? {
        return UserDefaults.standard.data(forKey: key)
    }
    
    func stringArray(forKey key: String) -> [String]? {
        return UserDefaults.standard.stringArray(forKey: key)
    }
    
    func synchronize() -> Bool {
        let uSync = UserDefaults.standard.synchronize()
        let cSync = NSUbiquitousKeyValueStore.default.synchronize()
        return uSync && cSync
    }
}
