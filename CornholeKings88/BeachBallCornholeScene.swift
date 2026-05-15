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
    private var closeUIButton: UIButton?

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
    private var timeRemaining: TimeInterval = 120.0
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
    private var beachBallTexture: SKTexture!
    private var messageNode: SKNode?
    private var confirmPanel: SKNode?
    private var confirmingQuit = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        beachBallTexture = Self.makeBeachBallTexture(diameter: 38)
        computeLayout()
        setupGameWorld()
        setupBoard()
        setupUI()
        pushCloseButton(to: view)
        warmUpSounds()
        boardDriftVx = 18.0 * (Bool.random() ? 1 : -1)
        driftVarianceTimer = Double.random(in: 1.5...3.0)
    }

    override func willMove(from view: SKView) {
        closeUIButton?.removeFromSuperview()
        closeUIButton = nil
    }

    // MARK: - Layout

    private func computeLayout() {
        boardY      = H * 0.08
        throwLineY  = -H * 0.30
        boardHalfW  = W * 0.265
        boardHalfH  = boardHalfW * 1.20
        holeRelY    = boardHalfH * 0.30
        holeRadius  = boardHalfW * 0.25

        let distToHole = abs((boardY + holeRelY) - throwLineY)
        let flightFrames = 2.0 * vzInitial / gravity
        let idealSwipe   = H * 0.38
        powerScale = distToHole / (flightFrames * idealSwipe)
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
        let topH: CGFloat = max(48, H * 0.09)
        let botH: CGFloat = max(36, H * 0.07)
        let topBarY = H / 2 - topH / 2
        let botBarY = -H / 2 + botH / 2

        addChrome(y: topBarY, h: topH)
        addChrome(y: botBarY, h: botH)

        // Timer
        let tl = makeLabel(text: "2:00", size: min(14, W / 22),
                           color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        tl.horizontalAlignmentMode = .center
        tl.position = CGPoint(x: 0, y: topBarY)
        tl.zPosition = 600
        addChild(tl)
        timerLabel = tl

        // Score chip
        let chipW: CGFloat = min(W * 0.64, 240)
        let chipH: CGFloat = 34
        let chipY = H / 2 - topH - chipH / 2 - 6

        let chipBg = SKSpriteNode(
            color: SKColor(red: 0.02, green: 0.06, blue: 0.16, alpha: 0.92),
            size: CGSize(width: chipW, height: chipH))
        chipBg.position = CGPoint(x: 0, y: chipY)
        chipBg.zPosition = 600
        addChild(chipBg)

        let pLabel = makeLabel(text: "YOU: 0", size: 9,
                               color: SKColor(red: 0.97, green: 0.42, blue: 0.22, alpha: 1))
        pLabel.horizontalAlignmentMode = .left
        pLabel.position = CGPoint(x: -chipW / 2 + 10, y: chipY)
        pLabel.zPosition = 602
        addChild(pLabel)
        playerScoreLabel = pLabel

        let divider = SKSpriteNode(
            color: SKColor(red: 0.40, green: 0.80, blue: 1.00, alpha: 0.35),
            size: CGSize(width: 1, height: 20))
        divider.position = CGPoint(x: 0, y: chipY)
        divider.zPosition = 602
        addChild(divider)

        let aLabel = makeLabel(text: "BOT: 0", size: 9,
                               color: SKColor(red: 0.28, green: 0.75, blue: 1.00, alpha: 1))
        aLabel.horizontalAlignmentMode = .right
        aLabel.position = CGPoint(x: chipW / 2 - 10, y: chipY)
        aLabel.zPosition = 602
        addChild(aLabel)
        aiScoreLabel = aLabel

        // Cooldown bar (shows when player can throw again)
        let barW = min(W * 0.52, 170)
        let barH: CGFloat = 7

        let barBg = SKSpriteNode(
            color: SKColor(white: 0.12, alpha: 0.88),
            size: CGSize(width: barW, height: barH))
        barBg.position = CGPoint(x: 0, y: botBarY + 4)
        barBg.zPosition = 600
        addChild(barBg)
        cooldownBarBg = barBg

        let bar = SKSpriteNode(
            color: SKColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1),
            size: CGSize(width: barW, height: barH))
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position = CGPoint(x: -barW / 2, y: botBarY + 4)
        bar.zPosition = 601
        addChild(bar)
        cooldownBar = bar

        let readyLbl = makeLabel(text: "READY", size: 5,
                                 color: SKColor(white: 0.55, alpha: 1))
        readyLbl.horizontalAlignmentMode = .center
        readyLbl.position = CGPoint(x: 0, y: botBarY - 6)
        readyLbl.zPosition = 600
        addChild(readyLbl)

        addCrtOverlay()
    }

    private func addChrome(y: CGFloat, h: CGFloat) {
        let panel = SKSpriteNode(
            color: SKColor(red: 0.04, green: 0.015, blue: 0.008, alpha: 0.96),
            size: CGSize(width: W, height: h))
        panel.position = CGPoint(x: 0, y: y)
        panel.zPosition = 500
        addChild(panel)

        let rule = SKSpriteNode(
            color: SKColor(red: 0.22, green: 0.58, blue: 0.82, alpha: 0.48),
            size: CGSize(width: W, height: 1))
        rule.position = CGPoint(x: 0, y: y - h / 2)
        rule.zPosition = 501
        addChild(rule)
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

    // MARK: - Close Button

    private func pushCloseButton(to view: UIView) {
        let btn = UIButton(type: .custom)
        btn.frame = CGRect(x: 12, y: 12, width: 44, height: 44)
        btn.setTitle("✕", for: .normal)
        btn.titleLabel?.font = UIFont(name: "PressStart2P-Regular", size: 13) ??
                               UIFont.systemFont(ofSize: 13)
        btn.setTitleColor(UIColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1), for: .normal)
        btn.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(btn)
        closeUIButton = btn
    }

    @objc private func closeButtonTapped() { showConfirmQuit() }

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

    static func makeBeachBallTexture(diameter: CGFloat) -> SKTexture {
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

            // Classic beachball stripe colors
            let stripes: [UIColor] = [
                UIColor(red: 0.92, green: 0.15, blue: 0.15, alpha: 1),   // red
                UIColor(red: 0.95, green: 0.84, blue: 0.08, alpha: 1),   // yellow
                UIColor(red: 0.08, green: 0.38, blue: 0.92, alpha: 1),   // blue
                UIColor(red: 0.12, green: 0.70, blue: 0.22, alpha: 1),   // green
                UIColor(red: 0.94, green: 0.94, blue: 0.92, alpha: 1),   // white
                UIColor(red: 0.92, green: 0.15, blue: 0.15, alpha: 1),   // red (wrap)
            ]
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

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        let fixedDt: CGFloat = 1.0 / 60.0

        if lastUpdateTime == 0 { lastUpdateTime = currentTime; return }
        let realDt = min(0.1, currentTime - lastUpdateTime)
        lastUpdateTime = currentTime

        guard !gameOver else { return }

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

        // Board drift
        updateBoardDrift(dt: CGFloat(realDt))

        // Ball physics (iterate by index so we can safely read count)
        for i in 0..<activeBalls.count {
            let ball = activeBalls[i]
            guard !ball.hasHitSurface else { continue }
            updateBallPhysics(ball, dt: fixedDt)
        }

        resolveBallCollisions()
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

        ball.rot += ball.rotV
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
        bar.color = pct >= 1.0
            ? SKColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1)   // green = ready
            : SKColor(red: 0.70, green: 0.42, blue: 0.10, alpha: 1)   // amber = cooling
    }

    // MARK: - Throwing

    private func throwBall(owner: BallOwner, startX: CGFloat, startY: CGFloat,
                           vx: CGFloat, vy: CGFloat) {
        let ball = BeachBall(owner: owner, startX: startX, startY: startY,
                             texture: beachBallTexture)
        ball.vx = vx
        ball.vy = vy
        ball.vz = vzInitial

        let speed = sqrt(vx * vx + vy * vy)
        ball.rotV = (Bool.random() ? 1 : -1) * (0.05 + speed * 0.018)

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

        if confirmingQuit { handleButtonTap(at: loc); return }
        if gameOver       { handleButtonTap(at: loc); return }

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

        if handleButtonTap(at: end) { touchStart = nil; return }

        guard let start = touchStart else { return }
        touchStart = nil

        guard playerCooldown <= 0, !gameOver else { return }

        let dx = end.x - start.x
        let dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) > 4 else { return }

        playerCooldown = throwCooldown
        throwBall(owner: .player, startX: start.x, startY: throwLineY,
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

        let panel = SKNode(); panel.zPosition = 1100
        let bg = SKSpriteNode(
            color: SKColor(red: 0.03, green: 0.07, blue: 0.16, alpha: 0.96),
            size: CGSize(width: W * 0.72, height: H * 0.28))
        panel.addChild(bg)

        let lbl = makeLabel(text: "QUIT?", size: min(12, W / 22),
                            color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        lbl.position = CGPoint(x: 0, y: H * 0.066)
        panel.addChild(lbl)

        for (i, (txt, name)) in [("YES", "confirmQuitBtn"), ("NO", "cancelQuitBtn")].enumerated() {
            panel.addChild(makeButtonNode(text: txt, name: name,
                                          at: CGPoint(x: CGFloat(i * 2 - 1) * W * 0.15, y: -H * 0.035),
                                          width: W * 0.26))
        }
        addChild(panel); confirmPanel = panel
    }

    private func hideConfirmPanel() {
        confirmingQuit = false; confirmPanel?.removeFromParent(); confirmPanel = nil
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

        let panel   = SKNode(); panel.zPosition = 1000
        let panelW  = W * 0.84
        let panelH  = H * 0.52

        let backing = SKSpriteNode(
            color: SKColor(red: 0.03, green: 0.08, blue: 0.18, alpha: 0.96),
            size: CGSize(width: panelW, height: panelH))
        panel.addChild(backing)

        let tied      = playerScore == aiScore
        let playerWon = playerScore > aiScore
        let headerTxt: String
        let headerCol: SKColor
        if tied {
            headerTxt = "TIE GAME"
            headerCol = SKColor(red: 0.90, green: 0.78, blue: 0.28, alpha: 1)
        } else if playerWon {
            headerTxt = "YOU WIN!"
            headerCol = SKColor(red: 0.18, green: 0.88, blue: 0.44, alpha: 1)
        } else {
            headerTxt = "BOT WINS!"
            headerCol = SKColor(red: 0.96, green: 0.24, blue: 0.16, alpha: 1)
        }

        let header = makeLabel(text: headerTxt, size: min(17, panelW / 14), color: headerCol)
        header.position = CGPoint(x: 0, y: panelH * 0.28)
        panel.addChild(header)

        let scoreLbl = makeLabel(text: "\(playerScore)  —  \(aiScore)",
                                  size: min(13, panelW / 18),
                                  color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        scoreLbl.position = CGPoint(x: 0, y: panelH * 0.02)
        panel.addChild(scoreLbl)

        let sub = makeLabel(text: "YOU   BOT", size: min(6, panelW / 38),
                            color: SKColor(white: 0.50, alpha: 1))
        sub.position = CGPoint(x: 0, y: -panelH * 0.10)
        panel.addChild(sub)

        panel.addChild(makeButtonNode(text: "PLAY AGAIN", name: "playAgainBtn",
                                       at: CGPoint(x: 0, y: -panelH * 0.28), width: panelW * 0.74))
        panel.addChild(makeButtonNode(text: "EXIT", name: "exitBtn",
                                       at: CGPoint(x: 0, y: -panelH * 0.42), width: panelW * 0.74))

        addChild(panel); messageNode = panel
    }

    private func makeButtonNode(text: String, name: String,
                                 at pos: CGPoint, width: CGFloat) -> SKNode {
        let container = SKNode(); container.position = pos; container.name = name
        let bg = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 0.92),
            size: CGSize(width: width, height: 30))
        bg.name = name; container.addChild(bg)
        let lbl = makeLabel(text: text, size: min(9, width / 16),
                            color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        lbl.name = name; container.addChild(lbl)
        return container
    }

    // MARK: - Restart

    private func restartGame() {
        messageNode?.removeFromParent(); messageNode = nil
        playerScore = 0; aiScore = 0
        timeRemaining = 120.0; gameOver = false
        playerCooldown = 0; aiCooldown = 0
        aiPendingThrow = false; lastUpdateTime = 0
        playerScoreLabel?.text = "YOU: 0"
        aiScoreLabel?.text     = "BOT: 0"
        timerLabel?.fontColor  = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        for ball in activeBalls { ball.node.removeFromParent(); ball.shadow.removeFromParent() }
        activeBalls.removeAll()
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
