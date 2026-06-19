import SpriteKit

/// A wandering member of Billy's gang. Roams the visible stage and chases the
/// player when nearby; on contact GameScene launches a 7-point cornhole match.
final class BullyNode: SKNode {

    private let wanderSpeed: CGFloat = 28.0
    private let chaseSpeed:  CGFloat = 50.0
    private let chaseRadius: CGFloat = 120.0

    /// Set true while a bully-vs-player match is being launched / running so the
    /// bully halts and produces no further contacts.
    var isEngaged: Bool = false

    /// GameScene supplies this so the bully can probe whether a world point
    /// is passable. When set, the bully steers around walls/water before its
    /// reactive stuck-detection kicks in.
    var walkableProbe: ((CGPoint) -> Bool)? = nil

    /// Bag-hit state. After 2 bag hits the bully flees off-screen.
    private(set) var bagHits: Int = 0
    private(set) var isFleeingFromBag: Bool = false
    private var fleeVelocity: CGVector = .zero
    /// Brief stun + knockback after a non-fatal bag hit. While > 0, no chase or wander.
    private var stunTimer: TimeInterval = 0
    private var knockbackVelocity: CGVector = .zero
    private let stunDuration: TimeInterval = 0.8

    /// Force the bully into flee mode directly away from `awayPos`, without a
    /// bag-hit flash. Used when GameScene detects the bully has been stuck
    /// against geometry for too long and should just leave the scene.
    func startFleeing(awayFrom awayPos: CGPoint) {
        guard !isFleeingFromBag else { return }
        isFleeingFromBag = true
        let dx = position.x - awayPos.x
        let dy = position.y - awayPos.y
        let d = max(hypot(dx, dy), 0.001)
        let speed: CGFloat = chaseSpeed * 1.5
        fleeVelocity = CGVector(dx: dx / d * speed, dy: dy / d * speed)
    }

    /// Called by GameScene when a thrown beanbag connects.
    /// Returns true if the bully is now fleeing (so caller can drop the contact).
    @discardableResult
    func takeBagHit(from origin: CGPoint) -> Bool {
        guard !isFleeingFromBag else { return true }
        bagHits += 1
        let dx = position.x - origin.x
        let dy = position.y - origin.y
        let d = max(hypot(dx, dy), 0.001)

        // Quick red flash for feedback.
        bodySprite.removeAction(forKey: "hitFlash")
        bodySprite.run(.sequence([
            .colorize(with: .red, colorBlendFactor: 1.0, duration: 0.0),
            .wait(forDuration: 0.10),
            .colorize(withColorBlendFactor: 0.0, duration: 0.20),
        ]), withKey: "hitFlash")

        if bagHits >= 2 {
            isFleeingFromBag = true
            let speed: CGFloat = chaseSpeed * 1.5
            fleeVelocity = CGVector(dx: dx / d * speed, dy: dy / d * speed)
            return true
        }

        // First hit — stun + knockback, then resume chasing.
        stunTimer = stunDuration
        let kb: CGFloat = 110
        knockbackVelocity = CGVector(dx: dx / d * kb, dy: dy / d * kb)
        return false
    }

    private var bodySprite: SKSpriteNode!
    private var wanderHeading: CGVector = .zero
    private var wanderRetargetTimer: TimeInterval = 0
    private var animTime: TimeInterval = 0

    // Obstacle-avoidance / unstick state. When the bully is pushed up against
    // a wall by physics its actual displacement drops to ~0 even though we
    // keep commanding velocity. After ~stuckThreshold seconds we commit to a
    // perpendicular "detour" heading for detourDuration so we slide around
    // the obstacle instead of mashing into it.
    private var lastPosition: CGPoint = .zero
    private var stuckTimer: TimeInterval = 0
    private var detourTimer: TimeInterval = 0
    private var detourSign: CGFloat = 1            // +1 / -1 chooses which side
    private let stuckThreshold:  TimeInterval = 0.25
    private let detourDuration:  TimeInterval = 0.7
    /// Minimum per-second displacement to count as "making progress."
    private let progressEpsilon: CGFloat = 6.0

