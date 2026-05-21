import SpriteKit

/// A beanbag thrown by the player on the world map. Travels in a straight line
/// for a fixed range, then pops. GameScene drives motion + collision manually
/// in update() rather than using SpriteKit physics, so it can pick out dogs
/// and bullies precisely without changing existing collision masks.
final class BeanbagProjectile: SKNode {

    var velocity: CGVector
    /// Remaining travel time before the bag lands.
    var lifeRemaining: TimeInterval
    /// True once the bag has come to rest on the ground.
    private(set) var hasLanded = false
    var isDead = false

    init(velocity: CGVector, lifetime: TimeInterval) {
        self.velocity = velocity
        self.lifeRemaining = lifetime
        super.init()
        buildVisual()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func buildVisual() {
        // Shadow underneath so the bag reads as airborne.
        let shadow = SKShapeNode(circleOfRadius: 5)
        shadow.fillColor = SKColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -4)
        shadow.zPosition = -1
        addChild(shadow)

        let body = SKShapeNode(circleOfRadius: 5)
        body.fillColor = SKColor(red: 0.85, green: 0.38, blue: 0.10, alpha: 1.0)
        body.strokeColor = SKColor(red: 0.40, green: 0.18, blue: 0.04, alpha: 1.0)
        body.lineWidth = 1
        addChild(body)

        // Slow spin.
        run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.45)))
    }

    /// Pop animation; the caller is responsible for removing the node after.
    func pop() {
        isDead = true
        removeAllActions()
        run(.sequence([
            .group([.scale(to: 1.8, duration: 0.12), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
    }

    /// Stops mid-flight, sits as a static bag on the ground briefly, then fades out.
    func land() {
        guard !hasLanded, !isDead else { return }
        hasLanded = true
        velocity = .zero
        removeAllActions()              // stop the spin
        zRotation = 0
        // Tiny "thud" squash.
        let squash = SKAction.sequence([
            .scaleY(to: 0.75, duration: 0.06),
            .scaleY(to: 1.0,  duration: 0.08),
        ])
        run(.sequence([
            squash,
            .wait(forDuration: 1.5),
            .fadeOut(withDuration: 0.40),
            .run { [weak self] in self?.isDead = true },
            .removeFromParent(),
        ]))
    }
}
