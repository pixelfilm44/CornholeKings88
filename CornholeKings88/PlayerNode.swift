import SpriteKit

final class PlayerNode: SKSpriteNode {

    static let categoryBit: UInt32 = 0x1 << 0
    static let worldBit:    UInt32 = 0x1 << 1
    static let enemyBit:    UInt32 = 0x1 << 3

    enum AnimState { case idle, move, attack, death }
    enum Facing { case down, up, right, left }

    private static let frameW = 64
    private static let frameH = 64
    private static let cols = 6
    // On-screen render size — kept at the legacy 48×48 so physics, tree canopy,
    // and world-tile scale all stay tuned regardless of source frame size.
    private static let renderW: CGFloat = 48
    private static let renderH: CGFloat = 48

    // Row layout (0-based, top-down). Each block lists 3 rows for the 3
    // distinct facings; left is produced by flipping right.
    // Order: down, right, up. Left is produced by flipping right.
    private static let idleRows:   [Facing: Int] = [.down: 0, .right: 1, .up: 2]
    private static let moveRows:   [Facing: Int] = [.down: 3, .right: 4, .up: 5]
    private static let attackRows: [Facing: Int] = [.down: 6, .right: 7, .up: 8]
    private static let deathRow = 9

    /// Loaded once from Assets.xcassets ("jeff_sprite" imageset).
    private static let sheet: SKTexture? = {
        let t = SKTexture(imageNamed: "jeff_sprite")
        t.filteringMode = .nearest
        return t
    }()

    private static func framesForRow(_ row: Int) -> [SKTexture] {
        guard let sheet = sheet else { return [] }
        let texW = sheet.size().width
        let texH = sheet.size().height
        guard texW > 0, texH > 0 else { return [] }
        let nW = CGFloat(frameW) / texW
        let nH = CGFloat(frameH) / texH
        // SKTexture rect uses bottom-left origin; sheet rows are top-down.
        let nY = 1.0 - CGFloat(row + 1) * nH
        return (0..<cols).map { col in
            let nX = CGFloat(col) * nW
            let t = SKTexture(rect: CGRect(x: nX, y: nY, width: nW, height: nH), in: sheet)
            t.filteringMode = .nearest
            return t
        }
    }

    private static func buildAnims() -> [AnimState: [Facing: [SKTexture]]] {
        func build(_ rows: [Facing: Int]) -> [Facing: [SKTexture]] {
            var d: [Facing: [SKTexture]] = [:]
            for (f, r) in rows { d[f] = framesForRow(r) }
            d[.left] = d[.right]   // mirrored via xScale at runtime
            return d
        }
        let death = framesForRow(deathRow)
        return [
            .idle:   build(idleRows),
            .move:   build(moveRows),
            .attack: build(attackRows),
            .death:  [.down: death, .up: death, .right: death, .left: death],
        ]
    }

    private static let anims: [AnimState: [Facing: [SKTexture]]] = buildAnims()

    var moveDirection: CGVector = .zero
    let moveSpeed: CGFloat = 120.0

    private(set) var isInTree: Bool = false
    private var treeOverlay: SKShapeNode?

    private var state: AnimState = .idle
    private var facing: Facing = .down

    /// Read-only access to current facing for world projectiles, etc.
    var currentFacing: Facing { facing }
    /// Unit vector in the direction the player is currently facing.
    var currentFacingVector: CGVector {
        switch facing {
        case .up:    return CGVector(dx: 0, dy: 1)
        case .down:  return CGVector(dx: 0, dy: -1)
        case .left:  return CGVector(dx: -1, dy: 0)
        case .right: return CGVector(dx: 1, dy: 0)
        }
    }

