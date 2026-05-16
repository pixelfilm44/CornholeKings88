import Foundation

/// Singleton that owns the player's heart count across the entire game.
/// All scenes read and write through this — it persists to UserDefaults so
/// hearts carry over between any mini-game and the world map within a session.
/// On cold app launch (LoadingScene) the count is reset to maxHearts.
final class HeartsManager {
    static let shared = HeartsManager()
    private static let key = "universalHearts_v1"

    let maxHearts: Int = 5
    private(set) var currentHearts: Int

    /// Fired on the main thread whenever `currentHearts` changes.
    /// GameScene subscribes to keep its HUD in sync while the bike race modal is up.
    var onChanged: (() -> Void)?

    private init() {
        let saved = UserDefaults.standard.integer(forKey: Self.key)
        currentHearts = saved > 0 ? saved : 5
    }

    func lose() {
        guard currentHearts > 0 else { return }
        currentHearts -= 1
        save(); onChanged?()
    }

    func gain() {
        guard currentHearts < maxHearts else { return }
        currentHearts += 1
        save(); onChanged?()
    }

    /// Restores to full — called on cold app launch and on world-map game over.
    func refill() {
        currentHearts = maxHearts
        save(); onChanged?()
    }

    /// Sets an exact count (clamped to 0…maxHearts).
    func set(_ count: Int) {
        currentHearts = max(0, min(maxHearts, count))
        save(); onChanged?()
    }

    private func save() {
        UserDefaults.standard.set(currentHearts, forKey: Self.key)
    }
}
