import SpriteKit

// MARK: - GopherNode
// A pesky gopher that pops up during cornhole throws and chases the bag.
// If it reaches the bag before the bag lands, it steals the throw.
// Visual is drawn programmatically in a chunky 16-bit style to match the rest
// of the mini-game (matches DogNode's approach).

final class GopherNode: SKNode {

    enum Phase {
        case emerging   // popping up from the dirt (no chase yet)
        case chasing    // actively running toward the bag
        case caught     // grabbed the bag, retreating into the hole
        case diving     // missed — diving back down to despawn
    }

    private(set) var phase: Phase = .emerging
    let chaseSpeed: CGFloat = 140.0

    // Catch hitbox — distance at which the gopher grabs the throw-line bag.
    let catchRadius: CGFloat = 24

    private var body: SKSpriteNode!
    private var head: SKSpriteNode!
    private var legPhase: CGFloat = 0
    private var legLeft: SKSpriteNode!
    private var legRight: SKSpriteNode!
    private var dirtMound: SKSpriteNode!
    private var facingRight: Bool = true

    override init() {
        super.init()
        buildVisual()
        setScale(2.0)   // chunky gopher — twice the size of the original sprite
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func buildVisual() {
        let fur      = SKColor(red: 0.62, green: 0.42, blue: 0.20, alpha: 1.0)
        let darkFur  = SKColor(red: 0.40, green: 0.26, blue: 0.10, alpha: 1.0)
        let belly    = SKColor(red: 0.82, green: 0.66, blue: 0.42, alpha: 1.0)
        let black    = SKColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 1.0)
        let tooth    = SKColor(red: 0.95, green: 0.92, blue: 0.78, alpha: 1.0)
        let dirt     = SKColor(red: 0.32, green: 0.20, blue: 0.10, alpha: 1.0)

        // Dirt mound underneath — sits at z just under the gopher so it reads as a hole rim
        dirtMound = SKSpriteNode(color: dirt, size: CGSize(width: 18, height: 4))
        dirtMound.position = CGPoint(x: 0, y: -8)
        dirtMound.zPosition = -1
        addChild(dirtMound)

        // Body
        body = SKSpriteNode(color: fur, size: CGSize(width: 12, height: 8))
        body.position = CGPoint(x: 0, y: 0)
        addChild(body)

        // Belly highlight
        let bellyPatch = SKSpriteNode(color: belly, size: CGSize(width: 8, height: 3))
        bellyPatch.position = CGPoint(x: 0, y: -2)
        addChild(bellyPatch)

        // Head (right side when facing right)
        head = SKSpriteNode(color: fur, size: CGSize(width: 9, height: 8))
        head.position = CGPoint(x: 6, y: 4)
        addChild(head)

        // Snout
        let snout = SKSpriteNode(color: belly, size: CGSize(width: 4, height: 3))
        snout.position = CGPoint(x: 10, y: 3)
        addChild(snout)

        // Buck teeth
        let teeth = SKSpriteNode(color: tooth, size: CGSize(width: 2, height: 2))
        teeth.position = CGPoint(x: 11, y: 1)
        addChild(teeth)

        // Nose
        let nose = SKSpriteNode(color: black, size: CGSize(width: 1, height: 1))
        nose.position = CGPoint(x: 12, y: 4)
        addChild(nose)

        // Eye
        let eye = SKSpriteNode(color: black, size: CGSize(width: 1, height: 2))
        eye.position = CGPoint(x: 8, y: 6)
        addChild(eye)

        // Ears
        let earL = SKSpriteNode(color: darkFur, size: CGSize(width: 2, height: 2))
        earL.position = CGPoint(x: 3, y: 8)
        addChild(earL)
        let earR = SKSpriteNode(color: darkFur, size: CGSize(width: 2, height: 2))
        earR.position = CGPoint(x: 7, y: 8)
        addChild(earR)

        // Legs (animated during chase)
        legLeft = SKSpriteNode(color: darkFur, size: CGSize(width: 2, height: 3))
        legLeft.position = CGPoint(x: -3, y: -5)
        addChild(legLeft)

        legRight = SKSpriteNode(color: darkFur, size: CGSize(width: 2, height: 3))
        legRight.position = CGPoint(x: 3, y: -5)
        addChild(legRight)

        // Start hidden below ground — emerge() reveals everything
        for child in children where child !== dirtMound {
            child.isHidden = true
        }
        dirtMound.setScale(0.2)
    }

