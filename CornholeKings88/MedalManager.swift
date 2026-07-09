import Foundation

/// Bronze/Silver/Gold grading layer over the existing mini-games. Each scene grades its
/// own run at dismiss time from whatever performance data it already has in scope, then
/// reports the tier here. Only the best-ever tier per game is kept — a medal can never
/// be lost by a worse later run.
enum MedalTier: Int, Comparable {
    case none = 0
    case bronze = 1
    case silver = 2
    case gold = 3

    static func < (lhs: MedalTier, rhs: MedalTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none:   return ""
        case .bronze: return "BRONZE"
        case .silver: return "SILVER"
        case .gold:   return "GOLD"
        }
    }

    var emoji: String {
        switch self {
        case .none:   return ""
        case .bronze: return "🥉"
        case .silver: return "🥈"
        case .gold:   return "🥇"
        }
    }
}

/// One entry per medal-eligible mini-game. Kickball is intentionally excluded — it's a
/// pure forgiveness-ramp story beat (CLAUDE.md), and grading it would fight that intent.
enum MiniGameKey: String, CaseIterable {
    case cornhole
    case baseball
    case beachball
    case wellFlinger
    case jousters
    case piranha
    case beehive
    case horseRace
    case mopChase
    case bike
}

final class MedalManager {

    static let shared = MedalManager()
    private init() {}

    private func key(for game: MiniGameKey) -> String { "medal_\(game.rawValue)_v1" }

    func medal(for game: MiniGameKey) -> MedalTier {
        let raw = UserDefaults.standard.integer(forKey: key(for: game))
        return MedalTier(rawValue: raw) ?? .none
    }

    /// Records a run's result. Only upgrades — a worse run never overwrites a better one.
    /// Returns true if this run set a new best (so the caller can show an upgrade beat).
    @discardableResult
    func recordResult(for game: MiniGameKey, tier: MedalTier) -> Bool {
        guard tier > medal(for: game) else { return false }
        UserDefaults.standard.set(tier.rawValue, forKey: key(for: game))
        return true
    }

    var totalMedalScore: Int {
        MiniGameKey.allCases.reduce(0) { $0 + medal(for: $1).rawValue }
    }

    var maxMedalScore: Int { MiniGameKey.allCases.count * MedalTier.gold.rawValue }

    func reset() {
        for game in MiniGameKey.allCases {
            UserDefaults.standard.removeObject(forKey: key(for: game))
        }
    }
}
