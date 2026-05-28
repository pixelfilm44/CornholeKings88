import SpriteKit
import UIKit

// MARK: - BridgePiranhaScene
// Solo bridge-builder: throw 8 bean bags in a straight line across the river before
// running out of the 12 you have. Piranhas swim through and eat placed bags — watch
// for the fin warning, throw fast, and keep the bridge intact.

final class BridgePiranhaScene: SKScene {

    // MARK: - Public API
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    private var closeUIButton: UIButton? = nil  // unused; replaced by SK closeBtn

    // MARK: - Layout
    private var W: CGFloat = 0, H: CGFloat = 0
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var confirmingQuit = false
    private var confirmPanel: SKNode?
    private var riverMinY: CGFloat = 0      // bottom edge of river
    private var riverMaxY: CGFloat = 0      // top edge of river
    private var throwLineY: CGFloat = 0     // player throw position
    private var slotYPositions: [CGFloat] = []
    private let bridgeX: CGFloat = 0        // centre of screen / bridge line
    private var bridgeTolerance: CGFloat = 0

    // MARK: - Physics constants
    private let gravity: CGFloat      = 0.50
    private let vzInitial: CGFloat    = 15.0
    private let bzVisualScale: CGFloat = 0.42

    // MARK: - Aim oscillation
    private var targetX: CGFloat      = 0
    private var targetMovingRight     = true
    private var targetRange: CGFloat  = 0
    private var targetSpeed: CGFloat  = 0

    // MARK: - Flying bag
    private final class FlyingBag {
        var bx, by, bz: CGFloat
        var vx, vy, vz: CGFloat
        var rot: CGFloat  = 0
        var rotV: CGFloat = 0
        var landed        = false
        let node:   SKSpriteNode
        let shadow: SKSpriteNode
        let targetSlotIndex: Int

        init(startX: CGFloat, startY: CGFloat,
             targetSlotIndex: Int, targetY: CGFloat,
             gravity: CGFloat, vzInitial: CGFloat) {
            bx = startX; by = startY; bz = 3
            vx = 0; vz = vzInitial
            let frames = 2.0 * vzInitial / gravity   // ≈ 60
            vy = (targetY - startY) / frames
            self.targetSlotIndex = targetSlotIndex

            let tex = SKTexture(imageNamed: "bag_16bit")
            tex.filteringMode = .nearest
            node = SKSpriteNode(texture: tex, size: CGSize(width: 36, height: 36))
            node.color            = SKColor(red: 0.90, green: 0.28, blue: 0.28, alpha: 1)
            node.colorBlendFactor = 0.62
            node.zPosition        = 30

            shadow = SKSpriteNode(color: .black, size: CGSize(width: 36, height: 24))
            shadow.alpha     = 0.30
            shadow.zPosition = 7
        }
    }
    private var flyingBag: FlyingBag?

    // MARK: - Game state
    private var bagsRemaining = 12
    private var slotFilled    = Array(repeating: false, count: 8)
    private var slotBagNodes  = Array(repeating: nil as SKSpriteNode?, count: 8)
    private var gameOver      = false
    private var gameResult    = false

    private var nextUnfilledSlot: Int?   { slotFilled.firstIndex(of: false) }
    private var bridgeComplete:  Bool    { slotFilled.allSatisfy { $0 } }
    private var filledCount:     Int     { slotFilled.filter { $0 }.count }

    // MARK: - Piranha
    private enum PiranhaPhase { case idle, warning, swimming }
    private var piranhaPhase:       PiranhaPhase = .idle
    private var piranhaNode:        SKNode?
    private var finNode:            SKNode?
    private var piranhaY:           CGFloat       = 0
    private var piranhaX:           CGFloat       = 0
    private var piranhaVx:          CGFloat       = 0
    private var piranhaIdleTimer:   TimeInterval  = 0
    private var piranhaIdleDelay:   TimeInterval  = 6.0
    private var piranhaWarningTimer: TimeInterval = 0
    private var piranhaHasEaten     = false

    // MARK: - Nodes
    private var gameWorldNode:  SKEffectNode!
    private var aimIndicator:   SKSpriteNode?
    private var bagsLabel:      SKLabelNode?
    private var progressLabel:  SKLabelNode?

