import SpriteKit
import UIKit

// MARK: - BeachBallCornholeScene
// Pool-side beachball cornhole — 2-minute blitz where player and AI fire simultaneously.
// Beachballs are bouncy: they bounce off the board surface and can collide mid-air.
// Only cornholes score (1 pt each); the player with more at the buzzer wins.

final class BeachBallCornholeScene: SKScene {

    // MARK: - Public API
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    /// True only when launched from the world map / story mode; gates prize display.
    var awardsRewards: Bool = false
    private var closeUIButton: UIButton? = nil  // unused; replaced by SK closeBtn

    // MARK: - Types

    enum BallOwner { case player, ai }

    private final class BeachBall {
        var bx, by, bz: CGFloat       // physics position; bz = height above water surface
        var vx, vy, vz: CGFloat       // per-frame velocity
        var rot: CGFloat = 0
        var rotV: CGFloat = 0
        var owner: BallOwner
        var hasScored = false
        var hasHitSurface = false      // hit water (or scored) — no more physics updates
        var boardBounces = 0           // count board bounces; after 6 add a lateral kick

        // 3-axis spin illusion: independent xScale/yScale oscillation per ball
        var spinPhX: CGFloat = 0       // phase accumulator for horizontal-axis squish
        var spinPhY: CGFloat = 0       // phase accumulator for vertical-axis squish
        var spinFrX: CGFloat = 0       // radians per frame — driven by lateral throw speed
        var spinFrY: CGFloat = 0       // radians per frame — driven by forward throw speed
        var spinAmX: CGFloat = 0       // amplitude of xScale oscillation (0 = no effect)
        var spinAmY: CGFloat = 0       // amplitude of yScale oscillation

        let node: SKSpriteNode
        let shadow: SKSpriteNode

        init(owner: BallOwner, startX: CGFloat, startY: CGFloat, texture: SKTexture) {
            self.owner = owner
            bx = startX; by = startY; bz = 3
            vx = 0; vy = 0; vz = 0

            node = SKSpriteNode(texture: texture, size: CGSize(width: 38, height: 38))
            node.zPosition = 20

            shadow = SKSpriteNode(color: .black, size: CGSize(width: 36, height: 22))
            shadow.alpha = 0.26
            shadow.zPosition = 6
        }

        var isMoving: Bool { bz > 0.15 || abs(vx) > 0.015 || abs(vy) > 0.015 }
    }

    // MARK: - Layout
    private var W: CGFloat = 0, H: CGFloat = 0
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var boardY: CGFloat = 0
    private var throwLineY: CGFloat = 0
    private var boardHalfW: CGFloat = 0
    private var boardHalfH: CGFloat = 0
    private var holeRelY: CGFloat = 0      // hole Y relative to boardY
    private var holeRadius: CGFloat = 0
    private var powerScale: CGFloat = 0

    // MARK: - Physics
    private let gravity: CGFloat = 0.38        // slightly floatier than beanbags (0.50)
    private let vzInitial: CGFloat = 15.0      // same arc height as beanbags
    private let boardRestitution: CGFloat = 0.80
    private let ballRestitution: CGFloat = 0.82
    private let bzVisualScale: CGFloat = 0.35  // flatter perspective than beanbags' 0.50

    // MARK: - Throw-target oscillation
    private var targetX: CGFloat = 0
    private var targetMovingRight = true
    private var targetRange: CGFloat = 0   // set in computeLayout
    private var targetSpeed: CGFloat = 0   // set in computeLayout

    // MARK: - Board drift
    private var boardDriftX: CGFloat = 0
    private var boardDriftVx: CGFloat = 0
    private let boardDriftMaxX: CGFloat = 50.0
    private var driftVarianceTimer: TimeInterval = 0

    // MARK: - Game state
    private var activeBalls: [BeachBall] = []
    private var playerScore = 0
    private var aiScore = 0
    private var gameOver = false
    private var timeRemaining: TimeInterval = 90.0
    private var lastUpdateTime: TimeInterval = 0

    // Per-player cooldowns (seconds)
    private var playerCooldown: TimeInterval = 0
    private var aiCooldown: TimeInterval = 0
    private let throwCooldown: TimeInterval = 2.0

    // AI scheduling
    private var aiPendingThrow = false
    private var aiThrowDelay: TimeInterval = 0
    private var aiStartX: CGFloat = 0

    // Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // MARK: - Nodes
    private var gameWorldNode: SKEffectNode!
    private var boardContainer: SKNode!
    private var playerScoreLabel: SKLabelNode?
    private var aiScoreLabel: SKLabelNode?
    private var timerLabel: SKLabelNode?
    private var cooldownBar: SKSpriteNode?
    private var cooldownBarBg: SKSpriteNode?
    private var playerBallTexture: SKTexture!
    private var aiBallTexture: SKTexture!
    private var readyIndicator: SKSpriteNode?   // ball shown at throw line when player can throw
    private var wasReady = true                 // tracks cooldown→ready transition
    private var countdownActive = true          // blocks input and AI until countdown finishes
    private var messageNode: SKNode?
    private var confirmPanel: SKNode?
    private var confirmingQuit = false

    // MARK: - Dolphin Bonus
    private var dolphinNoseNode: SKNode?
    private var dolphinNosePos: CGPoint = .zero
    private var dolphinActive = false
    private var dolphinJumping = false
    private var dolphinSpawnTimer: TimeInterval = 7.0  // first appearance after ~7s
    private var dolphinHideTimer: TimeInterval = 0
    private let dolphinNoseRadius: CGFloat = 18
    private var dolphinTexture: SKTexture?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        let red   = UIColor(red: 0.92, green: 0.15, blue: 0.15, alpha: 1)
        let blue  = UIColor(red: 0.10, green: 0.35, blue: 0.92, alpha: 1)
        let white = UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        playerBallTexture = Self.makeBeachBallTexture(diameter: 38, stripes: [red, white, red, white, red, white])
        aiBallTexture     = Self.makeBeachBallTexture(diameter: 38, stripes: [blue, white, blue, white, blue, white])
        computeLayout()
        setupGameWorld()
        setupBoard()
        setupUI()
        setupReadyIndicator()
        warmUpSounds()
        boardDriftVx = 18.0 * (Bool.random() ? 1 : -1)
        driftVarianceTimer = Double.random(in: 1.5...3.0)
        readyIndicator?.alpha = 0
        if TutorialManager.shared.hasSeen(TutorialManager.beachball) {
            startCountdown()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    private func presentTutorial(autoTriggered: Bool) {
        let steps: [TutorialStep] = [
            .card(title: "BEACH BALL",
                  body:  "TWO-MINUTE BLITZ. MOST CORNHOLES WHEN THE TIMER HITS ZERO WINS."),
            .card(title: "THROW WHEN READY",
                  body:  "SWIPE TOWARD THE BOARD TO THROW. THE COOLDOWN BAR FILLS BEFORE EACH NEW THROW."),
            .card(title: "DRIFTING BOARD",
                  body:  "THE BOARD FLOATS LEFT AND RIGHT IN THE POOL. ONLY CORNHOLES COUNT — BANK SHOTS DON'T SCORE."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self = self else { return }
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.beachball)
                self.startCountdown()
            }
        }
        addChild(overlay)
    }

    override func willMove(from view: SKView) {
        // no UIKit close button to clean up
    }

