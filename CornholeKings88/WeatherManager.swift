import SpriteKit

/// Singleton that owns the world's day/night clock and the current weather
/// scenario. Persists across scene transitions so that returning from a
/// mini-game picks up where the world left off.
final class WeatherManager {
    static let shared = WeatherManager()

    enum Weather {
        case clear
        case rain
        case storm
    }

    /// Real-time seconds for one full day cycle (dawn → dusk → night → dawn).
    let dayCycleSeconds: TimeInterval = 240

    /// Normalized time of day in [0, 1).
    /// 0.00 = dawn (orange), 0.25 = midday (yellow/bright), 0.50 = sunset (blue),
    /// 0.75 = midnight (black), wraps back to dawn.
    private(set) var timeOfDay: CGFloat = 0.05

    private(set) var weather: Weather = .clear

    /// True during the night portion of the day cycle. The world scene uses
    /// this to suppress dog/bully spawns and bring out wolves.
    /// Window is tuned so real-time night lasts ~60s of the 240s cycle.
    var isNight: Bool { timeOfDay >= 0.70 && timeOfDay < 0.95 }

    /// Real-time seconds before the next weather roll.
    private var nextWeatherRoll: TimeInterval = 25

    private init() {}

    /// Advance the day clock and possibly transition weather.
    /// Called from the world scene's `update(_:)`.
    func tick(dt: TimeInterval) {
        guard dt > 0, dt < 1 else { return }
        timeOfDay = CGFloat((Double(timeOfDay) + dt / dayCycleSeconds)
            .truncatingRemainder(dividingBy: 1.0))

        nextWeatherRoll -= dt
        if nextWeatherRoll <= 0 {
            rollWeather()
            nextWeatherRoll = TimeInterval.random(in: 45...90)
        }
    }

    private func rollWeather() {
        // Strong bias toward clear; rain is uncommon; storms are rare.
        let r = Int.random(in: 0..<100)
        switch weather {
        case .clear:
            if r < 5 { weather = .rain }
            else if r < 7 { weather = .storm }
        case .rain:
            if r < 80 { weather = .clear }
            else if r < 85 { weather = .storm }
        case .storm:
            if r < 85 { weather = .clear }
            else if r < 95 { weather = .rain }
        }
    }

    /// Returns the world tint color and alpha for the current `timeOfDay`.
    /// Blends between 4 keyframes: dawn (orange), midday (clear yellow),
    /// sunset (blue), midnight (black).
    func currentSkyTint() -> (color: SKColor, alpha: CGFloat) {
        struct Frame { let t: CGFloat; let color: SKColor; let alpha: CGFloat }
        let frames: [Frame] = [
            Frame(t: 0.00, color: SKColor(red: 1.00, green: 0.50, blue: 0.20, alpha: 1), alpha: 0.35), // dawn orange
            Frame(t: 0.25, color: SKColor(red: 1.00, green: 0.95, blue: 0.55, alpha: 1), alpha: 0.10), // midday bright
            Frame(t: 0.50, color: SKColor(red: 0.20, green: 0.30, blue: 0.65, alpha: 1), alpha: 0.40), // sunset blue
            Frame(t: 0.75, color: SKColor(red: 0.00, green: 0.00, blue: 0.05, alpha: 1), alpha: 0.0),  // midnight — GameScene's night overlay handles the dark
            Frame(t: 1.00, color: SKColor(red: 1.00, green: 0.50, blue: 0.20, alpha: 1), alpha: 0.35), // wrap to dawn
        ]
        let t = timeOfDay
        for i in 0..<(frames.count - 1) {
            let a = frames[i], b = frames[i + 1]
            if t >= a.t && t <= b.t {
                let f = (t - a.t) / (b.t - a.t)
                return (lerpColor(a.color, b.color, f), a.alpha + (b.alpha - a.alpha) * f)
            }
        }
        return (frames[0].color, frames[0].alpha)
    }

    private func lerpColor(_ a: SKColor, _ b: SKColor, _ t: CGFloat) -> SKColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return SKColor(red:   ar + (br - ar) * t,
                       green: ag + (bg - ag) * t,
                       blue:  ab + (bb - ab) * t,
                       alpha: aa + (ba - aa) * t)
    }
}
