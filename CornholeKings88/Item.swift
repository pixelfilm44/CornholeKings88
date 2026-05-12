import SpriteKit

enum ItemType: String, CaseIterable {
    case coin
    case bag
    case star
    /// Won from BeeHive Battle. In cornhole these bags stick to the board —
    /// immune to wind and to being knocked by the bot's bags.
    case honeyBag

    var color: SKColor {
        switch self {
        case .coin:     return SKColor(red: 0.90, green: 0.72, blue: 0.15, alpha: 1.0)
        case .bag:      return SKColor(red: 0.85, green: 0.38, blue: 0.10, alpha: 1.0)
        case .star:     return SKColor(red: 0.95, green: 0.95, blue: 0.25, alpha: 1.0)
        case .honeyBag: return SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0)
        }
    }

    var displayName: String {
        switch self {
        case .coin:     return "COIN"
        case .bag:      return "BAG"
        case .star:     return "STAR"
        case .honeyBag: return "HONEY BAG"
        }
    }

    var hudSymbol: String {
        switch self {
        case .coin:     return "●"
        case .bag:      return "◆"
        case .star:     return "★"
        case .honeyBag: return "H"
        }
    }
}