    /// Pop-up animation. Calls `completion` when chase phase begins.
    func emerge(completion: @escaping () -> Void) {
        phase = .emerging
        // Dirt mound puffs out first
        dirtMound.run(SKAction.scale(to: 1.0, duration: 0.10))

        // Gopher rises up from the dirt — start sunk below ground, then slide up.
        let riseDistance: CGFloat = 14
        run(SKAction.wait(forDuration: 0.08)) { [weak self] in
            guard let self else { return }
            for child in self.children where child !== self.dirtMound {
                let finalY = child.position.y
                child.position.y = finalY - riseDistance
                child.isHidden = false
                child.alpha = 0
                let rise = SKAction.group([
                    SKAction.moveTo(y: finalY, duration: 0.18),
                    SKAction.fadeIn(withDuration: 0.10),
                ])
                rise.timingMode = .easeOut
                child.run(rise)
            }
            // Squash-and-stretch on the whole gopher for a punchy pop.
            let baseY = self.yScale
            self.run(SKAction.sequence([
                SKAction.scaleY(to: baseY * 1.20, duration: 0.10),
                SKAction.scaleY(to: baseY,        duration: 0.08),
            ]))
            self.run(SKAction.wait(forDuration: 0.22)) { [weak self] in
                self?.phase = .chasing
                completion()
            }
        }
    }

    /// Move toward a target point. Call from scene update.
    func chase(toward target: CGPoint, dt: CGFloat) {
        guard phase == .chasing else { return }

        let dx = target.x - position.x
        let dy = target.y - position.y
        let dist = max(hypot(dx, dy), 0.001)
        let step = chaseSpeed * dt
        position.x += dx / dist * min(step, dist)
        position.y += dy / dist * min(step, dist)

        // Face the bag
        let wantFacingRight = dx >= 0
        if wantFacingRight != facingRight {
            facingRight = wantFacingRight
            xScale = facingRight ? 1.0 : -1.0
        }

        // Leg waddle
        legPhase += dt * 14
        let bob = sin(legPhase) * 1.5
        legLeft.position.y  = -5 + bob
        legRight.position.y = -5 - bob
    }

    /// Bag is in range — grab it and retreat. Spawns a "STOLEN!" label via caller.
    func catchAndRetreat(completion: @escaping () -> Void) {
        phase = .caught
        // Quick chomp then dive — multiplicative so it works at any base scale.
        let chomp = SKAction.sequence([
            SKAction.scale(by: 1.25, duration: 0.06),
            SKAction.scale(by: 1.0 / 1.25, duration: 0.06),
        ])
        let dive = SKAction.group([
            SKAction.scale(to: 0.1, duration: 0.22),
            SKAction.fadeOut(withDuration: 0.22),
        ])
        run(SKAction.sequence([
            chomp,
            dive,
            SKAction.run(completion),
            SKAction.removeFromParent(),
        ]))
    }

    /// Missed — dive back into the dirt and despawn.
    func diveAway() {
        guard phase != .caught && phase != .diving else { return }
        phase = .diving
        let dive = SKAction.group([
            SKAction.scale(to: 0.1, duration: 0.22),
            SKAction.fadeOut(withDuration: 0.22),
        ])
        run(SKAction.sequence([
            dive,
            SKAction.removeFromParent(),
        ]))
    }
}