    // MARK: - Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // MARK: - Update timing
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        computeLayout()
        setupScene()
        setupUI()
        piranhaIdleDelay = Double.random(in: 5.0...9.0)
        if !TutorialManager.shared.hasSeen(TutorialManager.piranha) {
            presentTutorial(autoTriggered: true)
        }
    }

    override func willMove(from view: SKView) {
        // no UIKit close button to remove
    }

    // MARK: - Layout

    private func computeLayout() {
        let bankH       = H * 0.17
        throwLineY      = -H / 2 + bankH * 0.50
        riverMinY       = -H / 2 + bankH
        riverMaxY       =  H / 2 - bankH
        targetRange     = W * 0.28
        targetSpeed     = W * 0.62
        bridgeTolerance = W * 0.13

        let step = (riverMaxY - riverMinY) / 9.0
        slotYPositions = (0..<8).map { riverMinY + step * CGFloat($0 + 1) }
    }

    // MARK: - Scene construction

    private func setupScene() {
        gameWorldNode = SKEffectNode()
        if let f = CIFilter(name: "CIPixellate") {
            f.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = f
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        addChild(gameWorldNode)

        buildBanks()
        buildRiver()
        buildBridgeGuide()
        buildSlotMarkers()
        buildThrowLine()
        buildAimIndicator()
    }

    private func buildBanks() {
        let bankH = riverMinY + H / 2

        // Near bank (player side, bottom)
        let nearBank = SKSpriteNode(
            color: SKColor(red: 0.18, green: 0.36, blue: 0.12, alpha: 1),
            size: CGSize(width: W, height: bankH + 4))
        nearBank.position  = CGPoint(x: 0, y: -H / 2 + bankH / 2)
        nearBank.zPosition = -100
        gameWorldNode.addChild(nearBank)

        // Far bank (top)
        let farBankH = H / 2 - riverMaxY
        let farBank = SKSpriteNode(
            color: SKColor(red: 0.14, green: 0.28, blue: 0.09, alpha: 1),
            size: CGSize(width: W, height: farBankH + 4))
        farBank.position  = CGPoint(x: 0, y: H / 2 - farBankH / 2)
        farBank.zPosition = -100
        gameWorldNode.addChild(farBank)

        // Muddy bank edges where water meets land
        for (y, sign): (CGFloat, CGFloat) in [(riverMinY, 1), (riverMaxY, -1)] {
            let edge = SKSpriteNode(
                color: SKColor(red: 0.36, green: 0.22, blue: 0.08, alpha: 1),
                size: CGSize(width: W, height: 3))
            edge.position  = CGPoint(x: 0, y: y + sign * 1.5)
            edge.zPosition = -98
            gameWorldNode.addChild(edge)
        }

        addGrassTufts(from: -H / 2, to: riverMinY,
                      color: SKColor(red: 0.10, green: 0.24, blue: 0.07, alpha: 1))
        addGrassTufts(from: riverMaxY, to: H / 2,
                      color: SKColor(red: 0.08, green: 0.19, blue: 0.05, alpha: 1))
    }

    private func addGrassTufts(from minY: CGFloat, to maxY: CGFloat, color: SKColor) {
        let ts: CGFloat = 4
        var x = -W / 2
        while x < W / 2 {
            var y = minY
            while y < maxY {
                if Int.random(in: 0..<5) == 0 {
                    let t = SKSpriteNode(color: color, size: CGSize(width: ts, height: ts))
                    t.position  = CGPoint(x: x + ts / 2, y: y + ts / 2)
                    t.zPosition = -99
                    gameWorldNode.addChild(t)
                }
                y += ts
            }
            x += ts
        }
    }

    private func buildRiver() {
        let rH = riverMaxY - riverMinY
        let rY = (riverMinY + riverMaxY) / 2

        let river = SKSpriteNode(
            color: SKColor(red: 0.04, green: 0.16, blue: 0.40, alpha: 1),
            size: CGSize(width: W, height: rH))
        river.position  = CGPoint(x: 0, y: rY)
        river.zPosition = -101
        gameWorldNode.addChild(river)

        // Shimmer ripple tiles
        var y = riverMinY + 2
        while y < riverMaxY {
            if Int.random(in: 0..<3) == 0 {
                let w = CGFloat.random(in: 18...55)
                let ripple = SKSpriteNode(
                    color: SKColor(red: 0.07, green: 0.22, blue: 0.50, alpha: 1),
                    size: CGSize(width: w, height: 4))
                ripple.position  = CGPoint(
                    x: CGFloat.random(in: -W / 2 + w / 2...W / 2 - w / 2), y: y)
                ripple.zPosition = -100
                gameWorldNode.addChild(ripple)
            }
            y += 4
        }
    }

    private func buildBridgeGuide() {
        // Faint centre line helps the player aim
        let rH = riverMaxY - riverMinY
        let guide = SKSpriteNode(
            color: SKColor(white: 1, alpha: 0.10),
            size: CGSize(width: 2, height: rH))
        guide.position  = CGPoint(x: bridgeX, y: (riverMinY + riverMaxY) / 2)
        guide.zPosition = -95
        gameWorldNode.addChild(guide)

        // Far bank label
        let farLbl = makeLabel(text: "FAR BANK", size: min(7, W / 44),
                               color: SKColor(white: 0.50, alpha: 0.60))
        farLbl.position  = CGPoint(x: 0, y: riverMaxY + (H / 2 - riverMaxY) / 2)
        farLbl.zPosition = 5
        gameWorldNode.addChild(farLbl)
    }

    private func buildSlotMarkers() {
        for y in slotYPositions {
            let marker = SKShapeNode(circleOfRadius: 10)
            marker.strokeColor = SKColor(white: 0.55, alpha: 0.28)
            marker.fillColor   = SKColor(white: 0.20, alpha: 0.10)
            marker.lineWidth   = 1.5
            marker.position    = CGPoint(x: bridgeX, y: y)
            marker.zPosition   = -88
            gameWorldNode.addChild(marker)
        }
    }

    private func buildThrowLine() {
        let line = SKSpriteNode(
            color: SKColor(white: 1, alpha: 0.50),
            size: CGSize(width: W * 0.45, height: 1))
        line.position  = CGPoint(x: 0, y: throwLineY)
        line.zPosition = 0
        gameWorldNode.addChild(line)
    }

    private func buildAimIndicator() {
        let tex = SKTexture(imageNamed: "bag_16bit")
        tex.filteringMode = .nearest
        let bag = SKSpriteNode(texture: tex, size: CGSize(width: 36, height: 36))
        bag.color            = SKColor(red: 0.95, green: 0.76, blue: 0.12, alpha: 1)
        bag.colorBlendFactor = 0.50
        bag.position         = CGPoint(x: 0, y: throwLineY)
        bag.zPosition        = 30
        gameWorldNode.addChild(bag)
        aimIndicator = bag

        bag.run(.repeatForever(.sequence([
            .scale(to: 1.12, duration: 0.48),
            .scale(to: 0.90, duration: 0.48),
        ])))
    }

    // MARK: - UI

    private func setupUI() {
        // Bit-Wood Brawler design-system colors
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
        let dsIronGray = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1) // #595959

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat     = 48
        let panelTopY = H / 2 - topInset
        let topY      = panelTopY - topH / 2

        // Top ribbon — extends through safe area
        let totalTopH = topH + topInset
        let topBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: W, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: H / 2 - totalTopH / 2)
        topBar.zPosition = 500
        addChild(topBar)

        // 2px gold bottom border
        let border = SKSpriteNode(color: dsGold,
                                  size: CGSize(width: W, height: 2))
        border.position  = CGPoint(x: 0, y: topY - topH / 2)
        border.zPosition = 501
        addChild(border)

        // Zone A (left): pause + help
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size      = CGSize(width: 22, height: 22)
        pauseBtn.position  = CGPoint(x: -W / 2 + 22, y: topY)
        pauseBtn.zPosition = 502
        pauseBtn.name      = "pauseBtn"
        addChild(pauseBtn)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -W / 2 + 52, y: topY)
        addChild(help)

        // Zone B (center): BAGS and BRIDGE stats
        let bagsLbl = makeLabel(text: "BAGS: 12", size: 9, color: dsGold)
        bagsLbl.horizontalAlignmentMode = .right
        bagsLbl.position  = CGPoint(x: -8, y: topY)
        bagsLbl.zPosition = 502
        addChild(bagsLbl)
        bagsLabel = bagsLbl

        let progLbl = makeLabel(text: "BRIDGE: 0/8", size: 9, color: dsGold)
        progLbl.horizontalAlignmentMode = .left
        progLbl.position  = CGPoint(x: 8, y: topY)
        progLbl.zPosition = 502
        addChild(progLbl)
        progressLabel = progLbl

        // Zone C (right): close icon
        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: W / 2 - 22, y: topY)
        closeBtn.zPosition = 502
        closeBtn.name      = "closeButton"
        addChild(closeBtn)

        // Iron bolts — ribbon corners
        addIronBolt(at: CGPoint(x: -W / 2 + 5, y: topY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  W / 2 - 5, y: topY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x: -W / 2 + 5, y: topY - topH / 2 + 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  W / 2 - 5, y: topY - topH / 2 + 5), color: dsIronGray)
    }

    private func addIronBolt(at pt: CGPoint, color: SKColor) {
        let bolt = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
        bolt.position  = pt
        bolt.zPosition = 503
        addChild(bolt)
    }

    // MARK: - Tutorial

    private func presentTutorial(autoTriggered: Bool) {
        let steps: [TutorialStep] = [
            .card(title: "PIRANHA BRIDGE",
                  body:  "DROP BAGS ONTO THE PILINGS TO BUILD A BRIDGE ACROSS THE RIVER. BUILD ALL PLANKS TO ESCAPE."),
            .card(title: "AIMING",
                  body:  "DRAG FROM THE BOTTOM TO AIM. DISTANCE SETS POWER. RELEASE TO THROW."),
            .card(title: "PIRANHA TROUBLE",
                  body:  "PIRANHAS WILL SNATCH BAGS THAT MISS. YOU HAVE A LIMITED NUMBER OF BAGS — MAKE EACH ONE COUNT."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) {
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.piranha)
            }
        }
        addChild(overlay)
    }

    private func makeLabel(text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.text     = text
        l.fontSize = size
        l.fontColor = color
        l.verticalAlignmentMode = .center
        return l
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        guard !gameOver else { return }
        if isPausedGame { lastUpdateTime = currentTime; return }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = min(currentTime - lastUpdateTime, 0.05)
        lastUpdateTime = currentTime

        updateAim(dt: dt)
        if let bag = flyingBag { updateFlyingBag(bag, dt: dt) }
        updatePiranha(dt: dt)
    }

    // MARK: - Aim oscillation

    private func updateAim(dt: TimeInterval) {
        guard flyingBag == nil else { return }
        let step = CGFloat(dt) * targetSpeed
        if targetMovingRight {
            targetX += step
            if targetX >=  targetRange { targetX =  targetRange; targetMovingRight = false }
        } else {
            targetX -= step
            if targetX <= -targetRange { targetX = -targetRange; targetMovingRight = true }
        }
        aimIndicator?.position.x = targetX
    }

    // MARK: - Bag physics

    private func updateFlyingBag(_ bag: FlyingBag, dt: TimeInterval) {
        guard !bag.landed else { return }
        let s = CGFloat(dt) * 60.0

        bag.bz += bag.vz * s
        bag.vz -= gravity * s
        bag.by += bag.vy * s
        bag.bx += bag.vx * s
        bag.rot += bag.rotV * s

        let vizY = bag.by + max(0, bag.bz) * bzVisualScale
        bag.node.position  = CGPoint(x: bag.bx, y: vizY)
        bag.node.zRotation = bag.rot
        bag.node.setScale(1.0 + max(0, bag.bz) * 0.008)

        bag.shadow.position = CGPoint(x: bag.bx + max(0, bag.bz) * 0.30, y: bag.by)
        bag.shadow.alpha    = 0.30 * max(0, 1.0 - bag.bz / 40.0)

        if bag.bz <= 0 {
            bag.landed = true
            landBag(bag)
        }
    }

    private func landBag(_ bag: FlyingBag) {
        let slotIdx = bag.targetSlotIndex
        let onLine  = abs(bag.bx - bridgeX) < bridgeTolerance

        if onLine && slotIdx >= 0 && slotIdx < 8 && !slotFilled[slotIdx] {
            placeBag(at: slotIdx, from: bag)
        } else {
            missedBag(bag)
        }

        flyingBag = nil
        bagsRemaining -= 1
        updateHUD()
        checkEndCondition()
    }

    private func placeBag(at slotIdx: Int, from bag: FlyingBag) {
        slotFilled[slotIdx] = true

        bag.node.removeFromParent()
        bag.shadow.removeFromParent()

        let tex = SKTexture(imageNamed: "bag_16bit")
        tex.filteringMode = .nearest
        let placed = SKSpriteNode(texture: tex, size: CGSize(width: 36, height: 36))
        placed.color            = SKColor(red: 0.90, green: 0.28, blue: 0.28, alpha: 1)
        placed.colorBlendFactor = 0.62
        placed.position         = CGPoint(x: bridgeX, y: slotYPositions[slotIdx])
        placed.zPosition        = 15
        placed.zRotation        = .pi / 2   // laid flat like a bridge plank
        gameWorldNode.addChild(placed)
        slotBagNodes[slotIdx] = placed

        placed.setScale(0)
        placed.run(.sequence([
            .scale(to: 1.15, duration: 0.10),
            .scale(to: 1.00, duration: 0.08),
        ]))

        playSoundIfExists("bag_land.wav")
    }

    private func missedBag(_ bag: FlyingBag) {
        bag.node.run(.sequence([
            .scale(to: 0.4, duration: 0.18),
            .fadeOut(withDuration: 0.18),
            .removeFromParent(),
        ]))
        bag.shadow.run(.sequence([
            .fadeOut(withDuration: 0.20),
            .removeFromParent(),
        ]))
        showSplash(at: CGPoint(x: bag.bx, y: bag.by))
    }

    private func showSplash(at pos: CGPoint) {
        for i in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: CGFloat(i + 1) * 7)
            ring.strokeColor = SKColor(red: 0.35, green: 0.72, blue: 1.0, alpha: 0.80)
            ring.fillColor   = .clear
            ring.lineWidth   = 1.5
            ring.position    = pos
            ring.zPosition   = 25
            gameWorldNode.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(i) * 0.06),
                .group([
                    .scale(to: 2.2, duration: 0.40),
                    .fadeOut(withDuration: 0.40),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Piranha

    private func updatePiranha(dt: TimeInterval) {
        switch piranhaPhase {

        case .idle:
            piranhaIdleTimer += dt
            if piranhaIdleTimer >= piranhaIdleDelay { startPiranhaWarning() }

        case .warning:
            piranhaWarningTimer += dt
            if piranhaWarningTimer >= 1.6 { startPiranhaSwim() }

        case .swimming:
            piranhaX += piranhaVx * CGFloat(dt)
            piranhaNode?.position.x = piranhaX

            if !piranhaHasEaten && abs(piranhaX - bridgeX) < 22 {
                if let eatIdx = nearestFilledSlot(nearY: piranhaY) {
                    eatSlot(eatIdx)
                }
                piranhaHasEaten = true
            }

            let offScreen = (piranhaVx > 0 && piranhaX >  W / 2 + 70)
                         || (piranhaVx < 0 && piranhaX < -W / 2 - 70)
            if offScreen { resetPiranha() }
        }
    }

    private func nearestFilledSlot(nearY y: CGFloat) -> Int? {
        var best: Int?
        var bestDist = CGFloat(22)
        for i in 0..<8 where slotFilled[i] {
            let d = abs(slotYPositions[i] - y)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    private func startPiranhaWarning() {
        piranhaPhase        = .warning
        piranhaWarningTimer = 0
        piranhaHasEaten     = false

        // Prefer targeting a filled slot so there's always real danger
        if let slot = (0..<8).filter({ slotFilled[$0] }).randomElement() {
            piranhaY = slotYPositions[slot]
        } else {
            piranhaY = CGFloat.random(in: riverMinY + 20...riverMaxY - 20)
        }

        let fromLeft = Bool.random()
        piranhaX  = fromLeft ? -W / 2 - 55 : W / 2 + 55
        piranhaVx = fromLeft ?  W * 0.78    : -W * 0.78

        let finX: CGFloat = fromLeft ? -W / 2 + 14 : W / 2 - 14
        spawnFin(at: CGPoint(x: finX, y: piranhaY))

        playSoundIfExists("gopher_pop.wav")
    }

    private func spawnFin(at pos: CGPoint) {
        finNode?.removeFromParent()

        let fin = SKNode()
        fin.position  = pos
        fin.zPosition = 25
        gameWorldNode.addChild(fin)
        finNode = fin

        // Fin triangle
        let path = CGMutablePath()
        path.move(to:    CGPoint(x:  0, y: 14))
        path.addLine(to: CGPoint(x: -9, y: -4))
        path.addLine(to: CGPoint(x:  9, y: -4))
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor   = SKColor(red: 0.14, green: 0.60, blue: 0.42, alpha: 1)
        shape.strokeColor = SKColor(red: 0.06, green: 0.38, blue: 0.26, alpha: 1)
        shape.lineWidth   = 1.5
        fin.addChild(shape)

        // Water ripple ring around fin base
        let ripple = SKShapeNode(ellipseOf: CGSize(width: 30, height: 14))
        ripple.strokeColor = SKColor(red: 0.42, green: 0.80, blue: 1.0, alpha: 0.55)
        ripple.fillColor   = .clear
        ripple.lineWidth   = 1
        ripple.position    = CGPoint(x: 0, y: -2)
        fin.addChild(ripple)

        // Bob animation
        fin.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 5, duration: 0.28),
            .moveBy(x: 0, y: -5, duration: 0.28),
        ])))

        // "!" warning flash
        let excl = makeLabel(text: "!", size: min(18, W / 18),
                             color: SKColor(red: 1, green: 0.18, blue: 0.18, alpha: 1))
        excl.position  = CGPoint(x: pos.x > 0 ? -20 : 20, y: pos.y + 22)
        excl.zPosition = 35
        gameWorldNode.addChild(excl)
        excl.run(.sequence([
            .repeat(.sequence([
                .scale(to: 1.4, duration: 0.18),
                .scale(to: 1.0, duration: 0.18),
            ]), count: 4),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    private func startPiranhaSwim() {
        piranhaPhase = .swimming
        finNode?.removeFromParent()
        finNode = nil

        let piranha = buildPiranhaNode()
        piranha.position  = CGPoint(x: piranhaX, y: piranhaY)
        piranha.zPosition = 22
        if piranhaVx < 0 { piranha.xScale = -1 }
        gameWorldNode.addChild(piranha)
        piranhaNode = piranha

        // Tail-wiggle swim cycle
        piranha.run(.repeatForever(.sequence([
            .scaleX(to: 1.0, y: 1.08, duration: 0.09),
            .scaleX(to: 1.0, y: 0.93, duration: 0.09),
        ])))
    }

    private func buildPiranhaNode() -> SKNode {
        let n = SKNode()

        // Body
        let body = SKShapeNode(ellipseOf: CGSize(width: 52, height: 22))
        body.fillColor   = SKColor(red: 0.14, green: 0.60, blue: 0.40, alpha: 1)
        body.strokeColor = SKColor(red: 0.07, green: 0.36, blue: 0.24, alpha: 1)
        body.lineWidth   = 2
        n.addChild(body)

        // Belly stripe
        let belly = SKShapeNode(ellipseOf: CGSize(width: 36, height: 12))
        belly.fillColor   = SKColor(red: 0.82, green: 0.92, blue: 0.72, alpha: 1)
        belly.strokeColor = .clear
        belly.position    = CGPoint(x: 2, y: 0)
        n.addChild(belly)

        // Dorsal fin
        let dPath = CGMutablePath()
        dPath.move(to:    CGPoint(x: -8, y: 11))
        dPath.addLine(to: CGPoint(x:  2, y: 21))
        dPath.addLine(to: CGPoint(x: 10, y: 11))
        dPath.closeSubpath()
        let dFin = SKShapeNode(path: dPath)
        dFin.fillColor   = SKColor(red: 0.10, green: 0.48, blue: 0.30, alpha: 1)
        dFin.strokeColor = .clear
        n.addChild(dFin)

        // Mouth (faces right by default; flipped via xScale when swimming left)
        let mPath = CGMutablePath()
        mPath.move(to:    CGPoint(x: 22,  y:  5))
        mPath.addLine(to: CGPoint(x: 29,  y:  0))
        mPath.addLine(to: CGPoint(x: 22,  y: -5))
        let mouth = SKShapeNode(path: mPath)
        mouth.strokeColor = SKColor(red: 0.88, green: 0.10, blue: 0.10, alpha: 1)
        mouth.fillColor   = SKColor(red: 0.88, green: 0.10, blue: 0.10, alpha: 0.4)
        mouth.lineWidth   = 2.5
        n.addChild(mouth)

        // Eye
        let eyeW = SKShapeNode(circleOfRadius: 4)
        eyeW.fillColor   = .white
        eyeW.strokeColor = .clear
        eyeW.position    = CGPoint(x: 16, y: 5)
        n.addChild(eyeW)

        let pupil = SKShapeNode(circleOfRadius: 2)
        pupil.fillColor   = .black
        pupil.strokeColor = .clear
        pupil.position    = CGPoint(x: 17, y: 5)
        n.addChild(pupil)

        // Tail (left/back side)
        let tPath = CGMutablePath()
        tPath.move(to: CGPoint(x: -25,  y:  0))
        tPath.addLine(to: CGPoint(x: -37,  y: 12))
        tPath.move(to: CGPoint(x: -25,  y:  0))
        tPath.addLine(to: CGPoint(x: -37, y: -12))
        let tail = SKShapeNode(path: tPath)
        tail.strokeColor = SKColor(red: 0.10, green: 0.48, blue: 0.30, alpha: 1)
        tail.lineWidth   = 3
        tail.lineCap     = .round
        n.addChild(tail)

        return n
    }

    private func eatSlot(_ slotIdx: Int) {
        guard slotFilled[slotIdx], let bagNode = slotBagNodes[slotIdx] else { return }

        slotFilled[slotIdx]   = false
        slotBagNodes[slotIdx] = nil

        bagNode.run(.sequence([
            .group([
                .scale(to: 0.1, duration: 0.28),
                .fadeOut(withDuration: 0.28),
            ]),
            .removeFromParent(),
        ]))

        // Chomp burst on piranha
        piranhaNode?.run(.sequence([
            .scale(to: 1.30, duration: 0.10),
            .scale(to: 1.00, duration: 0.10),
        ]))

        playSoundIfExists("gopher_steal.wav")
        updateHUD()
        floatText("NOM!", at: CGPoint(x: bridgeX + 22, y: slotYPositions[slotIdx]))
    }

    private func resetPiranha() {
        piranhaNode?.removeFromParent(); piranhaNode = nil
        finNode?.removeFromParent();     finNode     = nil
        piranhaPhase     = .idle
        piranhaIdleTimer = 0
        piranhaIdleDelay = Double.random(in: 5.0...9.0)
    }

    // MARK: - Throw

    private func throwBag() {
        guard flyingBag == nil, !gameOver, bagsRemaining > 0 else { return }
        guard let slotIdx = nextUnfilledSlot else { return }

        let bag = FlyingBag(
            startX: targetX, startY: throwLineY,
            targetSlotIndex: slotIdx,
            targetY: slotYPositions[slotIdx],
            gravity: gravity, vzInitial: vzInitial)
        bag.rotV = (Bool.random() ? 1.0 : -1.0) * 0.05

        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        flyingBag = bag

        aimIndicator?.isHidden = true
        gameWorldNode.childNode(withName: "throwHint")?.removeFromParent()
    }

    // MARK: - HUD

    private func updateHUD() {
        bagsLabel?.text     = "BAGS: \(bagsRemaining)"
        progressLabel?.text = "BRIDGE: \(filledCount)/8"
    }

    private func floatText(_ text: String, at pos: CGPoint) {
        let lbl = makeLabel(text: text, size: min(10, W / 30),
                            color: SKColor(red: 1, green: 0.25, blue: 0.25, alpha: 1))
        lbl.position  = pos
        lbl.zPosition = 60
        gameWorldNode.addChild(lbl)
        lbl.run(.sequence([
            .group([
                .moveBy(x: 0, y: 22, duration: 0.85),
                .sequence([
                    .wait(forDuration: 0.30),
                    .fadeOut(withDuration: 0.55),
                ]),
            ]),
            .removeFromParent(),
        ]))
    }

    // MARK: - End condition

    private func checkEndCondition() {
        if bridgeComplete {
            endGame(won: true)
        } else if bagsRemaining < (8 - filledCount) {
            endGame(won: false)
        } else {
            aimIndicator?.isHidden = false
        }
    }

    private func endGame(won: Bool) {
        gameOver   = true
        gameResult = won
        aimIndicator?.isHidden = true
        flyingBag?.node.removeFromParent()
        flyingBag?.shadow.removeFromParent()
        flyingBag = nil

        if won { CornholeStatsManager.shared.recordWin()  }
        else   { CornholeStatsManager.shared.recordLoss() }

        showEndPanel(won: won)
    }

    private func showEndPanel(won: Bool) {
        let panelW = W * 0.82
        let panelH = H * 0.40

        let panel = SKNode()
        panel.zPosition = 600
        addChild(panel)

        let bg = SKSpriteNode(
            color: SKColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 0.94),
            size: CGSize(width: panelW, height: panelH))
        bg.zPosition = 0
        panel.addChild(bg)

        let bdr = SKShapeNode(rect: CGRect(
            x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH))
        bdr.strokeColor = SKColor(red: 0.50, green: 0.35, blue: 0.15, alpha: 0.80)
        bdr.fillColor   = .clear
        bdr.lineWidth   = 1.5
        bdr.zPosition   = 1
        panel.addChild(bdr)

        let titleText  = won ? "BRIDGE BUILT!" : "WASHED OUT!"
        let titleColor: SKColor = won
            ? SKColor(red: 0.35, green: 1.0, blue: 0.45, alpha: 1)
            : SKColor(red: 1.0,  green: 0.25, blue: 0.25, alpha: 1)
        let title = makeLabel(text: titleText, size: min(13, panelW / 18), color: titleColor)
        title.position  = CGPoint(x: 0, y: panelH * 0.22)
        title.zPosition = 2
        panel.addChild(title)

        let subText = won ? "YOU CROSSED THE RIVER!" : "BAGS GONE, BRIDGE BROKEN"
        let sub = makeLabel(text: subText, size: min(7, panelW / 36),
                            color: SKColor(white: 0.78, alpha: 1))
        sub.position  = CGPoint(x: 0, y: panelH * 0.05)
        sub.zPosition = 2
        panel.addChild(sub)

        let btnBg = SKSpriteNode(
            color: SKColor(red: 0.25, green: 0.18, blue: 0.08, alpha: 1),
            size: CGSize(width: 128, height: 38))
        btnBg.name      = "continueBtn"
        btnBg.position  = CGPoint(x: 0, y: -panelH * 0.24)
        btnBg.zPosition = 2
        panel.addChild(btnBg)

        let btnLbl = makeLabel(
            text: "CONTINUE",
            size: min(9, panelW / 30),
            color: SKColor(red: 0.90, green: 0.72, blue: 0.30, alpha: 1))
        btnLbl.name      = "continueBtn"
        btnLbl.position  = CGPoint(x: 0, y: -panelH * 0.24)
        btnLbl.zPosition = 3
        panel.addChild(btnLbl)

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.45))

        playSoundIfExists(won ? "game_win.wav" : "game_lose.wav")
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Tutorial overlay — any tap advances it.
        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        // HUD help button re-presents the tutorial.
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        // Pause overlay routing
        if isPausedGame {
            for n in nodes(at: loc) {
                let name = n.name ?? n.parent?.name ?? ""
                if name == "resumeBtn" { resumeGame(); return }
                if TutorialHelpButton.wasTapped(n) { presentTutorial(autoTriggered: false); return }
            }
            return
        }
        // Quit-confirm modal consumes all input until resolved.
        if confirmingQuit {
            for n in nodes(at: loc) {
                if QuitConfirmModal.isQuit(n)   { hideConfirmPanel(); dismissScene(won: false); return }
                if QuitConfirmModal.isCancel(n) { hideConfirmPanel(); return }
            }
            return
        }
        if nodes(at: loc).contains(where: { $0.name == "pauseBtn" }) { pauseGame(); return }
        if nodes(at: loc).contains(where: { $0.name == "closeButton" }) {
            if gameOver { dismissScene(won: gameResult) } else { showConfirmQuit() }
            return
        }

        if gameOver {
            let tapped = nodes(at: loc).compactMap { $0.name }.contains("continueBtn")
            if tapped { dismissScene(won: gameResult) }
            return
        }

        guard flyingBag == nil else { return }
        touchStart = loc
        aimingLine?.removeFromParent()
        let line = SKShapeNode()
        line.strokeColor = SKColor(white: 1, alpha: 0.45)
        line.lineWidth   = 1
        line.zPosition   = 400
        addChild(line)
        aimingLine = line
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let start = touchStart,
              let line  = aimingLine else { return }
        let loc  = touch.location(in: self)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: loc)
        line.path = path
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)

        aimingLine?.removeFromParent()
        aimingLine = nil

        if gameOver {
            touchStart = nil
            return
        }

        guard let start = touchStart else { return }
        touchStart = nil

        // Require an upward swipe of at least 15 pts (dy > 0 = up in SpriteKit coords)
        let dy = end.y - start.y
        guard dy > 15 else { return }

        throwBag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimingLine?.removeFromParent()
        aimingLine = nil
        touchStart = nil
    }

    // MARK: - Pause / Resume

    private func pauseGame() {
        guard !isPausedGame, !gameOver else { return }
        isPausedGame = true
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        lastUpdateTime = 0
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
    }

    private func showPauseOverlay() {
        let ov = SKNode(); ov.zPosition = 5000
        pauseOverlayNode = ov; addChild(ov)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2, width: W, height: H))
        dim.fillColor = SKColor(white: 0, alpha: 0.65); dim.strokeColor = .clear; ov.addChild(dim)

        let panelW: CGFloat = min(W - 48, 280), panelH: CGFloat = 200
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH), cornerRadius: 10)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        panel.lineWidth   = 2; ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 56); ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 8)
        resumeBg.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
        resumeBg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        resumeBg.lineWidth   = 1.5; resumeBg.position = CGPoint(x: 0, y: 6)
        resumeBg.name = "resumeBtn"; ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text = "RESUME"; resumeLbl.fontSize = 11
        resumeLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        resumeLbl.horizontalAlignmentMode = .center; resumeLbl.verticalAlignmentMode = .center
        resumeLbl.position = CGPoint(x: 0, y: -1); resumeLbl.name = "resumeBtn"; resumeBg.addChild(resumeLbl)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: 0, y: -62); ov.addChild(help)

        let helpHint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        helpHint.text = "TUTORIAL"; helpHint.fontSize = 7
        helpHint.fontColor = SKColor(white: 0.6, alpha: 0.8)
        helpHint.horizontalAlignmentMode = .center; helpHint.verticalAlignmentMode = .top
        helpHint.position = CGPoint(x: 0, y: -80); ov.addChild(helpHint)
    }

    // MARK: - Quit Confirmation

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true
        let panel = QuitConfirmModal.make(sceneSize: size)
        addChild(panel)
        confirmPanel = panel
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(won: Bool) {
        let t = SKTransition.push(with: .down, duration: 0.35)
        t.pausesOutgoingScene = false
        if let prev = previousScene { view?.presentScene(prev, transition: t) }
        onComplete?(won)
    }

    // MARK: - Helpers

    private func playSoundIfExists(_ filename: String) {
        let base = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        guard Bundle.main.url(forResource: base, withExtension: ext) != nil else { return }
        run(.playSoundFileNamed(filename, waitForCompletion: false))
    }
}
