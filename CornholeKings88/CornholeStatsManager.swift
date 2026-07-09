import Foundation

final class CornholeStatsManager {

    static let shared = CornholeStatsManager()
    private init() {}

    private enum Key {
        static let wins                = "stats_cornhole_wins"
        static let losses              = "stats_cornhole_losses"
        static let cornholes           = "stats_cornhole_cornholes"
        static let defeatedTom         = "stats_defeated_tom_v1"
        static let defeatedJenny       = "stats_defeated_jenny_v1"
        static let defeatedJenBaseball = "stats_defeated_jen_baseball_v1"
        static let defeatedTomBaseball = "stats_defeated_tom_baseball_v1"
    }

    var wins: Int {
        get { UserDefaults.standard.integer(forKey: Key.wins) }
        set { UserDefaults.standard.set(newValue, forKey: Key.wins) }
    }

    var losses: Int {
        get { UserDefaults.standard.integer(forKey: Key.losses) }
        set { UserDefaults.standard.set(newValue, forKey: Key.losses) }
    }

    var cornholes: Int {
        get { UserDefaults.standard.integer(forKey: Key.cornholes) }
        set { UserDefaults.standard.set(newValue, forKey: Key.cornholes) }
    }

    var defeatedTom: Bool {
        get { UserDefaults.standard.bool(forKey: Key.defeatedTom) }
        set { UserDefaults.standard.set(newValue, forKey: Key.defeatedTom) }
    }

    var defeatedJenny: Bool {
        get { UserDefaults.standard.bool(forKey: Key.defeatedJenny) }
        set { UserDefaults.standard.set(newValue, forKey: Key.defeatedJenny) }
    }

    var baseballUnlocked: Bool { defeatedTom && defeatedJenny }

    var defeatedJenBaseball: Bool {
        get { UserDefaults.standard.bool(forKey: Key.defeatedJenBaseball) }
        set { UserDefaults.standard.set(newValue, forKey: Key.defeatedJenBaseball) }
    }

    var defeatedTomBaseball: Bool {
        get { UserDefaults.standard.bool(forKey: Key.defeatedTomBaseball) }
        set { UserDefaults.standard.set(newValue, forKey: Key.defeatedTomBaseball) }
    }

    var joustersUnlocked: Bool { defeatedJenBaseball && defeatedTomBaseball }

    /// Derived from medal count across all graded mini-games (MedalManager), not from
    /// win/loss counters — a "rank" should reflect breadth of mastery, not raw volume.
    var currentRank: String {
        let score = MedalManager.shared.totalMedalScore
        switch score {
        case 0:      return "Rookie"
        case 1...9:  return "Contender"
        case 10...19: return "Champion"
        default:     return "Cornhole King"
        }
    }

    func recordWin()      { wins += 1 }
    func recordLoss()     { losses += 1 }
    func recordCornhole() { cornholes += 1 }
    func recordDefeatedTom()   { defeatedTom   = true }
    func recordDefeatedJenny() { defeatedJenny = true }

    func reset() {
        wins = 0
        losses = 0
        cornholes = 0
        defeatedTom         = false
        defeatedJenny       = false
        defeatedJenBaseball = false
        defeatedTomBaseball = false
        MedalManager.shared.reset()
    }
}
