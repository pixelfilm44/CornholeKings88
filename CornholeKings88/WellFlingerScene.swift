
import SpriteKit
import CoreMotion
import UIKit

// MARK: - WellFlingerScene (Well Dropper)
// The bag is already falling down a stone well. Tilt the phone left/right to
// nudge it past stones (which knock it sideways) and spider webs (which catch
// and stop it). A yellow beam rises from the cornhole hole at the bottom.
// 3 tries per game. Hole = 3 pts, board = 1 pt, miss/stuck = 0 pts.

final class WellFlingerScene: SKScene, SKPhysicsContactDelegate {

    // Physics categories
    private static let bagCat:    UInt32 = 1 << 0
    private static let wallCat:   UInt32 = 1 << 1
    private static let stoneCat:  UInt32 = 1 << 2
    private static let webCat:    UInt32 = 1 << 3
    private static let boardCat:  UInt32 = 1 << 4
    private static let holeCat:   UInt32 = 1 << 5
    private static let groundCat: UInt32 = 1 << 6

    // Mini-game contract
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?

    // Layout
    private var W: CGFloat = 0
    private var H: CGFloat = 0

    // World layout — bag falls from y = 0 down to ~ -shaftHeight (negative y).
    private var shaftHeight: CGFloat = 0
    private var shaftHalfW:  CGFloat = 0      // half the open shaft width
    private var bagSize:     CGFloat = 16

    // Where the cornhole board sits in world Y (negative).
    private var boardCenterY: CGFloat = 0
    private var holeLocalX:   CGFloat = 0     // local X of hole inside board container

    // Camera + world
    private var camNode: SKCameraNode!
    private var worldNode: SKNode!

    // Quit confirmation
    private var confirmingQuit = false
    private var confirmPanel: SKNode?

    // Bag
    private var bag: SKSpriteNode!
    private var bagShadow: SKSpriteNode!

    // Game state
    private enum TurnState { case falling, settling, ended }
    private var turnState: TurnState = .falling
    private var countdownActive = false   // blocks rock placement during the pre-turn countdown
    private var bagsLeft = 3
    private var score    = 0
    private var hasScoredThisTurn = false
    private let winThreshold = 3
    private var highScore = UserDefaults.standard.integer(forKey: "wellFlinger_high_v1")

    // Tilt
    private let motion = CMMotionManager()
    private var tiltX: CGFloat = 0

    // Stuck detection — if the bag stops making downward progress (wedged
    // between a rock and the wall) for longer than this many seconds while
    // falling, the round ends. We track vertical PROGRESS rather than velocity,
    // because a wedged bag often keeps jittering/spinning in place (non-zero
    // velocity) without actually descending.
    private let stuckLimit:    TimeInterval = 2.0
    private let stuckProgressEps: CGFloat   = 4   // min downward travel to count as "still falling"
    private var stuckTimer:    TimeInterval = 0
    private var stuckProgressY: CGFloat     = 0   // lowest (most negative) Y reached so far
    private var lastUpdate:    TimeInterval = 0

    // HUD
    private var scoreLbl: SKLabelNode!
    private var bagsLbl:  SKLabelNode!
    private var highLbl:  SKLabelNode!
    private var toastLbl: SKLabelNode!
    private var toastBg:  SKSpriteNode!

    // End-game panel
    private var endPanel: SKNode?

    // Setup guard
    private var hasSetup = false

    // Persistent obstacle layout (so the world doesn't change mid-turn)
    private struct ObstacleSpec { let y: CGFloat; let x: CGFloat; let r: CGFloat; let kind: Int /* 0 stone, 1 web */ }
    private var obstacleSpecs: [ObstacleSpec] = []
    private var obstacleNodes: [SKNode] = []     // built stones + webs
    private var placedRocks:   [SKNode] = []     // small rocks the player tapped down

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height

        if hasSetup { removeAllActions(); removeAllChildren() }
        hasSetup = true

