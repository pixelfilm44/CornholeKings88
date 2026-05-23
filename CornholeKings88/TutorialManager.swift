import Foundation

/// Tracks which mini-game tutorials the player has seen.
/// Each mini-game uses a unique key (see static constants) to record
/// the first-play tutorial completion. Players can replay via in-game
/// HELP buttons even after the flag is set.
final class TutorialManager {
    static let shared = TutorialManager()
    private init() {}

    // Tutorial keys — one per mini-game.
    static let bike      = "tutorial.bike.v1"
    static let cornhole  = "tutorial.cornhole.v1"
    static let baseball  = "tutorial.baseball.v1"
    static let beehive   = "tutorial.beehive.v1"
    static let beachball = "tutorial.beachball.v1"
    static let piranha   = "tutorial.piranha.v1"
    static let jousters  = "tutorial.jousters.v1"

    func hasSeen(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    func markSeen(_ key: String) {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Clears the seen-flag — used by debug menus or "Replay tutorial"
    /// flows that should re-trigger the auto-show next launch.
    func reset(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