    // bully.png — 512x896, 8 cols x 14 rows of 64x64 frames.
    // The first column shows the starting pose for each direction; the row
    // continues the walk cycle for that direction across the 8 columns.
    // Row 0 = down-walk, row 1 = right-walk, row 2 = up-walk. There is no
    // dedicated left row — mirror the right row horizontally via xScale.
    private enum Facing: Int { case down = 0, right = 1, up = 2, left = 3 }
    private var facing: Facing = .down

    private static let cols = 8
    private static let rows = 14
    private static let frameSheet: SKTexture = {
        let t = SKTexture(imageNamed: "bully")
        t.filteringMode = .nearest
        return t
    }()
    /// walkFrames[row] = array of 8 textures across that row. Only rows 0..2
    /// are populated (down / right / up). Left is rendered via xScale on the
    /// right row.
    private static let walkFrames: [[SKTexture]] = {
        let fw: CGFloat = 1.0 / CGFloat(cols)
        let fh: CGFloat = 1.0 / CGFloat(rows)
        var all: [[SKTexture]] = []
        for row in 0..<3 {
            var rowFrames: [SKTexture] = []
            // SKTexture rect origin is bottom-left; row 0 of the art (top row)
            // sits at y = 1 - fh in normalized coords.
            let y = 1.0 - CGFloat(row + 1) * fh
            for col in 0..<cols {
                let rect = CGRect(x: CGFloat(col) * fw, y: y, width: fw, height: fh)
                let tex = SKTexture(rect: rect, in: frameSheet)
                tex.filteringMode = .nearest
                rowFrames.append(tex)
            }
            all.append(rowFrames)
        }
        return all
    }()

