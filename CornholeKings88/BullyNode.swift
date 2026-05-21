import SpriteKit

/// A wandering member of Billy's gang. Roams the visible stage and chases the
/// player when nearby; on contact GameScene launches a 7-point cornhole match.
final class BullyNode: SKNode {

    private let wanderSpeed: CGFloat = 38.0
    private let chaseSpeed:  CGFloat = 66.0
    private let chaseRadius: CGFloat = 120.0

    /// Set true while a bully-vs-player match is being launched / running so the
    /// bully halts and produces no further contacts.
    var isEngaged: Bool = false

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
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 18, height: 12))
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

        // Chase when the player is close and not safely up a tree.
        let dx = playerPosition.x - position.x
        let dy = (playerPosition.y - 16) - position.y
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
            let idx = Int(animTime * fps) % frames.count
            bodySprite.texture = frames[idx]
        } else {
            // Standing still — show the first frame of the current facing row.
            animTime = 0
            bodySprite.texture = frames[0]
        }
    }

    private func pickNewWanderHeading() {
        wanderRetargetTimer = .random(in: 1.6...3.4)
        let angle = CGFloat.random(in: 0..<(.pi * 2))
        wanderHeading = CGVector(dx: cos(angle) * wanderSpeed,
                                 dy: sin(angle) * wanderSpeed)
    }
}
