import Foundation

/// Central store for cross-session world-progression unlocks that are *earned* by
/// winning a mini-game from the world map / story mode (never from the mini-game menu).
///
/// Item-driven gates: possessing the earned reward is what unlocks the next activity.
/// Most unlocks already live in `CornholeStatsManager` (baseball, jousters) or as
/// one-off `UserDefaults` keys (bridge, golden lance). This manager owns the flags that
/// previously had no home — chiefly the world-map unlock gate behind the BeanBag Bike race.
final class ProgressManager {
    static let shared = ProgressManager()
    private init() {}

    private let defaults = UserDefaults.standard

    // MARK: - World map unlock (BeanBag Bike victory)

    private let worldUnlockedKey = "worldUnlocked_v1"

    /// True once the player has won the BeanBag Bike race at least once. The backyard
    /// world map is locked until this flips.
    var worldUnlocked: Bool {
        get { defaults.bool(forKey: worldUnlockedKey) }
        set { defaults.set(newValue, forKey: worldUnlockedKey) }
    }

    // MARK: - Earned-item unlock flags (mirror existing reward sources)

    /// Earned a baseball — beat both Tom and Jenny at cornhole. Mirrors
    /// `CornholeStatsManager.baseballUnlocked`; enables the baseball mini-game.
    var hasBaseball: Bool { CornholeStatsManager.shared.baseballUnlocked }

    /// Earned a bat — beat both Tom and Jenny at baseball. Mirrors
    /// `CornholeStatsManager.joustersUnlocked`; enables Suburban Jousters.
    var hasBat: Bool { CornholeStatsManager.shared.joustersUnlocked }

    /// Earned the bridge — beat the Piranha Bridge mini-game.
    var hasBridge: Bool { defaults.bool(forKey: "bridgeUnlocked_v1") }

    /// Earned the Golden Lance — won Suburban Jousters.
    var hasLance: Bool { defaults.bool(forKey: "goldenLanceEarned_v1") }

    func reset() {
        defaults.removeObject(forKey: worldUnlockedKey)
    }
}