        backgroundColor = SKColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)

        shaftHalfW  = W * 0.34
        shaftHeight = H * 4.5
        bagSize     = W * 0.07
        boardCenterY = -shaftHeight + H * 0.18

        physicsWorld.gravity         = CGVector(dx: 0, dy: -120)
        physicsWorld.contactDelegate = self

        camNode = SKCameraNode()
        camera = camNode
        addChild(camNode)

        worldNode = SKNode()
        addChild(worldNode)

        buildShaft()
        buildObstacles()
        buildBoardAndGround()
        buildBag()
        buildHUD()
        addCrtOverlay()

        if TutorialManager.shared.hasSeen(TutorialManager.wellFlinger) {
            startCountdown()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    override func willMove(from view: SKView) {
        motion.stopDeviceMotionUpdates()
    }

    // MARK: - Tutorial

    private func presentTutorial(autoTriggered: Bool) {
        let steps: [TutorialStep] = [
            .card(title: "WELL DROPPER",
                  body: "The bag is falling down the well. TAP anywhere to drop a rock — the bag will bounce off it!"),
            .card(title: "WATCH OUT",
                  body: "Stones knock the bag sideways. SPIDER WEBS catch the bag and end the turn."),
            .card(title: "AIM FOR THE LIGHT",
                  body: "Use rocks to redirect the bag toward the yellow beam. Hole = 3 pts, board = 1 pt. You have 3 bags!"),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            TutorialManager.shared.markSeen(TutorialManager.wellFlinger)
            if autoTriggered { self?.startCountdown() }
        }
        addChild(overlay)
    }

    // MARK: - Countdown

    /// Same 3 / 2 / 1 / SHOOT! beat used by the beach-ball mini-game. The bag
    /// stays frozen until the final beat fires startTurn().
    private func startCountdown() {
        countdownActive = true
        let gold  = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        let green = SKColor(red: 0.18, green: 0.90, blue: 0.40, alpha: 1)

        func beatLabel(text: String, color: SKColor) -> SKAction {
            return .run { [weak self] in
                guard let self else { return }
                let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
                lbl.text = text
                lbl.fontSize = min(64, self.W / 5)
                lbl.fontColor = color
                lbl.horizontalAlignmentMode = .center
                lbl.verticalAlignmentMode = .center
                lbl.position = .zero
                lbl.zPosition = 900
                lbl.setScale(0.4)
                self.camNode.addChild(lbl)
                lbl.run(.sequence([
                    .group([
                        .scale(to: 1.0, duration: 0.15),
                        .fadeIn(withDuration: 0.10),
                    ]),
                    .wait(forDuration: 0.50),
                    .group([
                        .scale(to: 1.4, duration: 0.25),
                        .fadeOut(withDuration: 0.25),
                    ]),
                    .removeFromParent(),
                ]))
            }
        }

        let beat: TimeInterval = 0.85
        run(.sequence([
            beatLabel(text: "3", color: gold),
            .wait(forDuration: beat),
            beatLabel(text: "2", color: gold),
            .wait(forDuration: beat),
            beatLabel(text: "1", color: gold),
            .wait(forDuration: beat),
            beatLabel(text: "GO", color: green),
            .wait(forDuration: 0.55),
            .run { [weak self] in
                self?.countdownActive = false
                self?.startTurn()
            },
        ]))
    }

    // MARK: - World construction

    private func buildShaft() {
        // Two brick walls running the length of the shaft.
        let wallW = W * 0.16
        let tex = makeBrickTexture(size: CGSize(width: wallW, height: H))
        let count = Int(ceil(shaftHeight / H)) + 2

        for i in 0..<count {
            let yTop = H * 0.5 - CGFloat(i) * H
            let yCenter = yTop - H / 2

            let left = SKSpriteNode(texture: tex, size: CGSize(width: wallW, height: H))
            left.position = CGPoint(x: -shaftHalfW - wallW / 2, y: yCenter)
            left.zPosition = 2
            worldNode.addChild(left)

            let right = SKSpriteNode(texture: tex, size: CGSize(width: wallW, height: H))
            right.position = CGPoint(x: shaftHalfW + wallW / 2, y: yCenter)
            right.xScale = -1
            right.zPosition = 2
            worldNode.addChild(right)
        }

        // Inner shadow strips
        let shadowW = W * 0.04
        let shadowH = shaftHeight + H
        let lShadow = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55),
                                   size: CGSize(width: shadowW, height: shadowH))
        lShadow.position = CGPoint(x: -shaftHalfW + shadowW / 2, y: -shaftHeight / 2 + H / 2)
        lShadow.zPosition = 3
        worldNode.addChild(lShadow)

        let rShadow = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55),
                                   size: CGSize(width: shadowW, height: shadowH))
        rShadow.position = CGPoint(x: shaftHalfW - shadowW / 2, y: -shaftHeight / 2 + H / 2)
        rShadow.zPosition = 3
        worldNode.addChild(rShadow)

        // Static wall bodies — solid, so the bag bounces off the brick.
        func wallBody(x: CGFloat) {
            let n = SKNode()
            n.position = CGPoint(x: x, y: -shaftHeight / 2 + H / 2)
            let body = SKPhysicsBody(rectangleOf: CGSize(width: 4, height: shaftHeight + H * 2))
            body.isDynamic           = false
            body.categoryBitMask     = Self.wallCat
            body.contactTestBitMask  = Self.bagCat
            body.collisionBitMask    = Self.bagCat
            body.restitution         = 0.35
            body.friction            = 0.5
            n.physicsBody = body
            worldNode.addChild(n)
        }
        wallBody(x: -shaftHalfW)
        wallBody(x:  shaftHalfW)

        // Faint top opening — sky band so the player sees they came from up top.
        let sky = SKSpriteNode(color: SKColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1),
                               size: CGSize(width: shaftHalfW * 2, height: H * 0.4))
        sky.position = CGPoint(x: 0, y: H * 0.5 + H * 0.2 - 2)
        sky.zPosition = 0
        worldNode.addChild(sky)
    }

    private func buildObstacles() {
        // Lay out stones along the shaft at a steady depth interval, alternating
        // sides for forced steering. Then pick exactly 2 of those slots to swap
        // out for spider webs.
        obstacleSpecs.removeAll()
        obstacleNodes.removeAll()
        let topMargin    = H * 0.40
        let bottomMargin = H * 0.55     // keep the last stretch above the board clear
        var y: CGFloat   = -topMargin
        let bottom       = boardCenterY + bottomMargin
        let spacing: CGFloat = H * 0.32

        var slots: [ObstacleSpec] = []
        var alt = false
        while y > bottom {
            let side: CGFloat = alt ? 1 : -1
            let x = side * CGFloat.random(in: shaftHalfW * 0.15 ... shaftHalfW * 0.70)
            // Stones — smaller, more uniform pebbles rather than boulders.
            let stoneR = CGFloat.random(in: shaftHalfW * 0.10 ... shaftHalfW * 0.16)
            slots.append(ObstacleSpec(y: y, x: x, r: stoneR, kind: 0))
            y -= spacing
            alt.toggle()
        }

        // Swap 2 mid-shaft slots for webs (avoid the very top and bottom).
        if slots.count >= 5 {
            let usable = Array(1 ..< slots.count - 1)
            let webIndexes = Array(usable.shuffled().prefix(3))
            for idx in webIndexes {
                let s = slots[idx]
                let webR = CGFloat.random(in: shaftHalfW * 0.28 ... shaftHalfW * 0.38)
                slots[idx] = ObstacleSpec(y: s.y, x: s.x, r: webR, kind: 1)
            }
        }
        obstacleSpecs = slots

        for spec in obstacleSpecs {
            if spec.kind == 0 { addStone(at: CGPoint(x: spec.x, y: spec.y), radius: spec.r) }
            else              { addWeb(at:   CGPoint(x: spec.x, y: spec.y), radius: spec.r) }
        }
    }

    private func addStone(at p: CGPoint, radius r: CGFloat) {
        let tex = makeStoneTexture(radius: r)
        let n = SKSpriteNode(texture: tex, size: CGSize(width: r * 2, height: r * 2))
        n.position  = p
        n.zPosition = 5
        let body = SKPhysicsBody(circleOfRadius: r * 0.92)
        body.isDynamic           = false
        body.categoryBitMask     = Self.stoneCat
        body.contactTestBitMask  = Self.bagCat
        body.collisionBitMask    = Self.bagCat
        body.restitution         = 0.55   // bouncy — knocks bag sideways
        body.friction            = 0.3
        n.physicsBody = body
        worldNode.addChild(n)
        obstacleNodes.append(n)
    }

    private func addWeb(at p: CGPoint, radius r: CGFloat) {
        let tex = makeWebTexture(radius: r)
        let n = SKSpriteNode(texture: tex, size: CGSize(width: r * 2, height: r * 2))
        n.position  = p
        n.zPosition = 6
        n.name      = "web"
        // Sensor — no physical collision; turn ends on contact.
        let body = SKPhysicsBody(circleOfRadius: r * 0.65)
        body.isDynamic           = false
        body.categoryBitMask     = Self.webCat
        body.contactTestBitMask  = Self.bagCat
        body.collisionBitMask    = 0
        n.physicsBody = body
        worldNode.addChild(n)

        // Subtle sway
        n.run(.repeatForever(.sequence([
            .rotate(byAngle:  0.06, duration: 1.4),
            .rotate(byAngle: -0.12, duration: 2.0),
            .rotate(byAngle:  0.06, duration: 1.4),
        ])))
        obstacleNodes.append(n)
    }

    private func buildBoardAndGround() {
        // Cornhole board: side-view block with a hole near the left side.
        let bw = shaftHalfW * 2 * 0.92
        let bh = bw * 0.30
        let board = SKNode()
        board.position  = CGPoint(x: 0, y: boardCenterY)
        board.zPosition = 9
        worldNode.addChild(board)

        // Wood texture
        let woodTex = makeBoardTexture(size: CGSize(width: bw, height: bh))
        let woodSprite = SKSpriteNode(texture: woodTex,
                                      size: CGSize(width: bw, height: bh))
        woodSprite.zPosition = 0
        board.addChild(woodSprite)

        // Hole geometry — left side of the board.
        holeLocalX = -bw * 0.30
        let holeR  = bh * 0.42

        // Two static chunks flanking the hole act as the surface.
        let leftLeft   = -bw / 2
        let leftRight  = holeLocalX - holeR
        let rightLeft  = holeLocalX + holeR
        let rightRight = bw / 2
        let chunkH     = bh * 0.85
        let chunkY     = -bh * 0.05

        func chunk(left: CGFloat, right: CGFloat) {
            let w = max(2, right - left)
            let cx = (left + right) / 2
            let n = SKNode()
            n.position = CGPoint(x: cx, y: chunkY)
            let body = SKPhysicsBody(rectangleOf: CGSize(width: w, height: chunkH))
            body.isDynamic           = false
            body.categoryBitMask     = Self.boardCat
            body.contactTestBitMask  = Self.bagCat
            body.collisionBitMask    = Self.bagCat
            body.restitution         = 0.1
            body.friction            = 0.7
            n.physicsBody = body
            board.addChild(n)
        }
        chunk(left: leftLeft,  right: leftRight)
        chunk(left: rightLeft, right: rightRight)

        // Hole sensor (where the bag scores 3 pts)
        let holeSensor = SKNode()
        holeSensor.position = CGPoint(x: holeLocalX, y: bh * 0.10)
        let hb = SKPhysicsBody(rectangleOf: CGSize(width: holeR * 1.6, height: bh * 0.40))
        hb.isDynamic           = false
        hb.categoryBitMask     = Self.holeCat
        hb.contactTestBitMask  = Self.bagCat
        hb.collisionBitMask    = 0
        holeSensor.physicsBody = hb
        board.addChild(holeSensor)

        // Yellow guide beam from the hole — long and pulsing.
        let beamW: CGFloat = holeR * 2.0
        let beamH: CGFloat = shaftHeight * 0.95
        let beam = SKSpriteNode(texture: makeBeamTexture(width: beamW, height: beamH),
                                size: CGSize(width: beamW, height: beamH))
        beam.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        beam.position    = CGPoint(x: holeLocalX, y: 0)
        beam.zPosition   = -1
        beam.blendMode   = .add
        beam.alpha       = 0.6
        beam.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.85, duration: 0.55),
            .fadeAlpha(to: 0.45, duration: 0.55),
        ])))
        board.addChild(beam)

        // Dirt ground below the board — solid, catches misses.
        let groundH: CGFloat = bh * 1.2
        let ground = SKSpriteNode(color: SKColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1),
                                  size: CGSize(width: shaftHalfW * 2, height: groundH))
        ground.position  = CGPoint(x: 0, y: boardCenterY - bh / 2 - groundH / 2 + 2)
        ground.zPosition = 7
        let gb = SKPhysicsBody(rectangleOf: ground.size)
        gb.isDynamic           = false
        gb.categoryBitMask     = Self.groundCat
        gb.contactTestBitMask  = Self.bagCat
        gb.collisionBitMask    = Self.bagCat
        gb.restitution         = 0
        gb.friction            = 1
        ground.physicsBody = gb
        worldNode.addChild(ground)
    }

    private func buildBag() {
        bagShadow = SKSpriteNode(color: .black,
                                 size: CGSize(width: bagSize * 1.3, height: bagSize * 0.5))
        bagShadow.alpha = 0.35
        bagShadow.zPosition = 9
        worldNode.addChild(bagShadow)

        let bagTex = SKTexture(imageNamed: "bag_16bit")
        bagTex.filteringMode = .nearest
        bag = SKSpriteNode(texture: bagTex,
                           size: CGSize(width: bagSize * 2, height: bagSize * 2))
        bag.color            = SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
        bag.colorBlendFactor = 0.65
        bag.zPosition = 10
        bag.position  = CGPoint(x: 0, y: -H * 0.15)
        worldNode.addChild(bag)

        let body = SKPhysicsBody(circleOfRadius: bagSize * 0.7)
        body.isDynamic           = false   // frozen until startTurn — keeps the bag still during tutorial + countdown
        body.affectedByGravity   = true
        body.allowsRotation      = true
        body.mass                = 0.06
        body.restitution         = 0.25
        body.friction            = 0.5
        body.linearDamping       = 0.85
        body.angularDamping      = 0.6
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask     = Self.bagCat
        body.collisionBitMask    = Self.wallCat | Self.stoneCat | Self.boardCat | Self.groundCat
        body.contactTestBitMask  = Self.wallCat | Self.stoneCat | Self.webCat
                                 | Self.boardCat | Self.holeCat | Self.groundCat
        bag.physicsBody = body
    }

    // MARK: - HUD

    private func buildHUD() {
        let font       = "PressStart2P-Regular"
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1)
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH:    CGFloat  = 48
        let totalTopH = topH + topInset
        let topBarY   = H / 2 - topInset - topH / 2

        let topBar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: H / 2 - totalTopH / 2)
        topBar.zPosition = 500
        camNode.addChild(topBar)

        let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        border.position  = CGPoint(x: 0, y: H / 2 - totalTopH)
        border.zPosition = 501
        camNode.addChild(border)

        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size      = CGSize(width: 22, height: 22)
        pauseBtn.position  = CGPoint(x: -W / 2 + 22, y: topBarY)
        pauseBtn.zPosition = 502
        pauseBtn.name      = "pauseBtn"
        camNode.addChild(pauseBtn)

        let helpBtn = TutorialHelpButton.make()
        helpBtn.position  = CGPoint(x: -W / 2 + 52, y: topBarY)
        helpBtn.zPosition = 502
        camNode.addChild(helpBtn)

        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: W / 2 - 22, y: topBarY)
        closeBtn.zPosition = 502
        closeBtn.name      = "closeButton"
        camNode.addChild(closeBtn)

        scoreLbl = SKLabelNode(fontNamed: font)
        scoreLbl.text = "0000"; scoreLbl.fontSize = 13; scoreLbl.fontColor = dsGold
        scoreLbl.horizontalAlignmentMode = .left; scoreLbl.verticalAlignmentMode = .center
        scoreLbl.position = CGPoint(x: -W / 2 + 80, y: topBarY)
        scoreLbl.zPosition = 502
        camNode.addChild(scoreLbl)

        bagsLbl = SKLabelNode(fontNamed: font)
        bagsLbl.text = "3/3"; bagsLbl.fontSize = 13
        bagsLbl.fontColor = SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1)
        bagsLbl.horizontalAlignmentMode = .center; bagsLbl.verticalAlignmentMode = .center
        bagsLbl.position = CGPoint(x: 0, y: topBarY)
        bagsLbl.zPosition = 502
        camNode.addChild(bagsLbl)

        highLbl = SKLabelNode(fontNamed: font)
        highLbl.text = String(format: "%04d", highScore); highLbl.fontSize = 13
        highLbl.fontColor = SKColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        highLbl.horizontalAlignmentMode = .right; highLbl.verticalAlignmentMode = .center
        highLbl.position = CGPoint(x: W / 2 - 44, y: topBarY)
        highLbl.zPosition = 502
        camNode.addChild(highLbl)

        // Toast
        toastBg = SKSpriteNode(color: dsGold, size: CGSize(width: W * 0.7, height: 28))
        toastBg.alpha = 0
        toastBg.zPosition = 510
        camNode.addChild(toastBg)

        toastLbl = SKLabelNode(fontNamed: font)
        toastLbl.fontSize = 11
        toastLbl.fontColor = SKColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        toastLbl.horizontalAlignmentMode = .center
        toastLbl.verticalAlignmentMode   = .center
        toastBg.addChild(toastLbl)
    }

    private func updateHUD() {
        scoreLbl.text = String(format: "%04d", score)
        bagsLbl.text  = "\(bagsLeft)/3"
        highLbl.text  = String(format: "%04d", highScore)
    }

    private func showToast(_ msg: String) {
        let topInset = view?.safeAreaInsets.top ?? 0
        toastBg.position = CGPoint(x: 0, y: H / 2 - topInset - 90)
        toastLbl.text    = msg
        toastBg.removeAllActions()
        toastBg.alpha = 1
        toastBg.setScale(1)
        toastBg.run(.sequence([
            .wait(forDuration: 1.5),
            .group([.fadeOut(withDuration: 0.3), .scale(to: 0.85, duration: 0.3)]),
        ]))
    }

    // MARK: - CRT overlay
    private func addCrtOverlay() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
            var y: CGFloat = 0
            while y < size.height { c.fill(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(white: 0, alpha: 0).cgColor,
                        UIColor(white: 0, alpha: 0.15).cgColor,
                        UIColor(white: 0, alpha: 0.60).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: cols, locations: [0, 0.55, 1.0]) {
                c.drawRadialGradient(g,
                    startCenter: CGPoint(x: size.width/2, y: size.height/2), startRadius: 0,
                    endCenter:   CGPoint(x: size.width/2, y: size.height/2),
                    endRadius:   max(size.width, size.height) * 0.72, options: [])
            }
        }
        let crt = SKSpriteNode(texture: SKTexture(image: img), size: size)
        crt.zPosition = 800
        crt.isUserInteractionEnabled = false
        camNode.addChild(crt)
    }

    // MARK: - Turn lifecycle

    private func startTurn() {
        turnState = .falling
        hasScoredThisTurn = false
        tiltX = 0
        stuckTimer = 0
        lastUpdate = 0

        // Place the bag a bit below the top of the shaft, already moving downward
        // so it feels mid-fall as soon as the scene appears.
        bag.position = CGPoint(x: CGFloat.random(in: -shaftHalfW * 0.25 ... shaftHalfW * 0.25),
                               y: -H * 0.15)
        bag.zRotation = 0
        bag.alpha = 1
        bag.setScale(1)
        bag.physicsBody?.isDynamic = true
        bag.physicsBody?.affectedByGravity = true
        bag.physicsBody?.velocity = CGVector(dx: 0, dy: -40)
        bag.physicsBody?.angularVelocity = CGFloat.random(in: -1.0...1.0)
        stuckProgressY = bag.position.y

        updateHUD()
    }

    private func endTurn(pts: Int, msg: String) {
        guard turnState != .ended else { return }
        turnState = .ended
        bagsLeft -= 1
        score += pts
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "wellFlinger_high_v1")
        }
        updateHUD()
        showToast(msg)

        // Settle the bag visually for a moment, then either next turn or game-over.
        run(.sequence([
            .wait(forDuration: 1.4),
            .run { [weak self] in
                guard let self else { return }
                if self.bagsLeft <= 0 {
                    self.showGameOver()
                } else {
                    self.startTurn()
                }
            },
        ]))
    }

    private func showGameOver() {
        turnState = .ended
        let won = score >= winThreshold

        let panel = SKNode()
        panel.zPosition = 900
        camNode.addChild(panel)
        endPanel = panel

        let bg = SKSpriteNode(color: SKColor(red: 0.07, green: 0.04, blue: 0.02, alpha: 0.95),
                              size: CGSize(width: W * 0.82, height: H * 0.42))
        bg.zPosition = 0
        panel.addChild(bg)

        let border = SKShapeNode(rect: CGRect(origin: CGPoint(x: -bg.size.width / 2, y: -bg.size.height / 2),
                                              size: bg.size))
        border.strokeColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
        border.lineWidth = 2
        border.zPosition = 1
        panel.addChild(border)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = won ? "WELL DONE!" : "GAME OVER"
        title.fontSize  = 18
        title.fontColor = won
            ? SKColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
            : SKColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1)
        title.position  = CGPoint(x: 0, y: bg.size.height * 0.30)
        title.zPosition = 2
        panel.addChild(title)

        let scoreText = SKLabelNode(fontNamed: "PressStart2P-Regular")
        scoreText.text      = "SCORE  \(score)"
        scoreText.fontSize  = 13
        scoreText.fontColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
        scoreText.position  = CGPoint(x: 0, y: bg.size.height * 0.07)
        scoreText.zPosition = 2
        panel.addChild(scoreText)

        let hint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        hint.text      = won ? "NICE AIM" : "NEED \(winThreshold) PTS TO WIN"
        hint.fontSize  = 9
        hint.fontColor = .white
        hint.position  = CGPoint(x: 0, y: -bg.size.height * 0.05)
        hint.zPosition = 2
        panel.addChild(hint)

        let again = SKLabelNode(fontNamed: "PressStart2P-Regular")
        again.text      = "PLAY AGAIN"
        again.fontSize  = 12
        again.fontColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
        again.position  = CGPoint(x: -bg.size.width * 0.22, y: -bg.size.height * 0.30)
        again.zPosition = 2
        again.name      = "again"
        panel.addChild(again)

        let quit = SKLabelNode(fontNamed: "PressStart2P-Regular")
        quit.text      = "QUIT"
        quit.fontSize  = 12
        quit.fontColor = .white
        quit.position  = CGPoint(x: bg.size.width * 0.25, y: -bg.size.height * 0.30)
        quit.zPosition = 2
        quit.name      = "quitGame"
        panel.addChild(quit)
    }

    private func resetForReplay() {
        endPanel?.removeFromParent()
        endPanel = nil
        bagsLeft = 3
        score    = 0

        // Clear any rocks the player placed and re-randomize the obstacle layout.
        clearPlacedRocks()
        obstacleNodes.forEach { $0.removeFromParent() }
        obstacleNodes.removeAll()
        buildObstacles()

        updateHUD()
        startTurn()
    }

    private func clearPlacedRocks() {
        placedRocks.forEach { $0.removeFromParent() }
        placedRocks.removeAll()
    }

    // MARK: - Tilt input

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Phone portrait: gravity.x ∈ [-1, 1] — tilt the phone left → negative.
            let raw = CGFloat(data.gravity.x)
            // Deadzone + curve so neutral hands don't drift the bag.
            let dead: CGFloat = 0.05
            let v = abs(raw) < dead ? 0 : (raw - CGFloat(sign(raw)) * dead) / (1 - dead)
            self.tiltX = max(-1, min(1, v))
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        // Apply tilt as a horizontal force while the bag is falling.
        if turnState == .falling, !hasScoredThisTurn, !countdownActive, let body = bag.physicsBody {
            // Cap fall speed so the descent never gets away from the player.
            let maxFallSpeed: CGFloat = 180
            if body.velocity.dy < -maxFallSpeed {
                body.velocity = CGVector(dx: body.velocity.dx, dy: -maxFallSpeed)
            }
            // Cap lateral speed so a rock bounce doesn't fling the bag uncontrollably.
            let maxLateral: CGFloat = 160
            if abs(body.velocity.dx) > maxLateral {
                body.velocity = CGVector(dx: maxLateral * (body.velocity.dx > 0 ? 1 : -1),
                                         dy: body.velocity.dy)
            }

            // Stuck detection: track downward PROGRESS, not velocity. A wedged
            // bag keeps spinning/jittering (non-zero velocity) but stops
            // descending — so we measure how long it's been since it last
            // dropped at least stuckProgressEps points.
            let dt = (lastUpdate == 0) ? 0 : (currentTime - lastUpdate)
            lastUpdate = currentTime
            if bag.position.y < stuckProgressY - stuckProgressEps {
                stuckProgressY = bag.position.y   // made real downward progress
                stuckTimer = 0
            } else {
                stuckTimer += dt
                if stuckTimer >= stuckLimit {
                    hasScoredThisTurn = true
                    HapticsManager.shared.warningFeedback()
                    body.isDynamic = false
                    endTurn(pts: 0, msg: "BAG STUCK!")
                }
            }
        }

        // Camera follows the bag down, but stops just above the board so the
        // final landing is fully on screen.
        let targetY = max(boardCenterY + H * 0.30, bag.position.y - H * 0.10)
        let clampedTop = -H * 0.05
        camNode.position = CGPoint(x: 0, y: min(clampedTop, targetY))

        // Update bag shadow to track world ground depth subtly
        bagShadow.position = CGPoint(x: bag.position.x, y: boardCenterY + 2)
        let depthRatio = max(0, min(1, (0 - bag.position.y) / abs(boardCenterY)))
        bagShadow.alpha = 0.15 + depthRatio * 0.35
        bagShadow.xScale = 1.0 - depthRatio * 0.4
    }

    // MARK: - Contact handling

    func didBegin(_ contact: SKPhysicsContact) {
        guard turnState == .falling, !hasScoredThisTurn else { return }

        let cats = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard cats & Self.bagCat != 0 else { return }

        if cats & Self.holeCat != 0 {
            hasScoredThisTurn = true
            HapticsManager.shared.successFeedback()
            playSound("hit.mp3")
            sinkIntoHole()
            endTurn(pts: 3, msg: "CORNHOLE! +3")
            return
        }
        if cats & Self.webCat != 0 {
            hasScoredThisTurn = true
            HapticsManager.shared.warningFeedback()
            stickToWeb(contact: contact)
            endTurn(pts: 0, msg: "STUCK IN WEB!")
            return
        }
        if cats & Self.boardCat != 0 {
            // Treat board landing as a 1-pt outcome only after the bag has come
            // to rest on it (otherwise the first bounce would end the turn).
            scheduleSettleCheck(target: .board)
            HapticsManager.shared.lightImpact()
            playSound("hit.mp3")
            return
        }
        if cats & Self.groundCat != 0 {
            scheduleSettleCheck(target: .ground)
            return
        }
        if cats & Self.stoneCat != 0 {
            HapticsManager.shared.lightImpact()
            spawnSparks(at: contact.contactPoint, color: SKColor(white: 0.85, alpha: 1), count: 5)
            return
        }
        if cats & Self.wallCat != 0 {
            HapticsManager.shared.lightImpact()
            return
        }
    }

    // Wait briefly after the bag touches the board/ground to see if it settles
    // there (rather than bouncing off and landing elsewhere). The first stable
    // contact resolves the turn.
    private enum SettleTarget { case board, ground }
    private func scheduleSettleCheck(target: SettleTarget) {
        guard turnState == .falling, !hasScoredThisTurn else { return }
        run(.sequence([
            .wait(forDuration: 0.45),
            .run { [weak self] in
                guard let self, self.turnState == .falling, !self.hasScoredThisTurn else { return }
                let v = self.bag.physicsBody?.velocity ?? .zero
                guard hypot(v.dx, v.dy) < 80 else {
                    // still bouncing — let physics keep going
                    return
                }
                self.hasScoredThisTurn = true
                switch target {
                case .board:
                    self.endTurn(pts: 1, msg: "ON THE BOARD +1")
                case .ground:
                    self.endTurn(pts: 0, msg: "MISS")
                }
            },
        ]))
    }

    private func sinkIntoHole() {
        bag.physicsBody?.isDynamic = false
        let dropY = boardCenterY - bagSize * 1.2
        bag.run(.sequence([
            .group([
                .move(to: CGPoint(x: holeLocalX, y: dropY), duration: 0.25),
                .scale(to: 0.4, duration: 0.25),
                .fadeAlpha(to: 0.0, duration: 0.25),
            ]),
        ]))
    }

    private func stickToWeb(contact: SKPhysicsContact) {
        bag.physicsBody?.velocity = .zero
        bag.physicsBody?.angularVelocity = 0
        bag.physicsBody?.isDynamic = false
        let p = contact.contactPoint
        // Snap into the web center so it reads as "caught"
        bag.run(.move(to: p, duration: 0.12))
        // Pulse the web that caught it
        if let web = (contact.bodyA.categoryBitMask == Self.webCat ? contact.bodyA.node
                                                                   : contact.bodyB.node) {
            web.run(.sequence([
                .scale(to: 1.15, duration: 0.1),
                .scale(to: 1.0,  duration: 0.15),
            ]))
        }
    }

    private func spawnSparks(at p: CGPoint, color: SKColor, count: Int) {
        for _ in 0..<count {
            let s = SKSpriteNode(color: color, size: CGSize(width: 2, height: 2))
            s.position  = p
            s.zPosition = 50
            worldNode.addChild(s)
            let dx = CGFloat.random(in: -22...22)
            let dy = CGFloat.random(in: -22...22)
            s.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.35),
                    .fadeOut(withDuration: 0.35),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func playSound(_ name: String) {
        run(.playSoundFileNamed(name, waitForCompletion: false))
    }

    // MARK: - Touch routing

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }

        // Tutorial overlay routing
        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        let locScene = t.location(in: self)

        // Quit-confirm modal consumes all input until resolved.
        if confirmingQuit {
            let locCam = t.location(in: camNode)
            for n in camNode.nodes(at: locCam) {
                if QuitConfirmModal.isQuit(n)   { hideConfirmPanel(); dismissScene(); return }
                if QuitConfirmModal.isCancel(n) { hideConfirmPanel(); return }
            }
            return
        }

        for n in nodes(at: locScene) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        // HUD lives on the camera node; query its local coordinate space.
        let locCam = t.location(in: camNode)
        for n in camNode.nodes(at: locCam) {
            switch n.name {
            case "pauseBtn":
                isPaused.toggle()
                return
            case "closeButton":
                showConfirmQuit()
                return
            default: break
            }
        }

        // End-game panel buttons
        if let panel = endPanel {
            let locPanel = t.location(in: panel)
            for n in panel.nodes(at: locPanel) {
                switch n.name {
                case "again":    resetForReplay(); return
                case "quitGame": dismissScene();   return
                default: break
                }
            }
        }

        // Tap-to-place rock — only while the bag is falling (not during countdown).
        if turnState == .falling, !countdownActive {
            placePlayerRock(at: locScene)
        }
    }

    /// Drop a small player-placed rock at the tap position. The rock acts as a
    /// regular static stone (bag bounces off it) so it can redirect the bag
    /// toward the hole. Quietly ignored if the tap is outside the shaft, too
    /// close to the bag, or below the board.
    private func placePlayerRock(at worldPos: CGPoint) {
        let inset: CGFloat = 14
        let minX = -shaftHalfW + inset
        let maxX =  shaftHalfW - inset
        var p = worldPos
        p.x = max(minX, min(maxX, p.x))

        // Don't allow placing on top of the bag — it would teleport-launch it.
        if hypot(p.x - bag.position.x, p.y - bag.position.y) < bagSize * 1.8 { return }
        // Keep rocks out of the board / ground area so they can't shield the hole.
        if p.y < boardCenterY + H * 0.10 { return }
        // Keep rocks below the top of the visible shaft (avoid the HUD area).
        if p.y > -H * 0.05 { return }

        let r = shaftHalfW * 0.09     // small, ~half the natural pebble size
        let tex = makeStoneTexture(radius: r)
        let n = SKSpriteNode(texture: tex, size: CGSize(width: r * 2, height: r * 2))
        n.color            = SKColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1)
        n.colorBlendFactor = 0.45     // warm tint so player rocks read different from wall stones
        n.position  = p
        n.zPosition = 6
        let body = SKPhysicsBody(circleOfRadius: r * 0.92)
        body.isDynamic           = false
        body.categoryBitMask     = Self.stoneCat
        body.contactTestBitMask  = Self.bagCat
        body.collisionBitMask    = Self.bagCat
        body.restitution         = 0.55
        body.friction            = 0.3
        n.physicsBody = body
        worldNode.addChild(n)
        placedRocks.append(n)

        // Pop-in feedback
        n.setScale(0)
        n.run(.scale(to: 1.0, duration: 0.10))
        HapticsManager.shared.lightImpact()
    }

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true
        let panel = QuitConfirmModal.make(sceneSize: size)
        camNode.addChild(panel)
        confirmPanel = panel
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        confirmPanel = nil
    }

    private func dismissScene() {
        motion.stopDeviceMotionUpdates()
        onComplete?(score >= winThreshold)
        if let prev = previousScene {
            view?.presentScene(prev, transition: .fade(withDuration: 0.25))
        }
    }

    // MARK: - Procedural pixel textures

    private func makeBrickTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let brickH: CGFloat = 14
            let brickW: CGFloat = 28
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                let offset = (row % 2 == 0) ? CGFloat(0) : brickW / 2
                var x: CGFloat = -offset
                while x < size.width {
                    let base: UIColor = (Int.random(in: 0..<4) == 0)
                        ? UIColor(red: 0.45, green: 0.18, blue: 0.14, alpha: 1)
                        : UIColor(red: 0.36, green: 0.14, blue: 0.10, alpha: 1)
                    c.setFillColor(base.cgColor)
                    c.fill(CGRect(x: x + 1, y: y + 1, width: brickW - 2, height: brickH - 2))
                    // Top highlight
                    c.setFillColor(UIColor(red: 0.55, green: 0.24, blue: 0.18, alpha: 1).cgColor)
                    c.fill(CGRect(x: x + 1, y: y + 1, width: brickW - 2, height: 2))
                    x += brickW
                }
                y += brickH
                row += 1
            }
            // Mortar lines
            c.setStrokeColor(UIColor(white: 0.08, alpha: 1).cgColor)
            c.setLineWidth(1)
            var ry: CGFloat = 0
            while ry < size.height {
                c.move(to: CGPoint(x: 0, y: ry))
                c.addLine(to: CGPoint(x: size.width, y: ry))
                ry += brickH
            }
            c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeStoneTexture(radius: CGFloat) -> SKTexture {
        let side = radius * 2
        let pix: CGFloat = max(2, floor(radius / 6))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            let c = ctx.cgContext
            let cx = side / 2, cy = side / 2
            var py: CGFloat = 0
            while py < side {
                var px: CGFloat = 0
                while px < side {
                    let dist = hypot(px + pix / 2 - cx, py + pix / 2 - cy)
                    if dist <= radius {
                        let shade = UIColor(white: CGFloat.random(in: 0.32...0.55), alpha: 1)
                        c.setFillColor(shade.cgColor)
                        c.fill(CGRect(x: px, y: py, width: pix, height: pix))
                    } else if dist <= radius + pix * 0.5 {
                        c.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
                        c.fill(CGRect(x: px, y: py, width: pix, height: pix))
                    }
                    px += pix
                }
                py += pix
            }
            // Top-left highlight
            c.setFillColor(UIColor(white: 0.78, alpha: 0.8).cgColor)
            c.fill(CGRect(x: cx - radius * 0.4, y: cy - radius * 0.55, width: pix * 2, height: pix * 2))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeWebTexture(radius: CGFloat) -> SKTexture {
        let side = radius * 2
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setStrokeColor(UIColor(white: 1.0, alpha: 0.7).cgColor)
            c.setLineWidth(1)
            let cx = side / 2, cy = side / 2
            let spokes = 8
            // Radial spokes
            for i in 0..<spokes {
                let a = CGFloat(i) / CGFloat(spokes) * .pi * 2
                c.move(to: CGPoint(x: cx, y: cy))
                c.addLine(to: CGPoint(x: cx + cos(a) * radius, y: cy + sin(a) * radius))
            }
            c.strokePath()
            // Concentric rings, slightly irregular
            c.setStrokeColor(UIColor(white: 1.0, alpha: 0.55).cgColor)
            for ring in 1...4 {
                let r = radius * CGFloat(ring) / 5.0
                c.beginPath()
                for i in 0...spokes {
                    let a = CGFloat(i) / CGFloat(spokes) * .pi * 2
                    let rr = r + CGFloat.random(in: -1...1)
                    let p = CGPoint(x: cx + cos(a) * rr, y: cy + sin(a) * rr)
                    if i == 0 { c.move(to: p) } else { c.addLine(to: p) }
                }
                c.strokePath()
            }
            // Center blob
            c.setFillColor(UIColor(white: 1.0, alpha: 0.85).cgColor)
            c.fillEllipse(in: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeBoardTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            // Wood base
            c.setFillColor(UIColor(red: 0.55, green: 0.32, blue: 0.12, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            // Top highlight band
            c.setFillColor(UIColor(red: 0.70, green: 0.46, blue: 0.22, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.35))
            // Grain
            c.setStrokeColor(UIColor(red: 0.32, green: 0.18, blue: 0.06, alpha: 0.5).cgColor)
            c.setLineWidth(1)
            var gy: CGFloat = size.height * 0.10
            while gy < size.height {
                c.move(to: CGPoint(x: 0, y: gy))
                c.addLine(to: CGPoint(x: size.width, y: gy))
                gy += size.height * 0.18
            }
            c.strokePath()
            // Edge
            c.setStrokeColor(UIColor(red: 0.20, green: 0.10, blue: 0.02, alpha: 1).cgColor)
            c.setLineWidth(2)
            c.stroke(CGRect(origin: .zero, size: size))

            // Pixelated hole on the left
            let pix: CGFloat = 4
            let holeR = size.height * 0.42
            let cx = size.width * 0.20
            let cy = size.height * 0.50
            var py = cy - holeR - pix * 2
            while py < cy + holeR + pix * 2 {
                var px = cx - holeR - pix * 2
                while px < cx + holeR + pix * 2 {
                    let d = hypot(px + pix / 2 - cx, py + pix / 2 - cy)
                    let r = CGRect(x: px, y: py, width: pix, height: pix)
                    if d <= holeR {
                        c.setFillColor(UIColor.black.cgColor); c.fill(r)
                    } else if d <= holeR + pix * 1.5 {
                        c.setFillColor(UIColor(red: 0.20, green: 0.10, blue: 0.02, alpha: 1).cgColor)
                        c.fill(r)
                    }
                    px += pix
                }
                py += pix
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeBeamTexture(width: CGFloat, height: CGFloat) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let cols = [
                UIColor(red: 1.0, green: 0.93, blue: 0.40, alpha: 0.95).cgColor,
                UIColor(red: 1.0, green: 0.92, blue: 0.35, alpha: 0.55).cgColor,
                UIColor(red: 1.0, green: 0.90, blue: 0.30, alpha: 0.00).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: cols, locations: [0, 0.35, 1.0]) {
                c.drawLinearGradient(g,
                    start: CGPoint(x: width / 2, y: height),
                    end:   CGPoint(x: width / 2, y: 0),
                    options: [])
            }
            let horiz = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 0.55).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: horiz, locations: [0, 0.5, 1.0]) {
                c.setBlendMode(.destinationIn)
                c.drawLinearGradient(g,
                    start: CGPoint(x: 0, y: height / 2),
                    end:   CGPoint(x: width, y: height / 2),
                    options: [])
                c.setBlendMode(.normal)
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeBagTexture(size: CGFloat) -> SKTexture {
        let s = size
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: fmt).image { ctx in
            let c = ctx.cgContext
            let pad: CGFloat = s * 0.12
            let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
            // Body
            c.setFillColor(UIColor(red: 0.88, green: 0.22, blue: 0.22, alpha: 1).cgColor)
            c.fill(rect)
            // Top band
            c.setFillColor(UIColor(red: 0.66, green: 0.10, blue: 0.10, alpha: 1).cgColor)
            c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.25))
            // Stitching highlight
            c.setStrokeColor(UIColor(white: 1, alpha: 0.4).cgColor)
            c.setLineWidth(1)
            c.stroke(rect.insetBy(dx: 2, dy: 2))
            // Border
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(2)
            c.stroke(rect)
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func sign(_ v: CGFloat) -> Int {
        v > 0 ? 1 : (v < 0 ? -1 : 0)
    }
}