    // MARK: - Countdown

    private func startCountdown() {
        let gold = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
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
                self.addChild(lbl)
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
            beatLabel(text: "SHOOT!", color: green),
            .wait(forDuration: 0.55),
            .run { [weak self] in
                guard let self else { return }
                self.countdownActive = false
                self.showReadyIndicator()
            },
        ]))
    }

    // MARK: - Layout

    private func computeLayout() {
        boardY      = H * 0.08
        throwLineY  = -H * 0.30
        boardHalfW  = W * 0.265
        boardHalfH  = boardHalfW * 1.20
        holeRelY    = boardHalfH * 0.30
        holeRadius  = boardHalfW * 0.50

        let distToHole = abs((boardY + holeRelY) - throwLineY)
        let flightFrames = 2.0 * vzInitial / gravity
        let idealSwipe   = H * 0.38
        powerScale = distToHole / (flightFrames * idealSwipe)

        targetRange = boardHalfW * 1.20   // slightly wider than the board
        targetSpeed = W * 0.68            // world units per second
    }

    // Hole world-space position (moves with board drift)
    private var holeCenterX: CGFloat { boardDriftX }
    private var holeCenterY: CGFloat { boardY + holeRelY }

    // MARK: - Scene Setup

    private func setupGameWorld() {
        gameWorldNode = SKEffectNode()
        if let f = CIFilter(name: "CIPixellate") {
            f.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = f
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        addChild(gameWorldNode)

        // Deep pool water
        let water = SKSpriteNode(
            color: SKColor(red: 0.04, green: 0.22, blue: 0.46, alpha: 1),
            size: CGSize(width: W * 2, height: H * 2))
        water.zPosition = -200
        gameWorldNode.addChild(water)

        // Lighter shimmer layer (animated)
        let shimmer = SKSpriteNode(
            color: SKColor(red: 0.08, green: 0.38, blue: 0.65, alpha: 0.22),
            size: CGSize(width: W * 2, height: H * 2))
        shimmer.zPosition = -199
        gameWorldNode.addChild(shimmer)
        shimmer.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.08, duration: 2.0),
            .fadeAlpha(to: 0.30, duration: 2.0),
        ])))

        addPoolLanes()
        addWaveSparkles()

        // Pool coping (tiled edge) at player throw line
        let coping = SKSpriteNode(
            color: SKColor(red: 0.78, green: 0.72, blue: 0.60, alpha: 1),
            size: CGSize(width: W, height: 10))
        coping.position = CGPoint(x: 0, y: throwLineY - 6)
        coping.zPosition = 10
        gameWorldNode.addChild(coping)

        // Throw line indicator
        let tl = SKSpriteNode(
            color: SKColor(white: 1.0, alpha: 0.38),
            size: CGSize(width: boardHalfW * 1.6, height: 1))
        tl.position = CGPoint(x: 0, y: throwLineY)
        tl.zPosition = 8
        gameWorldNode.addChild(tl)

        // "THROW HERE" label below the line
        let tLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        tLabel.text = "THROW HERE"
        tLabel.fontSize = min(6, W / 60)
        tLabel.fontColor = SKColor(white: 0.7, alpha: 0.55)
        tLabel.horizontalAlignmentMode = .center
        tLabel.verticalAlignmentMode = .top
        tLabel.position = CGPoint(x: 0, y: throwLineY - 4)
        tLabel.zPosition = 9
        gameWorldNode.addChild(tLabel)
    }

    private func addPoolLanes() {
        let laneXs: [CGFloat] = [-W * 0.30, W * 0.30]
        for x in laneXs {
            let rope = SKSpriteNode(
                color: SKColor(red: 0.80, green: 0.22, blue: 0.08, alpha: 0.50),
                size: CGSize(width: 2, height: H * 1.6))
            rope.position = CGPoint(x: x, y: 0)
            rope.zPosition = -195
            gameWorldNode.addChild(rope)

            var fy: CGFloat = -H * 0.7
            while fy < H * 0.8 {
                let float = SKSpriteNode(
                    color: SKColor(red: 0.90, green: 0.88, blue: 0.82, alpha: 0.65),
                    size: CGSize(width: 6, height: 6))
                float.position = CGPoint(x: x, y: fy)
                float.zPosition = -194
                gameWorldNode.addChild(float)
                fy += 24
            }
        }
    }

    private func addWaveSparkles() {
        for _ in 0..<22 {
            let sparkle = SKSpriteNode(
                color: SKColor(white: 1.0, alpha: CGFloat.random(in: 0.05...0.14)),
                size: CGSize(width: CGFloat.random(in: 10...28), height: 1))
            sparkle.position = CGPoint(
                x: CGFloat.random(in: -W * 0.42...W * 0.42),
                y: CGFloat.random(in: -H * 0.44...H * 0.40))
            sparkle.zPosition = -193
            gameWorldNode.addChild(sparkle)
            let delay = Double.random(in: 0...4.0)
            sparkle.run(.repeatForever(.sequence([
                .wait(forDuration: delay),
                .fadeAlpha(to: CGFloat.random(in: 0.18...0.30), duration: 0.9),
                .fadeAlpha(to: 0.02, duration: 0.9),
            ])))
        }
    }

    private func setupBoard() {
        boardContainer = SKNode()
        boardContainer.position = CGPoint(x: boardDriftX, y: boardY)
        boardContainer.zPosition = 5
        boardContainer.setScale(0.90)
        gameWorldNode.addChild(boardContainer)

        let bw = boardHalfW * 2
        let bh = boardHalfH * 2

        // Pool-shadow beneath the floating board
        let shadowNode = SKSpriteNode(
            color: SKColor(red: 0.01, green: 0.08, blue: 0.20, alpha: 0.50),
            size: CGSize(width: bw + 8, height: bh + 8))
        shadowNode.alpha = 0.55
        shadowNode.position = CGPoint(x: 4, y: -5)
        shadowNode.zPosition = -1
        boardContainer.addChild(shadowNode)

        // Board surface — reused board_16bit asset with a pool-float tint
        let boardTex = SKTexture(imageNamed: "board_16bit")
        boardTex.filteringMode = .nearest
        let surface = SKSpriteNode(texture: boardTex, size: CGSize(width: bw, height: bh))
        surface.color = SKColor(red: 0.55, green: 0.85, blue: 0.98, alpha: 1)
        surface.colorBlendFactor = 0.28
        surface.zPosition = 0
        boardContainer.addChild(surface)

        // Hole — dark water-blue instead of earth tone
        let holeTex = makePixelCircleTexture(
            radius:    holeRadius,
            fill:      UIColor(red: 0.02, green: 0.10, blue: 0.24, alpha: 1),
            border:    UIColor(red: 0.04, green: 0.18, blue: 0.38, alpha: 1),
            pixelSize: 3)
        let hole = SKSpriteNode(texture: holeTex,
                                size: CGSize(width: holeRadius * 2, height: holeRadius * 2))
        hole.position = CGPoint(x: 0, y: holeRelY)
        hole.zPosition = 2
        boardContainer.addChild(hole)

        // Visual bob — board gently rocks on the water
        boardContainer.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 1.6),
            .moveBy(x: 0, y: -2, duration: 1.6),
        ])))
    }

    // MARK: - UI

    private func setupUI() {
        // Bit-Wood Brawler design-system colors
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
        let dsTimerBlue = SKColor(red: 0.353, green: 0.612, blue: 0.831, alpha: 1) // #5a9cd4
        let dsIronGray = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1) // #595959

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let botH: CGFloat = max(40, H * 0.07)
        let panelTopY = H / 2 - topInset
        let topBarY   = panelTopY - topH / 2
        let botBarY   = -H / 2 + botH / 2

        // ── Top HUD ribbon ────────────────────────────────────────────────
        let totalTopH = topH + topInset
        let topBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: W, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: H / 2 - totalTopH / 2)
        topBar.zPosition = 500
        addChild(topBar)

        let topBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: W, height: 2))
        topBorder.position  = CGPoint(x: 0, y: topBarY - topH / 2)
        topBorder.zPosition = 501
        addChild(topBorder)

        // Zone A (left): pause icon + help button
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size      = CGSize(width: 22, height: 22)
        pauseBtn.position  = CGPoint(x: -W / 2 + 22, y: topBarY)
        pauseBtn.zPosition = 502
        pauseBtn.name      = "pauseBtn"
        addChild(pauseBtn)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -W / 2 + 52, y: topBarY)
        addChild(help)

        // Zone B (center): YOU score | timer chip | BOT score
        let pLabel = makeLabel(text: "YOU: 0", size: 8,
                               color: SKColor(red: 0.97, green: 0.42, blue: 0.22, alpha: 1))
        pLabel.horizontalAlignmentMode = .right
        pLabel.position  = CGPoint(x: -38, y: topBarY)
        pLabel.zPosition = 502
        addChild(pLabel)
        playerScoreLabel = pLabel

        // Timer chip — gold-bordered box in the center
        let timerChipW: CGFloat = 60
        let timerChipH: CGFloat = 28
        let timerBg = SKSpriteNode(color: SKColor(red: 0.04, green: 0.02, blue: 0.01, alpha: 1),
                                   size: CGSize(width: timerChipW, height: timerChipH))
        timerBg.position  = CGPoint(x: 0, y: topBarY)
        timerBg.zPosition = 501
        addChild(timerBg)
        // 2px gold border strips around timer chip
        for (dx, sz) in [(CGFloat(0), CGSize(width: timerChipW, height: 2)),
                         (CGFloat(0), CGSize(width: timerChipW, height: 2)),
                         (CGFloat(-timerChipW / 2), CGSize(width: 2, height: timerChipH)),
                         (CGFloat( timerChipW / 2), CGSize(width: 2, height: timerChipH))] {
            let strip = SKSpriteNode(color: dsGold, size: sz)
            let dy: CGFloat = sz.height == 2
                ? (dx == 0 && strip.position == .zero ? timerChipH / 2 : -timerChipH / 2)
                : 0
            _ = dy
            strip.zPosition = 502
            timerBg.addChild(strip)
        }
        // Simpler: four border lines
        timerBg.removeAllChildren()
        let tTop = SKSpriteNode(color: dsGold, size: CGSize(width: timerChipW, height: 2))
        tTop.position = CGPoint(x: 0, y: timerChipH / 2 - 1); tTop.zPosition = 1; timerBg.addChild(tTop)
        let tBot = SKSpriteNode(color: dsGold, size: CGSize(width: timerChipW, height: 2))
        tBot.position = CGPoint(x: 0, y: -timerChipH / 2 + 1); tBot.zPosition = 1; timerBg.addChild(tBot)
        let tLeft = SKSpriteNode(color: dsGold, size: CGSize(width: 2, height: timerChipH))
        tLeft.position = CGPoint(x: -timerChipW / 2 + 1, y: 0); tLeft.zPosition = 1; timerBg.addChild(tLeft)
        let tRight = SKSpriteNode(color: dsGold, size: CGSize(width: 2, height: timerChipH))
        tRight.position = CGPoint(x: timerChipW / 2 - 1, y: 0); tRight.zPosition = 1; timerBg.addChild(tRight)

        let tl = makeLabel(text: "1:30", size: 11, color: dsTimerBlue)
        tl.horizontalAlignmentMode = .center
        tl.position  = CGPoint(x: 0, y: topBarY)
        tl.zPosition = 503
        addChild(tl)
        timerLabel = tl

        let aLabel = makeLabel(text: "BOT: 0", size: 8,
                               color: SKColor(red: 0.28, green: 0.75, blue: 1.00, alpha: 1))
        aLabel.horizontalAlignmentMode = .left
        aLabel.position  = CGPoint(x: 38, y: topBarY)
        aLabel.zPosition = 502
        addChild(aLabel)
        aiScoreLabel = aLabel

        // Zone C (right): close icon
        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: W / 2 - 22, y: topBarY)
        closeBtn.zPosition = 502
        closeBtn.name      = "closeButton"
        addChild(closeBtn)

        // Iron bolts — corners of the visible ribbon
        addIronBolt(at: CGPoint(x: -W / 2 + 5, y: topBarY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  W / 2 - 5, y: topBarY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x: -W / 2 + 5, y: topBarY - topH / 2 + 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  W / 2 - 5, y: topBarY - topH / 2 + 5), color: dsIronGray)

        // ── Bottom bar ────────────────────────────────────────────────────
        let botBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: W, height: botH))
        botBar.position  = CGPoint(x: 0, y: botBarY)
        botBar.zPosition = 500
        addChild(botBar)

        let botBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: W, height: 2))
        botBorder.position  = CGPoint(x: 0, y: botBarY + botH / 2)
        botBorder.zPosition = 501
        addChild(botBorder)

        // Cooldown bar (shows when player can throw again)
        let barW = min(W * 0.52, 170)
        let barH: CGFloat = 7

        let barBg = SKSpriteNode(color: dsIronGray,
                                 size: CGSize(width: barW, height: barH))
        barBg.position  = CGPoint(x: 0, y: botBarY + 6)
        barBg.zPosition = 601
        addChild(barBg)
        cooldownBarBg = barBg

        let bar = SKSpriteNode(color: SKColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1),
                               size: CGSize(width: barW, height: barH))
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position    = CGPoint(x: -barW / 2, y: botBarY + 6)
        bar.zPosition   = 602
        addChild(bar)
        cooldownBar = bar

        let readyLbl = makeLabel(text: "READY", size: 5, color: dsGold)
        readyLbl.horizontalAlignmentMode = .center
        readyLbl.position  = CGPoint(x: 0, y: botBarY - 6)
        readyLbl.zPosition = 601
        addChild(readyLbl)

        // Iron bolts — bottom corners
        addIronBolt(at: CGPoint(x: -W / 2 + 5, y: botBarY + botH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  W / 2 - 5, y: botBarY + botH / 2 - 5), color: dsIronGray)

        addCrtOverlay()
    }

    private func addIronBolt(at pt: CGPoint, color: SKColor) {
        let bolt = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
        bolt.position  = pt
        bolt.zPosition = 503
        addChild(bolt)
    }

    private func makeLabel(text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = text
        lbl.fontSize = size
        lbl.fontColor = color
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        return lbl
    }

    // MARK: - CRT overlay

    private func addCrtOverlay() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: W, height: H))
            c.setFillColor(UIColor(white: 0, alpha: 0.20).cgColor)
            var y: CGFloat = 0
            while y < H { c.fill(CGRect(x: 0, y: y, width: W, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(white: 0, alpha: 0.0).cgColor,
                        UIColor(white: 0, alpha: 0.14).cgColor,
                        UIColor(white: 0, alpha: 0.58).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: cols, locations: [0, 0.55, 1.0]) {
                c.drawRadialGradient(g,
                    startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                    endCenter:   CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.72,
                    options: [])
            }
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: W, height: H))
        overlay.position = .zero
        overlay.zPosition = 998
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Beachball Texture

    static func makeBeachBallTexture(diameter: CGFloat, stripes: [UIColor]) -> SKTexture {
        let sz = CGSize(width: diameter, height: diameter)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: sz, format: fmt).image { ctx in
            let c = ctx.cgContext
            let cx = diameter / 2, cy = diameter / 2
            let r  = diameter / 2 - 1.5

            let circlePath = UIBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5,
                                                          width: diameter - 3,
                                                          height: diameter - 3))
            c.addPath(circlePath.cgPath); c.clip()

            let sliceAngle = (2.0 * .pi) / CGFloat(stripes.count)
            for (i, color) in stripes.enumerated() {
                c.setFillColor(color.cgColor)
                let startA = CGFloat(i) * sliceAngle - .pi / 2
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cx, y: cy))
                path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                            startAngle: startA, endAngle: startA + sliceAngle, clockwise: false)
                path.closeSubpath()
                c.addPath(path); c.fillPath()
            }

            // Subtle dark outline on each stripe boundary
            c.setStrokeColor(UIColor(white: 0, alpha: 0.12).cgColor)
            c.setLineWidth(0.8)
            for i in 0..<stripes.count {
                let a = CGFloat(i) * sliceAngle - .pi / 2
                c.move(to: CGPoint(x: cx, y: cy))
                c.addLine(to: CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
                c.strokePath()
            }

            // White center hub
            c.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))

            // Specular highlight
            c.setFillColor(UIColor(white: 1.0, alpha: 0.28).cgColor)
            c.fillEllipse(in: CGRect(x: cx - r * 0.38, y: cy + r * 0.20,
                                      width: r * 0.50, height: r * 0.32))
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - Ready Indicator

    private func setupReadyIndicator() {
        let indicator = SKSpriteNode(texture: playerBallTexture,
                                     size: CGSize(width: 38, height: 38))
        indicator.position = CGPoint(x: targetX, y: throwLineY + 22)
        indicator.zPosition = 15
        indicator.alpha = 1.0
        gameWorldNode.addChild(indicator)
        readyIndicator = indicator
    }

    private func hideReadyIndicator() {
        readyIndicator?.run(.fadeOut(withDuration: 0.08))
    }

    private func showReadyIndicator() {
        guard let ind = readyIndicator else { return }
        ind.removeAllActions()
        ind.alpha = 1.0
        ind.run(.sequence([
            .group([
                .scale(to: 1.15, duration: 0.14),
                .fadeIn(withDuration: 0.10),
            ]),
            .scale(to: 1.0, duration: 0.08),
        ]))
    }

    private func updateThrowTarget(dt: CGFloat) {
        let step = targetSpeed * dt
        if targetMovingRight {
            targetX += step
            if targetX >= targetRange { targetX = targetRange; targetMovingRight = false }
        } else {
            targetX -= step
            if targetX <= -targetRange { targetX = -targetRange; targetMovingRight = true }
        }
        readyIndicator?.position.x = targetX
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        if isPausedGame { lastUpdateTime = currentTime; return }
        let fixedDt: CGFloat = 1.0 / 60.0

        if lastUpdateTime == 0 { lastUpdateTime = currentTime; return }
        let realDt = min(0.1, currentTime - lastUpdateTime)
        lastUpdateTime = currentTime

        guard !gameOver, !countdownActive else { return }

        // Count down
        timeRemaining = max(0, timeRemaining - realDt)
        updateTimerLabel()
        if timeRemaining <= 0 { endGame(); return }

        // Cooldowns
        playerCooldown = max(0, playerCooldown - realDt)
        aiCooldown     = max(0, aiCooldown     - realDt)
        updateCooldownBar()

        // AI pending throw
        if aiPendingThrow {
            aiThrowDelay -= realDt
            if aiThrowDelay <= 0 { aiPendingThrow = false; executeAIThrow() }
        }

        // AI autonomous cadence — fires roughly every 2s even if player doesn't throw
        if !aiPendingThrow && aiCooldown <= 0 && !gameOver {
            aiPendingThrow = true
            aiThrowDelay   = Double.random(in: 0.1...0.8)
            aiStartX       = CGFloat.random(in: -boardHalfW * 0.45...boardHalfW * 0.45)
        }

        // Throw-target oscillation — only moves when player is ready to throw
        if playerCooldown <= 0 { updateThrowTarget(dt: CGFloat(realDt)) }

        // Board drift
        updateBoardDrift(dt: CGFloat(realDt))

        // Ball physics (iterate by index so we can safely read count)
        for i in 0..<activeBalls.count {
            let ball = activeBalls[i]
            guard !ball.hasHitSurface else { continue }
            updateBallPhysics(ball, dt: fixedDt)
        }

        resolveBallCollisions()
        updateDolphin(dt: realDt)
    }

    // MARK: - Board Drift

    private func updateBoardDrift(dt: CGFloat) {
        driftVarianceTimer -= Double(dt)
        if driftVarianceTimer <= 0 {
            let base: CGFloat = 16.0
            let mult = CGFloat.random(in: 0.5...2.0)
            let sign: CGFloat = Double.random(in: 0...1) < 0.30 ? -1 : (boardDriftVx < 0 ? -1 : 1)
            boardDriftVx = sign * base * mult
            driftVarianceTimer = Double.random(in: 1.2...3.8)
        }

        boardDriftX += boardDriftVx * dt

        if boardDriftX >  boardDriftMaxX { boardDriftX =  boardDriftMaxX; boardDriftVx = -abs(boardDriftVx) }
        if boardDriftX < -boardDriftMaxX { boardDriftX = -boardDriftMaxX; boardDriftVx =  abs(boardDriftVx) }

        boardContainer.position.x = boardDriftX
    }

    // MARK: - Ball Physics

    private func updateBallPhysics(_ ball: BeachBall, dt: CGFloat) {
        ball.vz -= gravity
        ball.bx += ball.vx
        ball.by += ball.vy
        ball.bz += ball.vz

        ball.rot    += ball.rotV
        ball.spinPhX += ball.spinFrX
        ball.spinPhY += ball.spinFrY
        ball.node.zRotation = ball.rot

        if ball.bz <= 0 {
            ball.bz = 0
            handleBallGrounding(ball)
        }

        // Render: use a shallower bz perspective so arcs stay on-screen
        let visualY = ball.by + ball.bz * bzVisualScale
        ball.node.position   = CGPoint(x: ball.bx, y: visualY)
        ball.shadow.position = CGPoint(x: ball.bx + ball.bz * 0.06, y: ball.by)

        let heightScale = 1.0 + ball.bz * 0.008
        ball.node.setScale(heightScale)

        ball.shadow.alpha   = max(0.04, 0.26 - ball.bz * 0.004)
        ball.shadow.setScale(max(0.38, 1.0 - ball.bz * 0.004))
        ball.node.zPosition = 20 + ball.bz * 0.1 - ball.by * 0.02
    }

    private func handleBallGrounding(_ ball: BeachBall) {
        let dx = ball.bx - holeCenterX
        let dy = ball.by - holeCenterY
        if !ball.hasScored && sqrt(dx * dx + dy * dy) <= holeRadius {
            scoreBall(ball)
            return
        }

        if checkIsOnBoard(ball) {
            // Bounce — beachballs never land, they always bounce off
            ball.vz = abs(ball.vz) * boardRestitution
            ball.bz = 0.5
            ball.vx *= 0.88
            ball.vy *= 0.86
            ball.rotV *= 0.75
            // Bounce jolts the spin axes — reverse one or both frequencies randomly
            if Bool.random() { ball.spinFrX *= -1 }
            if Bool.random() { ball.spinFrY *= -1 }
            ball.boardBounces += 1

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            run(.playSoundFileNamed("bag_land.wav", waitForCompletion: false))

            // After several bounces with little bounce energy, push ball off the board
            if ball.boardBounces >= 6 || abs(ball.vz) < 0.5 {
                let pushAngle = CGFloat.random(in: 0...(2 * .pi))
                ball.vx += cos(pushAngle) * 1.5
                ball.vy += sin(pushAngle) * 1.5
                if abs(ball.vz) < 0.5 { ball.vz = 2.0 }  // small lift so it travels
            }

        } else {
            // Hit water — splash and fade
            ball.hasHitSurface = true
            spawnSplash(at: CGPoint(x: ball.bx, y: ball.by))
            ball.node.run(.sequence([
                .group([
                    .scale(to: 0.35, duration: 0.22),
                    .fadeOut(withDuration: 0.22),
                ]),
                .removeFromParent(),
            ]))
            ball.shadow.run(.sequence([
                .fadeOut(withDuration: 0.14),
                .removeFromParent(),
            ]))
            run(.sequence([
                .wait(forDuration: 0.4),
                .run { [weak self, weak ball] in
                    guard let self, let ball else { return }
                    self.activeBalls.removeAll { $0 === ball }
                },
            ]))
        }
    }

    private func scoreBall(_ ball: BeachBall) {
        ball.hasScored = true
        ball.hasHitSurface = true

        if ball.owner == .player {
            playerScore += 1
            playerScoreLabel?.text = "YOU: \(playerScore)"
        } else {
            aiScore += 1
            aiScoreLabel?.text = "BOT: \(aiScore)"
        }

        CornholeStatsManager.shared.recordCornhole()
        showHoleEffect(at: CGPoint(x: ball.bx, y: ball.by))

        ball.node.run(.sequence([
            .group([
                .scale(to: 0.30, duration: 0.22),
                .fadeOut(withDuration: 0.22),
            ]),
            .removeFromParent(),
        ]))
        ball.shadow.run(.sequence([
            .fadeOut(withDuration: 0.14),
            .removeFromParent(),
        ]))
        run(.sequence([
            .wait(forDuration: 0.4),
            .run { [weak self, weak ball] in
                guard let self, let ball else { return }
                self.activeBalls.removeAll { $0 === ball }
            },
        ]))
    }

    private func checkIsOnBoard(_ ball: BeachBall) -> Bool {
        let localX = ball.bx - boardDriftX
        let localY = ball.by - boardY
        return abs(localX) <= boardHalfW * 0.95 &&
               localY >= -boardHalfH * 0.95 &&
               localY <=  boardHalfH * 0.95
    }

    // MARK: - Dolphin Bonus

    private func updateDolphin(dt: TimeInterval) {
        if dolphinJumping { return }
        if dolphinActive {
            dolphinHideTimer -= dt
            if dolphinHideTimer <= 0 {
                hideDolphinNose()
                dolphinSpawnTimer = Double.random(in: 8.0...14.0)
            } else {
                checkDolphinCollision()
            }
        } else {
            dolphinSpawnTimer -= dt
            if dolphinSpawnTimer <= 0 { spawnDolphinNose() }
        }
    }

    private func spawnDolphinNose() {
        // Spawn on whichever side of the board has more clearance. Use a larger inset
        // (55–85 px) so the nose lands well inside the CRT vignette dark zone at screen edges.
        let leftRoom  = abs((-W / 2) - (boardDriftX - boardHalfW))
        let rightRoom = abs(( W / 2) - (boardDriftX + boardHalfW))
        let side: CGFloat = leftRoom > rightRoom ? -1 : 1
        let edgeInset = CGFloat.random(in: 55...85)
        var spawnX = side > 0 ? (W / 2 - edgeInset) : (-W / 2 + edgeInset)
        let boardClear: CGFloat = 28
        if side > 0 {
            spawnX = max(spawnX, boardDriftX + boardHalfW + boardClear)
        } else {
            spawnX = min(spawnX, boardDriftX - boardHalfW - boardClear)
        }
        // Clamp so the sprite is never further than 90 px from screen edge (avoids vignette)
        let maxInset = W / 2 - 55
        spawnX = max(-maxInset, min(maxInset, spawnX))
        let pos = CGPoint(x: spawnX,
                          y: boardY + CGFloat.random(in: -boardHalfH * 0.25...boardHalfH * 0.25))
        dolphinNosePos = pos

        let nose = SKNode()
        nose.position = pos
        nose.zPosition = 20    // above balls so nothing occludes it

        // ── Pulsing teal glow behind the snout — high contrast vs dark blue water ──
        let glow = SKShapeNode(circleOfRadius: 36)
        glow.fillColor   = SKColor(red: 0.10, green: 0.65, blue: 0.90, alpha: 0.20)
        glow.strokeColor = SKColor(red: 0.30, green: 0.90, blue: 1.00, alpha: 0.70)
        glow.lineWidth   = 3
        glow.zPosition   = -1
        glow.run(.repeatForever(.sequence([
            .group([.scale(to: 1.25, duration: 0.40), .fadeAlpha(to: 0.90, duration: 0.40)]),
            .group([.scale(to: 0.90, duration: 0.40), .fadeAlpha(to: 0.50, duration: 0.40)]),
        ])))
        nose.addChild(glow)

        // ── Snout sprite ──
        let snout = SKSpriteNode(texture: makeDolphinNoseTexture(),
                                 size: CGSize(width: 44, height: 44))
        snout.zPosition = 1
        // Beak points toward board center: flip when on right side so it faces left.
        snout.xScale = (side > 0) ? -1 : 1
        nose.addChild(snout)

        // ── Splash rings expanding from the waterline ──
        for i in 0..<3 {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 38, height: 12))
            ring.strokeColor = SKColor(red: 0.50, green: 0.90, blue: 1.0, alpha: 0.70)
            ring.lineWidth = 1.5
            ring.fillColor = .clear
            ring.position = CGPoint(x: 0, y: -10)
            ring.zPosition = 0
            ring.alpha = 0
            nose.addChild(ring)
            ring.run(.repeatForever(.sequence([
                .wait(forDuration: Double(i) * 0.45),
                .group([
                    .sequence([.fadeAlpha(to: 0.75, duration: 0.5),
                               .fadeAlpha(to: 0.0, duration: 0.55)]),
                    .scale(to: 1.8, duration: 1.05),
                ]),
                .scale(to: 1.0, duration: 0),
            ])))
        }

        // ── Gentle bob animation ──
        snout.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 0.40),
            .moveBy(x: 0, y: -2, duration: 0.40),
        ])))

        // ── "★ DOLPHIN" hint label — fades after 1.5 s ──
        let hint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        hint.text      = "★ DOLPHIN"
        hint.fontSize  = min(8, W / 44)
        hint.fontColor = SKColor(red: 0.40, green: 0.95, blue: 1.00, alpha: 1)
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode   = .center
        hint.position  = CGPoint(x: 0, y: 28)
        hint.zPosition = 5
        nose.addChild(hint)
        hint.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 1.0),
            .group([.fadeOut(withDuration: 0.40), .moveBy(x: 0, y: 8, duration: 0.40)]),
            .removeFromParent(),
        ]))

        // ── Entry pop ──
        nose.setScale(0.35); nose.alpha = 0
        nose.run(.group([
            .scale(to: 1.0, duration: 0.22),
            .fadeIn(withDuration: 0.22),
        ]))

        gameWorldNode.addChild(nose)
        dolphinNoseNode = nose
        dolphinActive = true
        dolphinHideTimer = Double.random(in: 5.0...7.0)
    }

    private func hideDolphinNose() {
        dolphinActive = false
        guard let nose = dolphinNoseNode else { return }
        dolphinNoseNode = nil
        nose.run(.sequence([
            .group([
                .fadeOut(withDuration: 0.25),
                .scale(to: 0.5, duration: 0.25),
            ]),
            .removeFromParent(),
        ]))
    }

    private func checkDolphinCollision() {
        guard dolphinActive, !dolphinJumping else { return }
        // Balls fly in an arc and are rendered at a visual height (by + bz * bzVisualScale),
        // so compare the ball's ON-SCREEN position to the dolphin head, not its ground
        // position. Use a generous radius (nose + ball) so hitting NEAR the dolphin counts.
        let ballRadius: CGFloat = 19.0
        let hitRadius = dolphinNoseRadius + ballRadius
        for ball in activeBalls {
            if ball.hasHitSurface || ball.hasScored { continue }
            let visualY = ball.by + ball.bz * bzVisualScale
            let dx = ball.bx - dolphinNosePos.x
            let dy = visualY - dolphinNosePos.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                triggerDolphinJump(forOwner: ball.owner, hitBall: ball)
                return
            }
        }
    }

    private func triggerDolphinJump(forOwner owner: BallOwner, hitBall: BeachBall) {
        dolphinJumping = true

        // Sink the ball that hit the nose — it splashed into the dolphin's domain
        hitBall.hasHitSurface = true
        spawnSplash(at: CGPoint(x: hitBall.bx, y: hitBall.by))
        hitBall.node.run(.sequence([
            .group([.scale(to: 0.35, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
        hitBall.shadow.run(.sequence([.fadeOut(withDuration: 0.14), .removeFromParent()]))
        run(.sequence([
            .wait(forDuration: 0.3),
            .run { [weak self, weak hitBall] in
                guard let self, let hitBall else { return }
                self.activeBalls.removeAll { $0 === hitBall }
            },
        ]))

        // Hide the snout — the dolphin is launching now
        if let nose = dolphinNoseNode {
            dolphinNoseNode = nil
            nose.removeFromParent()
        }
        dolphinActive = false

        // Build the dolphin sprite and arc it through the hole
        let dolphin = SKSpriteNode(texture: makeDolphinTexture(),
                                   size: CGSize(width: 88, height: 46))
        dolphin.zPosition = 60
        let startPos = dolphinNosePos
        let endPos   = CGPoint(x: holeCenterX, y: holeCenterY)
        let arcHeight: CGFloat = 110
        let duration: TimeInterval = 0.75
        let initialFacingLeft = endPos.x < startPos.x
        dolphin.xScale = initialFacingLeft ? -1 : 1
        dolphin.position = startPos
        gameWorldNode.addChild(dolphin)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        run(.playSoundFileNamed("bag_land.wav", waitForCompletion: false))

        let arc = SKAction.customAction(withDuration: duration) { node, elapsed in
            let p = max(0, min(1, CGFloat(elapsed) / CGFloat(duration)))
            let x = startPos.x + (endPos.x - startPos.x) * p
            let baseY = startPos.y + (endPos.y - startPos.y) * p
            let y = baseY + sin(.pi * p) * arcHeight
            node.position = CGPoint(x: x, y: y)
            // Tangent-based tilt so the dolphin's body follows the arc
            let dxArc = endPos.x - startPos.x
            let slope = (endPos.y - startPos.y) / max(1, duration) +
                        arcHeight * cos(.pi * p) * .pi / CGFloat(duration)
            let horiz = dxArc / CGFloat(duration)
            let baseRot = atan2(slope, horiz == 0 ? 0.0001 : horiz)
            (node as? SKSpriteNode).map { spr in
                spr.zRotation = initialFacingLeft ? (.pi - baseRot) : baseRot
            }
        }

        dolphin.run(.sequence([
            arc,
            .run { [weak self] in
                guard let self = self else { return }
                self.completeDolphinBonus(forOwner: owner, at: endPos)
            },
            .group([
                .scale(to: 0.30, duration: 0.20),
                .fadeOut(withDuration: 0.20),
            ]),
            .removeFromParent(),
        ]))
    }

    private func completeDolphinBonus(forOwner owner: BallOwner, at pos: CGPoint) {
        if owner == .player {
            playerScore += 5
            playerScoreLabel?.text = "YOU: \(playerScore)"
        } else {
            aiScore += 5
            aiScoreLabel?.text = "BOT: \(aiScore)"
        }
        showHoleEffect(at: pos)
        showDolphinBonusMessage(forOwner: owner)
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Reset spawn so a fresh nose can appear later in the round
        dolphinJumping = false
        dolphinSpawnTimer = Double.random(in: 12.0...18.0)
    }

    private func showDolphinBonusMessage(forOwner owner: BallOwner) {
        let banner = SKNode()
        banner.zPosition = 1200

        let text = owner == .player
            ? "5 POINT DOLPHIN BONUS!"
            : "BOT: 5 POINT DOLPHIN BONUS!"

        let label = makeLabel(text: text, size: min(11, W / 26),
                              color: SKColor(red: 0.40, green: 0.92, blue: 1.0, alpha: 1))
        let pad: CGFloat = 14
        let estW = CGFloat(text.count) * label.fontSize * 0.62 + pad * 2
        let bg = SKSpriteNode(
            color: SKColor(red: 0.02, green: 0.08, blue: 0.22, alpha: 0.92),
            size: CGSize(width: min(W * 0.92, estW), height: 30))
        banner.addChild(bg)
        banner.addChild(label)

        banner.position = CGPoint(x: 0, y: H * 0.18)
        banner.setScale(0.6); banner.alpha = 0
        addChild(banner)

        banner.run(.sequence([
            .group([.scale(to: 1.0, duration: 0.18), .fadeIn(withDuration: 0.18)]),
            .wait(forDuration: 1.6),
            .group([.fadeOut(withDuration: 0.30), .moveBy(x: 0, y: 14, duration: 0.30)]),
            .removeFromParent(),
        ]))
    }

    // Dolphin head/snout peeking from water — beak points RIGHT, flipped in scene by xScale.
    // Palette sampled from the reference pixel-art: steel blue-gray body, navy outline, amber eye.
    private func makeDolphinNoseTexture() -> SKTexture {
        if let t = dolphinTexture { return t }
        let tex = SKTexture(imageNamed: "Dolphin_head")
        tex.filteringMode = .nearest
        dolphinTexture = tex
        return tex
    }

    private func makeDolphinTexture() -> SKTexture {
        let tex = SKTexture(imageNamed: "Dolphin")
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - Ball-Ball Collisions

    private func resolveBallCollisions() {
        let ballRadius: CGFloat = 19.0
        let minDist:    CGFloat = ballRadius * 2

        for i in 0..<activeBalls.count {
            for j in (i + 1)..<activeBalls.count {
                let a = activeBalls[i], b = activeBalls[j]
                guard !a.hasHitSurface, !b.hasHitSurface else { continue }
                guard !a.hasScored, !b.hasScored else { continue }
                guard abs(a.bz - b.bz) < ballRadius else { continue }

                let dx = b.bx - a.bx, dy = b.by - a.by
                let distSq = dx * dx + dy * dy
                guard distSq < minDist * minDist, distSq > 0.01 else { continue }

                let dist = sqrt(distSq)
                let nx = dx / dist, ny = dy / dist
                let relVel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
                guard relVel < 0 else { continue }

                let impulse = -(1.0 + ballRestitution) * relVel * 0.5
                a.vx -= impulse * nx; a.vy -= impulse * ny
                b.vx += impulse * nx; b.vy += impulse * ny

                // Also bump vz slightly to give the collision some visual pop
                let vzBump: CGFloat = abs(relVel) * 0.15
                a.vz += vzBump; b.vz += vzBump

                let correction = (minDist - dist) * 0.5
                a.bx -= nx * correction; a.by -= ny * correction
                b.bx += nx * correction; b.by += ny * correction
            }
        }
    }

    // MARK: - Effects

    private func spawnSplash(at pos: CGPoint) {
        for i in 0..<4 {
            let ring = SKShapeNode(circleOfRadius: 4)
            ring.strokeColor = SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 0.70)
            ring.lineWidth = 1.5
            ring.fillColor = .clear
            ring.position = pos
            ring.zPosition = 30
            gameWorldNode.addChild(ring)
            let delay = Double(i) * 0.055
            ring.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .scale(to: CGFloat(i + 1) * 1.8, duration: 0.32),
                    .fadeOut(withDuration: 0.32),
                ]),
                .removeFromParent(),
            ]))
        }

        for _ in 0..<6 {
            let drop = SKSpriteNode(
                color: SKColor(red: 0.50, green: 0.85, blue: 1.0, alpha: 0.80),
                size: CGSize(width: 2, height: 2))
            drop.position = pos
            drop.zPosition = 31
            gameWorldNode.addChild(drop)
            let dx = CGFloat.random(in: -14...14)
            let dy = CGFloat.random(in: 4...18)
            drop.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.24),
                    .fadeOut(withDuration: 0.24),
                ]),
                .removeFromParent(),
            ]))
        }

        run(.playSoundFileNamed("bag_land.wav", waitForCompletion: false))
    }

    private func showHoleEffect(at pos: CGPoint) {
        let flash = SKSpriteNode(
            color: SKColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 0.90),
            size: CGSize(width: holeRadius * 1.6, height: holeRadius * 1.6))
        flash.position = pos
        flash.zPosition = 50
        gameWorldNode.addChild(flash)
        flash.run(.sequence([
            .group([
                .scale(to: 2.6, duration: 0.22),
                .fadeOut(withDuration: 0.30),
            ]),
            .removeFromParent(),
        ]))

        run(.playSoundFileNamed("hole_score.wav", waitForCompletion: false))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Timer Display

    private func updateTimerLabel() {
        let secs = max(0, Int(ceil(timeRemaining)))
        timerLabel?.text = String(format: "%d:%02d", secs / 60, secs % 60)

        if timeRemaining <= 10 && timeRemaining > 0 {
            let flash = timeRemaining.truncatingRemainder(dividingBy: 1.0) < 0.5
            timerLabel?.fontColor = flash
                ? SKColor(red: 0.96, green: 0.22, blue: 0.12, alpha: 1)
                : SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        }
    }

    private func updateCooldownBar() {
        guard let bar = cooldownBar, let bg = cooldownBarBg else { return }
        let pct = CGFloat(max(0, min(1, 1.0 - playerCooldown / throwCooldown)))
        bar.size.width = bg.size.width * pct
        let isReady = pct >= 1.0
        bar.color = isReady
            ? SKColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1)   // green = ready
            : SKColor(red: 0.70, green: 0.42, blue: 0.10, alpha: 1)   // amber = cooling

        // Pop the ready indicator in the moment the cooldown completes
        if isReady && !wasReady { showReadyIndicator() }
        wasReady = isReady
    }

    // MARK: - Throwing

    private func throwBall(owner: BallOwner, startX: CGFloat, startY: CGFloat,
                           vx: CGFloat, vy: CGFloat) {
        let tex = owner == .player ? playerBallTexture! : aiBallTexture!
        let ball = BeachBall(owner: owner, startX: startX, startY: startY, texture: tex)
        ball.vx = vx
        ball.vy = vy
        ball.vz = vzInitial

        let speed = sqrt(vx * vx + vy * vy)
        ball.rotV = (Bool.random() ? 1 : -1) * (0.05 + speed * 0.018)

        // 3D spin illusion: lateral speed → around-vertical-axis squish (xScale)
        //                   forward speed → around-horizontal-axis squish (yScale)
        ball.spinFrX = (Bool.random() ? 1 : -1) * (0.03 + abs(vx) * 0.022)
        ball.spinFrY = (Bool.random() ? 1 : -1) * (0.03 + abs(vy) * 0.016)
        ball.spinAmX = CGFloat.random(in: 0.10...0.18)
        ball.spinAmY = CGFloat.random(in: 0.08...0.15)
        ball.spinPhX = CGFloat.random(in: 0...(2 * .pi))
        ball.spinPhY = CGFloat.random(in: 0...(2 * .pi))

        gameWorldNode.addChild(ball.node)
        gameWorldNode.addChild(ball.shadow)
        activeBalls.append(ball)
    }

    // MARK: - AI

    private func executeAIThrow() {
        guard !gameOver, timeRemaining > 1.0 else { return }
        aiCooldown = throwCooldown + CGFloat.random(in: -0.3...0.3)

        let flightFrames = 2.0 * vzInitial / gravity  // ≈ 79 frames

        // Predict where the hole will be when the ball lands
        let futureBoardX = boardDriftX + boardDriftVx * CGFloat(flightFrames / 60.0)
        let clampedX     = max(-boardDriftMaxX, min(boardDriftMaxX, futureBoardX))

        // AI accuracy scales with score gap (rubber-band)
        let diff = playerScore - aiScore
        var noiseFactor: CGFloat = 1.4
        if diff > 2  { noiseFactor = max(0.4, noiseFactor - CGFloat(diff)  * 0.18) }
        if diff < -2 { noiseFactor = min(3.2, noiseFactor + CGFloat(-diff) * 0.18) }

        let noise  = holeRadius * noiseFactor
        let aimX   = clampedX + CGFloat.random(in: -noise...noise)
        let aimY   = holeCenterY + CGFloat.random(in: -noise * 0.4...noise * 0.4)

        let vx = (aimX  - aiStartX)    / flightFrames
        let vy = (aimY  - throwLineY)  / flightFrames

        throwBall(owner: .ai, startX: aiStartX, startY: throwLineY, vx: vx, vy: vy)
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
        if nodes(at: loc).contains(where: { $0.name == "pauseBtn" }) { pauseGame(); return }

        if confirmingQuit { handleButtonTap(at: loc); return }
        if gameOver       { handleButtonTap(at: loc); return }
        if countdownActive { return }

        if handleButtonTap(at: loc, fireActions: false) { return }

        touchStart = loc
        aimingLine?.removeFromParent()
        let line = SKShapeNode()
        line.strokeColor = SKColor(white: 1, alpha: 0.40)
        line.lineWidth = 1
        line.zPosition = 400
        addChild(line)
        aimingLine = line
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = touchStart, let line = aimingLine else { return }
        let loc  = touch.location(in: self)
        let path = CGMutablePath()
        path.move(to: start); path.addLine(to: loc)
        line.path = path
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)

        aimingLine?.removeFromParent(); aimingLine = nil

        if confirmingQuit || gameOver {
            handleButtonTap(at: end); touchStart = nil; return
        }

        if countdownActive { touchStart = nil; return }

        if handleButtonTap(at: end) { touchStart = nil; return }

        guard let start = touchStart else { return }
        touchStart = nil

        guard playerCooldown <= 0, !gameOver else { return }

        let dx = end.x - start.x
        let dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) > 4 else { return }

        playerCooldown = throwCooldown
        wasReady = false
        hideReadyIndicator()
        throwBall(owner: .player, startX: targetX, startY: throwLineY,
                  vx: dx * powerScale, vy: dy * powerScale)

        // React — AI schedules a reactive throw if it hasn't already
        if !aiPendingThrow && aiCooldown <= 0 {
            aiPendingThrow = true
            aiThrowDelay   = Double.random(in: 0.25...0.85)
            aiStartX       = CGFloat.random(in: -boardHalfW * 0.45...boardHalfW * 0.45)
        } else if aiCooldown > 0.6 {
            aiCooldown = 0.5  // shorten remaining cooldown for tighter reaction
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimingLine?.removeFromParent(); aimingLine = nil; touchStart = nil
    }

    @discardableResult
    private func handleButtonTap(at loc: CGPoint, fireActions: Bool = true) -> Bool {
        for node in nodes(at: loc) {
            var n: SKNode? = node
            while let cur = n {
                switch cur.name {
                case "closeButton":
                    if fireActions { showConfirmQuit() }; return true
                case "confirmQuitBtn":
                    if fireActions { hideConfirmPanel(); dismissScene(playerWon: false) }
                    return true
                case "cancelQuitBtn":
                    if fireActions { hideConfirmPanel() }; return true
                case "playAgainBtn":
                    if fireActions { restartGame() }; return true
                case "exitBtn":
                    if fireActions { dismissScene(playerWon: playerScore > aiScore) }
                    return true
                default: n = cur.parent
                }
            }
        }
        return false
    }

    // MARK: - Confirm Quit

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

    // MARK: - Game Over

    private func endGame() {
        gameOver = true
        run(.playSoundFileNamed("round_end.wav", waitForCompletion: false))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        showGameOverPanel()
    }

    private func showGameOverPanel() {
        messageNode?.removeFromParent()

        let tied      = playerScore == aiScore
        let playerWon = playerScore > aiScore

        let rewards: [GameResultModal.Reward] = (awardsRewards && playerWon)
            ? [GameResultModal.Reward(item: .floatingBag, count: 8)]
            : []

        let panel = GameResultModal.make(
            sceneSize: CGSize(width: W, height: H),
            won: playerWon,
            title: tied ? "TIE GAME" : (playerWon ? "VICTORY!" : "DEFEAT"),
            subtitle: "\(playerScore)  -  \(aiScore)",
            detail: "YOU   BOT",
            rewards: rewards,
            buttons: [GameResultModal.Button(label: "PLAY AGAIN", name: "playAgainBtn", style: .primary),
                      GameResultModal.Button(label: "EXIT", name: "exitBtn", style: .danger)])
        addChild(panel); messageNode = panel
    }

    // MARK: - Restart

    private func restartGame() {
        messageNode?.removeFromParent(); messageNode = nil
        playerScore = 0; aiScore = 0
        timeRemaining = 90.0; gameOver = false
        playerCooldown = 0; aiCooldown = 0
        wasReady = true
        showReadyIndicator()
        aiPendingThrow = false; lastUpdateTime = 0
        playerScoreLabel?.text = "YOU: 0"
        aiScoreLabel?.text     = "BOT: 0"
        timerLabel?.fontColor  = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        for ball in activeBalls { ball.node.removeFromParent(); ball.shadow.removeFromParent() }
        activeBalls.removeAll()
        dolphinNoseNode?.removeFromParent(); dolphinNoseNode = nil
        dolphinActive = false; dolphinJumping = false
        dolphinSpawnTimer = 7.0; dolphinHideTimer = 0
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

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        if playerWon { CornholeStatsManager.shared.recordWin() }
        else         { CornholeStatsManager.shared.recordLoss() }
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        let t = SKTransition.push(with: .down, duration: 0.38)
        t.pausesOutgoingScene = false
        view.presentScene(prev, transition: t)
    }

    // MARK: - Sound

    private func warmUpSounds() {
        let sounds = ["bag_land.wav", "hole_score.wav", "round_end.wav"]
        for f in sounds {
            let base = (f as NSString).deletingPathExtension
            let ext  = (f as NSString).pathExtension
            guard Bundle.main.url(forResource: base, withExtension: ext) != nil else { continue }
            let audio = SKAudioNode(fileNamed: f)
            audio.autoplayLooped = false; audio.isPositional = false
            addChild(audio)
            audio.run(.sequence([
                .changeVolume(to: 0, duration: 0), .play(),
                .wait(forDuration: 0.05),
                .run { [weak audio] in audio?.removeFromParent() },
            ]))
        }
    }

    // MARK: - Pixel Circle Texture (shared utility)

    private func makePixelCircleTexture(radius: CGFloat, fill: UIColor,
                                        border: UIColor, pixelSize: Int) -> SKTexture {
        let ps    = CGFloat(pixelSize)
        let cells = Int(ceil(radius * 2 / ps)) + 2
        let imgPx = cells * pixelSize
        let cx    = CGFloat(cells) / 2.0
        let cy    = CGFloat(cells) / 2.0
        let r     = radius / ps

        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: CGFloat(imgPx), height: CGFloat(imgPx)), false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }

        for row in 0..<cells {
            for col in 0..<cells {
                let dx   = CGFloat(col) + 0.5 - cx
                let dy   = CGFloat(row) + 0.5 - cy
                let dist = sqrt(dx * dx + dy * dy)
                let rect = CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps,
                                  width: ps, height: ps)
                if dist <= r - 0.7 {
                    ctx.setFillColor(fill.cgColor); ctx.fill(rect)
                } else if dist <= r + 0.3 {
                    ctx.setFillColor(border.cgColor); ctx.fill(rect)
                }
            }
        }
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex = SKTexture(image: img); tex.filteringMode = .nearest; return tex
    }
}
