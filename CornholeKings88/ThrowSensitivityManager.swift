import Foundation
import CoreGraphics

/// Player-tunable sensitivity for flick-throw mini-games. A higher multiplier
/// means a gentler flick still produces a full-power throw (Easy mode); a
/// lower multiplier means the player has to swipe harder/faster (Hard mode).
///
/// The multiplier is applied at calibration time in each scene that uses
/// swipe-to-throw — see `CornholeMiniGameScene`, `BeachBallCornholeScene`,
/// and `HorseRaceCornholeScene` (multiplies `powerScale`), plus
/// `BridgePiranhaScene` (scales the minimum upward-swipe threshold).
final class ThrowSensitivityManager {
    static let shared = ThrowSensitivityManager()
    private init() {}

    private let key = "throwSensitivity_v1"

    /// Persisted multiplier in [minValue, maxValue]. Default 1.0 = current feel.
    static let minValue: CGFloat = 0.6   // Hard — needs a harder flick
    static let maxValue: CGFloat = 1.5   // Easy — gentle flicks count
    static let defaultValue: CGFloat = 1.0

    var multiplier: CGFloat {
        get {
            let stored = UserDefaults.standard.object(forKey: key) as? Double
            let v = CGFloat(stored ?? Double(Self.defaultValue))
            return max(Self.minValue, min(Self.maxValue, v))
        }
        set {
            let v = max(Self.minValue, min(Self.maxValue, newValue))
            UserDefaults.standard.set(Double(v), forKey: key)
        }
    }

    /// 0.0 (Hard) ... 1.0 (Easy) — the slider position derived from multiplier.
    var normalized: CGFloat {
        get { (multiplier - Self.minValue) / (Self.maxValue - Self.minValue) }
        set { multiplier = Self.minValue + max(0, min(1, newValue)) * (Self.maxValue - Self.minValue) }
    }

    /// "EASY" / "NORMAL" / "HARD" tag for the current multiplier.
    var label: String {
        let n = normalized
        if n < 0.34 { return "HARD" }
        if n < 0.67 { return "NORMAL" }
        return "EASY"
    }
}
