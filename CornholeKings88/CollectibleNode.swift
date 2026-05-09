import SpriteKit

final class CollectibleNode: SKNode {

    static let collectibleBit: UInt32 = 0x1 << 2

    let itemType: ItemType

    // Set to true the moment collect() is called so contact can't fire twice
    // while the fade-out animation is still running.
    private(set) var isBeingCollected = false

    init(type: ItemType) {
        self.itemType = type
        super.init()
        buildVisual()
        buildPhysics()
        startBob()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Visual

    private func buildVisual() {
        // 8×8 pixel-art tile in the item's colour
        let body = SKSpriteNode(color: itemType.color, size: CGSize(width: 8, height: 8))
        body.zPosition = 1
        addChild(body)

        // Subtle highlight pixel (top-left corner, 2×2)
        let highlight = SKSpriteNode(color: SKColor(white: 1.0, alpha: 0.55),
                                     size: CGSize(width: 2, height: 2))
        highlight.position = CGPoint(x: -3, y: 3)
        highlight.zPosition = 2
        addChild(highlight)

        // Faint glow ring so the item reads against any tile colour
        let ring = SKShapeNode(circleOfRadius: 7)
        ring.strokeColor = itemType.color.withAlphaComponent(0.35)
        ring.fillColor = .clear
        ring.lineWidth = 1.5
        ring.zPosition = 0
        addChild(ring)
    }

    // MARK: - Physics (sensor — contact only, no collision response)

    private func buildPhysics() {
        let body = SKPhysicsBody(circleOfRadius: 8)
        body.isDynamic = false
        body.categoryBitMask = CollectibleNode.collectibleBit
        body.collisionBitMask = 0
        body.contactTestBitMask = PlayerNode.categoryBit
        physicsBody = body
    }

    // MARK: - Animation

    private func startBob() {
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 2, duration: 0.55),
            .moveBy(x: 0, y: -2, duration: 0.55),
        ])
        run(.repeatForever(bob), withKey: "bob")
    }

    // MARK: - Collection

    func collect() {
        guard !isBeingCollected else { return }
        isBeingCollected = true
        removeAction(forKey: "bob")
        physicsBody = nil   // prevent any further contacts

        let pop = SKAction.sequence([
            .scale(to: 1.6, duration: 0.07),
            .group([
                .scale(to: 0.0, duration: 0.14),
                .fadeOut(withDuration: 0.14),
            ]),
            .removeFromParent(),
        ])
        run(pop)
    }
}