    override init() {
        super.init()
        buildVisual()
        setupPhysics()
        pickNewWanderHeading()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func buildVisual() {
        let sprite = SKSpriteNode(texture: BullyNode.walkFrames[0][0])
        sprite.size = CGSize(width: 56, height: 56)
        sprite.position = CGPoint(x: 0, y: 16)
        sprite.zPosition = 1
        addChild(sprite)
        bodySprite = sprite
    }

    private func setupPhysics() {
        // Visual sprite is offset to (0, 16); place the body at the visible feet,
        // not at the node origin (which sits below the visible character art).
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 18, height: 12),
                               center: CGPoint(x: 0, y: 10))
        pb.isDynamic      = true
        pb.allowsRotation = false
        pb.mass           = 0.12
        pb.friction       = 0.0
        pb.linearDamping  = 10.0
        pb.categoryBitMask    = PlayerNode.enemyBit
        pb.collisionBitMask   = PlayerNode.worldBit
        pb.contactTestBitMask = PlayerNode.categoryBit
        physicsBody = pb
    }

    func update(dt: TimeInterval, playerPosition: CGPoint, playerInTree: Bool) {
        zPosition = -(position.y - 4)

        if isEngaged {
            physicsBody?.velocity = .zero
            return
        }

        if isFleeingFromBag {
            physicsBody?.velocity = fleeVelocity
            updateFacing(velocity: fleeVelocity)
            updateAnimation(dt: dt, velocity: fleeVelocity)
            return
        }

        if stunTimer > 0 {
            stunTimer -= dt
            physicsBody?.velocity = knockbackVelocity
            // Decay knockback so the bully slides to a stop before resuming.
            knockbackVelocity = CGVector(dx: knockbackVelocity.dx * 0.85,
                                         dy: knockbackVelocity.dy * 0.85)
            updateAnimation(dt: dt, velocity: .zero)
            return
        }

        // Chase when the player is close and not safely up a tree.
        let dx = playerPosition.x - position.x
        let dy = (playerPosition.y - 6) - position.y
        let dist = hypot(dx, dy)

        // Desired pre-detour heading (chase target or wander direction).
        var desired: CGVector
        let speedScale: CGFloat
        if !playerInTree && dist < chaseRadius && dist > 0.001 {
            desired = CGVector(dx: dx / dist, dy: dy / dist)
            speedScale = chaseSpeed
        } else {
            wanderRetargetTimer -= dt
            if wanderRetargetTimer <= 0 { pickNewWanderHeading() }
            let mag = max(hypot(wanderHeading.dx, wanderHeading.dy), 0.001)
            desired = CGVector(dx: wanderHeading.dx / mag, dy: wanderHeading.dy / mag)
            speedScale = wanderSpeed
        }

        // Proactive look-ahead: steer around walls before we collide with them.
        desired = steerAroundObstacles(desired: desired)

        // Detect "stuck" by sampling actual displacement vs commanded motion.
        // If physics has pinned us against a wall, our position barely changes
        // even though velocity is large.
        let actualDelta = hypot(position.x - lastPosition.x, position.y - lastPosition.y)
        let expectedDelta = speedScale * CGFloat(dt)
        if dt > 0 && expectedDelta > 1, actualDelta < min(progressEpsilon * CGFloat(dt), expectedDelta * 0.35) {
            stuckTimer += dt
            if detourTimer <= 0 && stuckTimer >= stuckThreshold {
                detourTimer = detourDuration
                detourSign  = Bool.random() ? 1 : -1
                stuckTimer  = 0
            }
        } else {
            stuckTimer = 0
        }

        // Apply a perpendicular detour heading if we're currently sliding past
        // an obstacle. The desired direction is preserved as a soft pull so
        // the bully eventually rejoins the chase once it clears the corner.
        if detourTimer > 0 {
            detourTimer -= dt
            // perpendicular to desired
            let perp = CGVector(dx: -desired.dy * detourSign, dy: desired.dx * detourSign)
            // Blend: mostly perpendicular, light forward pull.
            let blendX = perp.dx * 0.85 + desired.dx * 0.35
            let blendY = perp.dy * 0.85 + desired.dy * 0.35
            let m = max(hypot(blendX, blendY), 0.001)
            desired = CGVector(dx: blendX / m, dy: blendY / m)
        }

        let velocity = CGVector(dx: desired.dx * speedScale,
                                dy: desired.dy * speedScale)
        physicsBody?.velocity = velocity
        lastPosition = position

        updateFacing(velocity: velocity)
        updateAnimation(dt: dt, velocity: velocity)
    }

    private func updateFacing(velocity: CGVector) {
        // Pick row by dominant axis. Horizontal wins ties on purpose so a
        // diagonal-running bully animates with side frames.
        if abs(velocity.dx) >= abs(velocity.dy) {
            if velocity.dx > 2       { facing = .right }
            else if velocity.dx < -2 { facing = .left }
        } else {
            if velocity.dy > 2       { facing = .up }
            else if velocity.dy < -2 { facing = .down }
        }
    }

    private func updateAnimation(dt: TimeInterval, velocity: CGVector) {
        let speed = hypot(velocity.dx, velocity.dy)
        // Left reuses the right row, mirrored horizontally.
        let rowIndex: Int
        switch facing {
        case .down:  rowIndex = 0; bodySprite.xScale = 1
        case .right: rowIndex = 1; bodySprite.xScale = 1
        case .up:    rowIndex = 2; bodySprite.xScale = 1
        case .left:  rowIndex = 1; bodySprite.xScale = -1
        }
        let frames = BullyNode.walkFrames[rowIndex]
        if speed > 2 {
            animTime += dt * Double(max(speed / 60.0, 1.0))
            let fps: Double = 10
            // Only the first 6 columns of each walk row contain art —
            // columns 6 and 7 in the bully sheet are blank and would
            // flash the bully invisible if we cycled through them.
            let walkFrameCount = min(6, frames.count)
            let idx = Int(animTime * fps) % walkFrameCount
            bodySprite.texture = frames[idx]
        } else {
            // Standing still — show the first frame of the current facing row.
            animTime = 0
            bodySprite.texture = frames[0]
        }
    }

    /// Probe a few angles around the desired heading and return the closest
    /// unit vector that lands on a walkable tile ~22 units ahead.
    private func steerAroundObstacles(desired: CGVector) -> CGVector {
        guard let probe = walkableProbe else { return desired }
        let lookAhead: CGFloat = 22
        let ahead = CGPoint(x: position.x + desired.dx * lookAhead,
                            y: position.y + desired.dy * lookAhead)
        if probe(ahead) { return desired }
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

    private func pickNewWanderHeading() {
        wanderRetargetTimer = .random(in: 1.6...3.4)
        let angle = CGFloat.random(in: 0..<(.pi * 2))
        wanderHeading = CGVector(dx: cos(angle) * wanderSpeed,
                                 dy: sin(angle) * wanderSpeed)
    }
}
