import SpriteKit

/// A nighttime predator that hunts the player. Visually a dark-coated dog
/// with glowing red eyes. Subclasses `DogNode` so it plugs into the same
/// chase/bite/flee/contact pipeline (`dogs` array, `dogsTouchingPlayer`).
/// Differs in one rule: it takes **two** beanbag hits to scare off.
final class WolfNode: DogNode {

    /// Beanbag hits accumulated this life. At 2 the wolf starts fleeing.
    var bagHitsTaken: Int = 0

    override init() {
        super.init()

        if let body = children.compactMap({ $0 as? SKSpriteNode }).first {
            body.color = SKColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1)
            body.colorBlendFactor = 0.85
        }

        for dx in [CGFloat(-3), CGFloat(3)] {
            let eye = SKShapeNode(circleOfRadius: 1.8)
            eye.fillColor = SKColor(red: 1.0, green: 0.12, blue: 0.10, alpha: 1)
            eye.strokeColor = .clear
            eye.glowWidth = 2.0
            eye.position = CGPoint(x: dx, y: 4)
            eye.zPosition = 100
            addChild(eye)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Red flash for a non-fatal bag hit.
    func flashHit() {
        guard let body = children.compactMap({ $0 as? SKSpriteNode }).first else { return }
        body.removeAction(forKey: "wolfHitFlash")
        body.run(.sequence([
            .colorize(with: .red, colorBlendFactor: 1.0, duration: 0.0),
            .wait(forDuration: 0.10),
            .colorize(with: SKColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1),
                      colorBlendFactor: 0.85, duration: 0.18),
        ]), withKey: "wolfHitFlash")
    }
}