    init() {
        let first = PlayerNode.anims[.idle]?[.down]?.first
        super.init(texture: first,
                   color: .magenta,
                   size: CGSize(width: PlayerNode.renderW, height: PlayerNode.renderH))
        if first == nil { colorBlendFactor = 1.0 }

        // Anchor at the feet area: physics circle near the bottom of the sprite.
        // NOTE: y offset tuned so the cyan debug circle sits on the visible feet
        // of the current character art (not the bottom of the 48×48 frame).
        let body = SKPhysicsBody(circleOfRadius: 6.0, center: CGPoint(x: 0, y: -6))
        body.allowsRotation = false
        body.categoryBitMask    = PlayerNode.categoryBit
        body.collisionBitMask   = PlayerNode.worldBit
        body.contactTestBitMask = PlayerNode.worldBit | PlayerNode.enemyBit
        self.physicsBody = body

        playAnimation()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    func update(dt: TimeInterval) {
        zPosition = -(position.y - 6)   // sort by visible feet (matches physics body offset)

        // Moving while in a tree descends automatically
        if isInTree && (moveDirection.dx != 0 || moveDirection.dy != 0) {
            descendTree()
        }

        let moving = !isInTree && (moveDirection.dx != 0 || moveDirection.dy != 0)
        if moving {
            let step = moveSpeed * CGFloat(dt)
            position.x += moveDirection.dx * step
            position.y += moveDirection.dy * step
        }

        let newFacing = moving ? facingFor(moveDirection) : facing
        let newState: AnimState = moving ? .move : .idle
        setAnimation(state: newState, facing: newFacing)
    }

    func climbTree() {
        guard !isInTree else { return }
        isInTree = true
        moveDirection = .zero
        physicsBody?.velocity = .zero
        // Remove enemy contact — player is hidden in the foliage
        physicsBody?.contactTestBitMask &= ~PlayerNode.enemyBit

        let canopy = SKShapeNode(circleOfRadius: 20)
        canopy.fillColor   = SKColor(red: 0.13, green: 0.52, blue: 0.13, alpha: 0.68)
        canopy.strokeColor = SKColor(red: 0.04, green: 0.30, blue: 0.04, alpha: 0.95)
        canopy.lineWidth   = 1.5
        canopy.position    = CGPoint(x: 0, y: 10)
        canopy.zPosition   = 1
        canopy.name        = "treeCanopy"
        addChild(canopy)
        treeOverlay = canopy

        let rustle = SKAction.sequence([
            SKAction.scale(to: 1.10, duration: 0.12),
            SKAction.scale(to: 0.94, duration: 0.12),
            SKAction.scale(to: 1.0,  duration: 0.08),
        ])
        canopy.run(rustle)
    }

    func descendTree() {
        guard isInTree else { return }
        isInTree = false
        // Restore enemy contact
        physicsBody?.contactTestBitMask |= PlayerNode.enemyBit
        treeOverlay?.removeFromParent()
        treeOverlay = nil
    }

    /// External hooks for one-shot states.
    func playAttack(completion: (() -> Void)? = nil) {
        removeAction(forKey: "anim")
        state = .attack
        guard let frames = PlayerNode.anims[.attack]?[facing], !frames.isEmpty else {
            completion?(); return
        }
        applyFlip()
        let anim = SKAction.animate(with: frames, timePerFrame: 0.08, resize: false, restore: false)
        run(SKAction.sequence([anim, SKAction.run { [weak self] in
            self?.state = .idle
            self?.playAnimation()
            completion?()
        }]), withKey: "anim")
    }

    func playDeath() {
        removeAction(forKey: "anim")
        state = .death
        guard let frames = PlayerNode.anims[.death]?[facing], !frames.isEmpty else { return }
        applyFlip()
        let anim = SKAction.animate(with: frames, timePerFrame: 0.15, resize: false, restore: false)
        run(anim, withKey: "anim")
    }

    private func setAnimation(state newState: AnimState, facing newFacing: Facing) {
        if newState == state && newFacing == facing && action(forKey: "anim") != nil {
            applyFlip()
            return
        }
        state = newState
        facing = newFacing
        playAnimation()
    }

    private func playAnimation() {
        removeAction(forKey: "anim")
        applyFlip()
        guard let frames = PlayerNode.anims[state]?[facing], !frames.isEmpty else { return }
        let tpf: TimeInterval = (state == .move) ? 0.12 : 0.20
        let anim = SKAction.animate(with: frames, timePerFrame: tpf, resize: false, restore: false)
        run(SKAction.repeatForever(anim), withKey: "anim")
    }

    private func applyFlip() {
        let mag = abs(xScale) == 0 ? 1 : abs(xScale)
        xScale = (facing == .left) ? -mag : mag
    }

    private func facingFor(_ v: CGVector) -> Facing {
        if abs(v.dx) > abs(v.dy) {
            return v.dx > 0 ? .right : .left
        } else {
            return v.dy > 0 ? .up : .down
        }
    }

    private static func findInBundle(filename: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(at: resourceURL,
                                                              includingPropertiesForKeys: nil) else {
            return nil
        }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == filename { return url }
        }
        return nil
    }
}
