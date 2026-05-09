import SpriteKit

final class DogNode: SKNode {

    let chaseSpeed: CGFloat = 88.0

    // When the player climbs a tree, lock in the dog's current heading so it
    // runs straight through rather than re-targeting the player.
    private var straightRunVelocity: CGVector? = nil

    private var legPhase: CGFloat = 0
    private var legFront: SKSpriteNode!
    private var legBack: SKSpriteNode!

    override init() {
        super.init()
        buildVisual()
        setupPhysics()
    }

    private func buildVisual() {
        let brown     = SKColor(red: 0.55, green: 0.30, blue: 0.09, alpha: 1.0)
        let darkBrown = SKColor(red: 0.35, green: 0.18, blue: 0.04, alpha: 1.0)
        let black     = SKColor(red: 0.08, green: 0.05, blue: 0.01, alpha: 1.0)

        // Body
        let body = SKSpriteNode(color: brown, size: CGSize(width: 13, height: 6))
        body.position = CGPoint(x: -1, y: 0)
        addChild(body)

        // Head (right side when facing right)
        let head = SKSpriteNode(color: brown, size: CGSize(width: 8, height: 8))
        head.position = CGPoint(x: 9, y: 2)
        addChild(head)

        // Snout
        let snout = SKSpriteNode(color: darkBrown, size: CGSize(width: 4, height: 4))
        snout.position = CGPoint(x: 14, y: 0)
        addChild(snout)

        // Nose
        let nose = SKSpriteNode(color: black, size: CGSize(width: 2, height: 2))
        nose.position = CGPoint(x: 16, y: 1)
        addChild(nose)

        // Ears
        for xOff: CGFloat in [7, 11] {
            let ear = SKSpriteNode(color: darkBrown, size: CGSize(width: 4, height: 5))
            ear.position = CGPoint(x: xOff, y: 7)
            addChild(ear)
        }

        // Tail (left side when facing right)
        let tail = SKSpriteNode(color: brown, size: CGSize(width: 4, height: 4))
        tail.position = CGPoint(x: -8, y: 4)
        addChild(tail)

        // Legs — stored so update() can animate them
        let front = SKSpriteNode(color: darkBrown, size: CGSize(width: 3, height: 5))
        front.position = CGPoint(x: 4, y: -5)
        addChild(front)
        legFront = front

        let back = SKSpriteNode(color: darkBrown, size: CGSize(width: 3, height: 5))
        back.position = CGPoint(x: -4, y: -5)
        addChild(back)
        legBack = back
    }

    private func setupPhysics() {
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 18, height: 10))
        pb.isDynamic      = true
        pb.allowsRotation = false
        pb.mass           = 0.08
        pb.friction       = 0.0
        pb.linearDamping  = 10.0
        // Dog is an enemy; it collides with walls and touches the player.
        pb.categoryBitMask    = PlayerNode.enemyBit
        pb.collisionBitMask   = PlayerNode.worldBit
        pb.contactTestBitMask = PlayerNode.categoryBit
        physicsBody = pb
    }

    func update(dt: TimeInterval, playerPosition: CGPoint, playerInTree: Bool, isBiting: Bool) {
        zPosition = -position.y

        // The player's physics body is anchored at the feet (16 px below sprite
        // center). Aim there so the dog's body actually overlaps the player's
        // body and fires a contact event.
        let target = CGPoint(x: playerPosition.x, y: playerPosition.y - 16)

        if playerInTree {
            if straightRunVelocity == nil {
                // Lock the dog's heading at the moment the player climbs. If
                // the dog was latched on the player (velocity ~0), give it a
                // fallback direction based on its current facing so it actually
                // runs off-screen.
                let vel = physicsBody?.velocity ?? .zero
                let spd = hypot(vel.dx, vel.dy)
                if spd > 2 {
                    straightRunVelocity = CGVector(dx: vel.dx / spd * chaseSpeed,
                                                   dy: vel.dy / spd * chaseSpeed)
                } else {
                    let dx = target.x - position.x
                    let dy = target.y - position.y
                    let d  = hypot(dx, dy)
                    if d > 2 {
                        straightRunVelocity = CGVector(dx: dx / d * chaseSpeed, dy: dy / d * chaseSpeed)
                    } else {
                        // Right on top of the player. Run in our facing direction.
                        let dirX: CGFloat = xScale >= 0 ? 1 : -1
                        straightRunVelocity = CGVector(dx: dirX * chaseSpeed, dy: 0)
                    }
                }
            }
        } else {
            straightRunVelocity = nil
        }

        let targetVelocity: CGVector
        if let sv = straightRunVelocity {
            targetVelocity = sv
        } else if isBiting {
            // Latched on. Snap our position to the player's feet and stay put
            // so contact remains active and the cooldown can keep ticking damage.
            position = target
            targetVelocity = .zero
        } else {
            // Always chase at full speed — never park in front of the player,
            // or the bodies won't overlap and didBegin never fires.
            let dx   = target.x - position.x
            let dy   = target.y - position.y
            let dist = max(hypot(dx, dy), 0.001)
            targetVelocity = CGVector(dx: dx / dist * chaseSpeed,
                                      dy: dy / dist * chaseSpeed)
        }
        physicsBody?.velocity = targetVelocity

        // Flip to face direction of travel.
        let vx = physicsBody?.velocity.dx ?? 0
        if abs(vx) > 2 { xScale = vx >= 0 ? 1 : -1 }

        // Alternating leg bob.
        legPhase += CGFloat(dt) * 12
        let bob: CGFloat = sin(legPhase) * 1.5
        legFront.position.y = -5 + bob
        legBack.position.y  = -5 - bob
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }
}
