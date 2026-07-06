import CoreGraphics
import Foundation

/// Player-tunable difficulty knobs for the two named baseball opponents, Tim and Jen.
///
/// Each knob is stored as an integer percentage (default 100%) and exposed to the
/// game as a multiplier. `CornholeBaseballScene` reads these for whichever named
/// opponent is active; the generic BOT is never tuned (always 1.0).
///
/// Persisted to `UserDefaults` so changes survive relaunch.
final class BaseballAISettings {

    static let shared = BaseballAISettings()
    private init() {}

    enum Character: String, CaseIterable {
        case tom, jen
        var displayName: String { self == .tom ? "TIM" : "JEN" }
    }

    /// The four performance dials the player can adjust.
    enum Stat: String, CaseIterable {
        case hit    // likelihood to make contact at the plate
        case power  // how hard the ball is hit
        case pitch  // pitch speed
        case run    // fielder running speed chasing the ball

        var label: String {
            switch self {
            case .hit:   return "HIT %"
            case .power: return "POWER"
            case .pitch: return "PITCH SPD"
            case .run:   return "RUN SPD"
            }
        }
    }

    // Percentage bounds. 20% floor keeps speed-based dials from freezing a fielder/pitch.
    let minPercent = 20
    let maxPercent = 200
    let step       = 10
    let defaultPercent = 100

    private let defaults = UserDefaults.standard
    private func key(_ c: Character, _ s: Stat) -> String { "baseballAI_\(c.rawValue)_\(s.rawValue)_v1" }

    /// Current percentage for a dial (defaults to 100 when never set).
    func percent(_ c: Character, _ s: Stat) -> Int {
        let k = key(c, s)
        guard defaults.object(forKey: k) != nil else { return defaultPercent }
        return defaults.integer(forKey: k)
    }

    /// Multiplier form (percentage / 100) used directly by the game.
    func multiplier(_ c: Character, _ s: Stat) -> CGFloat {
        CGFloat(percent(c, s)) / 100.0
    }

    /// Nudges a dial by `delta` (typically ±step), clamped to the bounds, and persists it.
    /// Returns the new percentage.
    @discardableResult
    func adjust(_ c: Character, _ s: Stat, by delta: Int) -> Int {
        let next = min(maxPercent, max(minPercent, percent(c, s) + delta))
        defaults.set(next, forKey: key(c, s))
        return next
    }

    /// Restores every dial for both characters back to 100%.
    func reset() {
        for c in Character.allCases {
            for s in Stat.allCases {
                defaults.removeObject(forKey: key(c, s))
            }
        }
    }
}
