import Foundation

final class CornholeStatsManager {

    static let shared = CornholeStatsManager()
    private init() {}

    private enum Key {
        static let wins          = "stats_cornhole_wins"
        static let losses        = "stats_cornhole_losses"
        static let cornholes     = "stats_cornhole_cornholes"
        static let defeatedTom   = "stats_defeated_tom_v1"
        static let defeatedJenny = "stats_defeated_jenny_v1"
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

    var currentRank: String { "Rookie" }

    func recordWin()      { wins += 1 }
    func recordLoss()     { losses += 1 }
    func recordCornhole() { cornholes += 1 }
    func recordDefeatedTom()   { defeatedTom   = true }
    func recordDefeatedJenny() { defeatedJenny = true }

    func reset() {
        wins = 0
        losses = 0
        cornholes = 0
        defeatedTom   = false
        defeatedJenny = false
    }
}
