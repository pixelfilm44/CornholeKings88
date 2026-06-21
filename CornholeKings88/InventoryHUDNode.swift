import SpriteKit

/// Horizontal strip of item slots shown in the bottom chrome, above the D-pad.
/// Each slot displays a coloured icon + "×N" count for every collected item type.
final class InventoryHUDNode: SKNode {

    private let slotWidth:   CGFloat = 56
    private let slotHeight:  CGFloat = 22
    private let slotSpacing: CGFloat = 8
    private let maxVisible   = 6

    private var slotNodes: [SKNode] = []

    // MARK: - Public

    func refresh(counts: [ItemType: Int]) {
        slotNodes.forEach { $0.removeFromParent() }
        slotNodes.removeAll()

        let shown: [ItemType] = [.coin, .bag]
        let visible: [(ItemType, Int)] = shown.map { ($0, counts[$0] ?? 0) }

        let totalW = CGFloat(visible.count) * slotWidth
                   + CGFloat(visible.count - 1) * slotSpacing
        var x = -totalW / 2 + slotWidth / 2

        for (type, count) in visible {
            let slot = makeSlot(type: type, count: count)
            slot.position = CGPoint(x: x, y: 0)
            addChild(slot)
            slotNodes.append(slot)
            x += slotWidth + slotSpacing
        }
    }

    // MARK: - Slot construction

    private func makeSlot(type: ItemType, count: Int) -> SKNode {
        let node = SKNode()
        node.name = "slot_\(type.rawValue)"

        // Dark pill background
        let bg = SKSpriteNode(color: SKColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 0.82),
                              size: CGSize(width: slotWidth, height: slotHeight))
        bg.zPosition = 0
        node.addChild(bg)

        // Icon — circle for coin, square for bag
        let iconPos = CGPoint(x: -slotWidth / 2 + 11, y: 0)
        let icon: SKNode
        if type == .coin {
            let coin = SKShapeNode(circleOfRadius: 6)
            coin.fillColor = type.color
            coin.strokeColor = SKColor(red: 0.55, green: 0.40, blue: 0.05, alpha: 1.0)
            coin.lineWidth = 1
            icon = coin
        } else {
            icon = SKSpriteNode(color: type.color, size: CGSize(width: 12, height: 12))
        }
        icon.position = iconPos
        icon.zPosition = 1
        node.addChild(icon)

        // Highlight pixel on icon
        let hl = SKSpriteNode(color: SKColor(white: 1.0, alpha: 0.5),
                              size: CGSize(width: 4, height: 4))
        hl.position = CGPoint(x: iconPos.x - 4, y: iconPos.y + 4)
        hl.zPosition = 2
        node.addChild(hl)

        let label = SKLabelNode(fontNamed: "PressStart2P-Regular")
        label.text = "×\(count)"
        label.fontSize = 8
        label.fontColor = SKColor(white: 0.90, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: iconPos.x + 10, y: 0)
        label.zPosition = 1
        node.addChild(label)

        return node
    }
}
