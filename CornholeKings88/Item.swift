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
    /// Burns all bags on the board this round when it lands on the surface (thrower scores 1 pt,
    /// all other board bags destroyed); when scored in the hole, burns all other cornholes this round.
    case fireBag
    /// Won by winning the Beanbag Bike Race. Scores 2 pts on the board, 6 pts in the hole.
    /// Fully immune to all magic bag effects — cannot be destroyed or have hole points removed.
    case goldenBag
    /// Found in world chests. Place from inventory to distract a chasing dog for a few seconds.
    case dogBiscuit

    var color: SKColor {
        switch self {
        case .coin:     return SKColor(red: 0.90, green: 0.72, blue: 0.15, alpha: 1.0)
        case .bag:      return SKColor(red: 0.85, green: 0.38, blue: 0.10, alpha: 1.0)
        case .star:     return SKColor(red: 0.95, green: 0.95, blue: 0.25, alpha: 1.0)
        case .honeyBag: return SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0)
        case .bombBag:  return SKColor(red: 0.08, green: 0.06, blue: 0.06, alpha: 1.0)
        case .magicBag: return SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1.0)
        case .fireBag:  return SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1.0)
        case .goldenBag:  return SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1.0)
        case .dogBiscuit: return SKColor(red: 0.80, green: 0.62, blue: 0.36, alpha: 1.0)
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
        case .fireBag:   return "FIRE BAG"
        case .goldenBag:  return "GOLDEN BAG"
        case .dogBiscuit: return "DOG BISCUIT"
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
        case .fireBag:   return "F"
        case .goldenBag:  return "★"
        case .dogBiscuit: return "D"
        }
    }
}
