import Foundation

/// Persistent flags + helpers for items the player can buy from the world Store.
enum StoreManager {
    private static let gauntletKey = "gauntletOwned_v1"

    static var gauntletOwned: Bool {
        get { UserDefaults.standard.bool(forKey: gauntletKey) }
        set { UserDefaults.standard.set(newValue, forKey: gauntletKey) }
    }
}
