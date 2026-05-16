import SpriteKit

enum ItemType: String, CaseIterable {
    case coin
    case bag
    case star
    /// Won from BeeHive Battle. In cornhole these bags stick to the board —
    /// immune to wind and to being knocked by the bot's bags.
    case honeyBag
    /// Won by beating Billy the Bully. Destroys all opponent bags on the board
    /// when it lands on the surface; destroys opponent hole bags when scored.
    case bombBag
    /// Won by beating the Tree Spirit. On board collision destroys the opponent bag hit;
    /// when scored in the hole, destroys all opponent bags already in the hole this round.
    case magicBag

    var color: SKColor {
        switch self {
        case .coin:     return SKColor(red: 0.90, green: 0.72, blue: 0.15, alpha: 1.0)
        case .bag:      return SKColor(red: 0.85, green: 0.38, blue: 0.10, alpha: 1.0)
        case .star:     return SKColor(red: 0.95, green: 0.95, blue: 0.25, alpha: 1.0)
        case .honeyBag: return SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0)
        case .bombBag:  return SKColor(red: 0.08, green: 0.06, blue: 0.06, alpha: 1.0)
        case .magicBag: return SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1.0)
        }
    }

    var displayName: String {
        switch self {
        case .coin:     return "COIN"
        case .bag:      return "BAG"
        case .star:     return "STAR"
        case .honeyBag: return "HONEY BAG"
        case .bombBag:  return "BOMB BAG"
        case .magicBag: return "MAGIC BAG"
        }
    }

    var hudSymbol: String {
        switch self {
        case .coin:     return "●"
        case .bag:      return "◆"
        case .star:     return "★"
        case .honeyBag: return "H"
        case .bombBag:  return "B"
        case .magicBag: return "M"
        }
    }
}
