import SpriteKit

class DogNode: SKNode {

    let chaseSpeed: CGFloat = 62.0

    // When the player climbs a tree, lock in the dog's current heading so it
    // runs straight through rather than re-targeting the player.
    private var straightRunVelocity: CGVector? = nil

    // After the first bite the dog bolts in the opposite direction and never
    // re-targets the player. GameScene calls startFleeing(awayFrom:) to trigger.
    private(set) var isFleeing = false
    private var fleeVelocity: CGVector = .zero

    // Biscuit distraction — GameScene assigns a world position; dog walks there and eats.
    var biscuitTarget: CGPoint? = nil

    /// GameScene supplies this so the dog can probe whether a world point is
    /// passable. When set, the dog steers around walls and water instead of
    /// running straight into them.
    var walkableProbe: ((CGPoint) -> Bool)? = nil
    private(set) var isEating = false
    private var eatTimer: TimeInterval = 0
    private let eatDuration: TimeInterval = 3.0
    var onFinishedEating: (() -> Void)? = nil

    /// Lock in a flee heading directly away from `playerPos` and switch the
    /// dog into flee mode. After this the dog ignores the player entirely.
    func startFleeing(awayFrom playerPos: CGPoint) {
        guard !isFleeing else { return }
        isFleeing = true
        let dx = position.x - playerPos.x
        let dy = position.y - playerPos.y
        let dist = max(hypot(dx, dy), 0.001)
        // Run away at 1.4× normal speed so the escape feels snappy.
        let speed = chaseSpeed * 1.4
        fleeVelocity = CGVector(dx: dx / dist * speed, dy: dy / dist * speed)
    }

    private var animTime: TimeInterval = 0
    private var bodySprite: SKSpriteNode!
    private static let walkFrames: [SKTexture] = {
        let sheet = SKTexture(imageNamed: "Walk")
        sheet.filteringMode = .nearest
        let cols = 6
        let fw: CGFloat = 1.0 / CGFloat(cols)
        var frames: [SKTexture] = []
        for i in 0..<cols {
            let rect = CGRect(x: CGFloat(i) * fw, y: 0, width: fw, height: 1)
            let t = SKTexture(rect: rect, in: sheet)
            t.filteringMode = .nearest
            frames.append(t)
        }
        return frames
    }()

    override init() {
        super.init()
        buildVisual()
        setupPhysics()
    }

    private func buildVisual() {
        let sprite = SKSpriteNode(texture: DogNode.walkFrames[0])
        sprite.size = CGSize(width: 24, height: 24)
        sprite.position = CGPoint(x: 0, y: 2)
        addChild(sprite)
        bodySprite = sprite
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
        zPosition = -(position.y - 3)  // sort by feet (body bottom), not center

        // The player's physics body is anchored at the visible feet (offset
        // below sprite center). Aim there so the dog's body actually overlaps
        // the player's body and fires a contact event.
        let target = CGPoint(x: playerPosition.x, y: playerPosition.y - 6)

        // Biscuit target suppresses tree-run locking so the dog doesn't drift off.
        if biscuitTarget == nil {
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
        } else {
            straightRunVelocity = nil
        }

        let targetVelocity: CGVector
        if isFleeing {
            // Bolt away — ignore player position and any other state.
            targetVelocity = fleeVelocity
        } else if isEating {
            // Standing still over biscuit — tick down eat timer.
            eatTimer += dt
            if eatTimer >= eatDuration {
                isEating = false
                biscuitTarget = nil
                eatTimer = 0
                onFinishedEating?()
                onFinishedEating = nil
            }
            targetVelocity = .zero
        } else if let bpos = biscuitTarget {
            // Walk toward biscuit; begin eating when close enough.
            let dx   = bpos.x - position.x
            let dy   = bpos.y - position.y
            let dist = hypot(dx, dy)
            if dist < 8 {
                isEating = true
                eatTimer = 0
                targetVelocity = .zero
            } else {
                targetVelocity = CGVector(dx: dx / dist * chaseSpeed, dy: dy / dist * chaseSpeed)
            }
        } else if let sv = straightRunVelocity {
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
            let desired = CGVector(dx: dx / dist, dy: dy / dist)
            let steered = steerAroundObstacles(desired: desired)
            targetVelocity = CGVector(dx: steered.dx * chaseSpeed,
                                      dy: steered.dy * chaseSpeed)
        }
        physicsBody?.velocity = targetVelocity

        // Flip to face direction of travel.
        let vx = physicsBody?.velocity.dx ?? 0
        if abs(vx) > 2 { xScale = vx >= 0 ? 1 : -1 }

        // Advance walk-cycle frame based on movement speed; pause when eating/idle.
        let speed = hypot(targetVelocity.dx, targetVelocity.dy)
        if speed > 2 {
            animTime += dt * Double(max(speed / 60.0, 1.0))
            let fps: Double = 10
            let idx = Int(animTime * fps) % DogNode.walkFrames.count
            bodySprite.texture = DogNode.walkFrames[idx]
        } else {
            animTime = 0
            bodySprite.texture = DogNode.walkFrames[0]
        }
    }

    /// Probe a few angles around the desired heading and return the closest
    /// unit vector that lands on a walkable tile ~18 units ahead. Falls back
    /// to the desired direction if no probe is configured or every angle is
    /// blocked (lets physics resolve it).
    private func steerAroundObstacles(desired: CGVector) -> CGVector {
        guard let probe = walkableProbe else { return desired }
        let lookAhead: CGFloat = 18
        let ahead = CGPoint(x: position.x + desired.dx * lookAhead,
                            y: position.y + desired.dy * lookAhead)
        if probe(ahead) { return desired }
        // Try alternating left/right deflections, widening until something opens up.
        let deflections: [CGFloat] = [30, -30, 60, -60, 90, -90, 130, -130]
        for deg in deflections {
            let rad = deg * .pi / 180
            let c = cos(rad), s = sin(rad)
            let nx = desired.dx * c - desired.dy * s
            let ny = desired.dx * s + desired.dy * c
            let p = CGPoint(x: position.x + nx * lookAhead,
                            y: position.y + ny * lookAhead)
            if probe(p) { return CGVector(dx: nx, dy: ny) }
        }
        return desired
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }
}
