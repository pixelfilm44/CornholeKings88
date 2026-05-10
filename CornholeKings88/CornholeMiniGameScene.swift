import SpriteKit
import UIKit

// MARK: - CornholeMiniGameScene
// 16-bit style cornhole mini-game, self-contained. Present this scene when the
// player steps up to a board and taps A. Bags are drawn programmatically;
// replace bag_16bit.png / board_16bit.png in the bundle when sprites are ready.

final class CornholeMiniGameScene: SKScene {

    // MARK: - Public
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?

    // MARK: - Types

    enum BagOwner { case player, ai }

    private enum State { case playerTurn, aiTurn, resolving, gameOver }

    // Per-bag physics/visual state kept off the node graph to avoid SpriteKit
    // overhead. Positions are in scene coordinate units (source pixels).
    private final class MiniGameBag {
        var bx, by, bz: CGFloat   // physics world position; bz = height above surface
        var vx, vy, vz: CGFloat   // velocities (per-frame units)
        var rot: CGFloat = 0
        var rotV: CGFloat = 0
        var owner: BagOwner
        var isGrounded = false
        var hasScored = false                // landed in hole
        var hasAppliedGroundScale = false    // prevents double-shrink on re-collision
        var hasLanded = false               // first touchdown — for haptic trigger
        var baseScale: CGFloat = 1.0        // 0.75 for off-board bags; multiplied by height scale

        let node: SKSpriteNode
        let shadow: SKSpriteNode

        init(owner: BagOwner, startX: CGFloat, startY: CGFloat) {
            self.owner = owner
            self.bx = startX; self.by = startY; self.bz = 3
            self.vx = 0; self.vy = 0; self.vz = 0

            let playerColor = SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
            let aiColor     = SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1)

            let bagTex = SKTexture(imageNamed: "bag_16bit")
            bagTex.filteringMode = .nearest
            node = SKSpriteNode(texture: bagTex, size: CGSize(width: 50, height: 50))
            node.color            = owner == .player ? playerColor : aiColor
            node.colorBlendFactor = 0.65   // tint sprite red (player) or blue (AI)
            node.zPosition        = 20

            shadow = SKSpriteNode(color: .black,
                                  size: CGSize(width: 50, height: 35))
            shadow.alpha = 0.35
            shadow.zPosition = 6
        }

        required init?(coder: NSCoder) { fatalError() }

        var isMoving: Bool { bz > 0.15 || abs(vx) > 0.012 || abs(vy) > 0.012 }
    }

    // MARK: - Layout (computed in didMove)
    private var boardY: CGFloat = 0
    private var throwLineY: CGFloat = 0
    private var boardHalfW: CGFloat = 0
    private var boardHalfH: CGFloat = 0
    private var holeCenter = CGPoint.zero
    private var holeRadius: CGFloat = 0
    private var targetRange: CGFloat = 0
    private var targetSpeed: CGFloat = 0
    private var powerScale: CGFloat = 0

    // MARK: - Physics constants
    private let gravityPerFrame: CGFloat = 0.50
    private let vzInitial:       CGFloat = 15.0

    // MARK: - Game state
    private var gameState: State = .playerTurn
    private var activeBags: [MiniGameBag] = []
    private var playerBagsThrown = 0
    private var aiBagsThrown     = 0
    private let bagsPerPlayer    = 4
    private let winScore         = 11
    private var playerScore      = 0
    private var aiScore          = 0
    private var lastThrower: BagOwner = .ai
    private var hasCalculatedScore = false

    // Moving throw-target oscillation
    private var targetX: CGFloat = 0
    private var targetMovingRight = true

    // Wind (dx only for 2D feel)
    private var wind = CGVector.zero

    // Rain scenario — rolled once per game; -1 = no rain
    private var rainActive      = false
    private var rainStartRound  = -1      // round when rain begins (1-indexed)
    private var rainEndRound    = Int.max // first round without rain (Int.max = whole game)
    private var roundNumber     = 0
    private var rainParticleNode: SKNode?
    private var boardRainOverlay: SKSpriteNode?

    // Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // Tutorial / confirm state
    private var tutorialActive   = false
    private var confirmingQuit   = false
    private var confirmPanel:  SKNode?

    // MARK: - Node references
    private var gameWorldNode: SKEffectNode!
    private var turnIndicator: SKSpriteNode?
    private var playerScoreLabel: SKLabelNode?
    private var aiScoreLabel:     SKLabelNode?
    private var windLabel:        SKLabelNode?
    private var messageNode: SKNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        computeLayout()
        setupGameWorld()
        setupBoard()
        setupUI()
        rollRainScenario()

        // Always show on mini-game open. Player can dismiss instantly with "GOT IT!".
        // TODO: re-introduce one-time gating once rendering is confirmed.
        showFirstTimeTutorial()
        print("🎓 Cornhole tutorial requested in didMove")
    }

    // MARK: - Layout

    private func computeLayout() {
        boardY       = size.height * 0.18
        throwLineY   = -size.height * 0.30
        boardHalfW   = size.width * 0.2625  // 25% narrower than before
        boardHalfH   = boardHalfW * 1.20
        holeCenter   = CGPoint(x: 0, y: boardY + boardHalfH * 0.30)
        holeRadius   = boardHalfW * 0.25
        targetRange  = boardHalfW * 1.30
        targetSpeed  = size.width * 0.70   // source pixels per second

        // powerScale chosen so a 38% screen-height swipe lands near the hole
        let distToHole   = abs(holeCenter.y - throwLineY)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 100 frames
        let idealSwipe   = size.height * 0.38
        powerScale = distToHole / (flightFrames * idealSwipe)
    }

    // MARK: - Scene Setup

    private func setupGameWorld() {
        // SKEffectNode applies the CIPixellate filter — gives the 16-bit chunky-pixel look.
        // Scale 2 = each source pixel rendered as a 2×2 block (subtler than 8-bit at 4).
        gameWorldNode = SKEffectNode()
        if let filter = CIFilter(name: "CIPixellate") {
            filter.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = filter
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        addChild(gameWorldNode)

        // Dark-green grass background
        let bg = SKSpriteNode(color: SKColor(red: 0.13, green: 0.30, blue: 0.10, alpha: 1),
                              size: CGSize(width: size.width * 2, height: size.height * 2))
        bg.zPosition = -200
        gameWorldNode.addChild(bg)

        addGrassPattern()

        // Throw line
        let throwLine = SKSpriteNode(
            color: SKColor(white: 1.0, alpha: 0.55),
            size: CGSize(width: boardHalfW * 1.2, height: 1))
        throwLine.position = CGPoint(x: 0, y: throwLineY)
        throwLine.zPosition = -1
        gameWorldNode.addChild(throwLine)
    }

    // Scatter random darker/lighter 4×4 grass tufts for texture
    private func addGrassPattern() {
        let tileSize: CGFloat = 4
        let palette: [SKColor] = [
            SKColor(red: 0.10, green: 0.25, blue: 0.08, alpha: 1),
            SKColor(red: 0.18, green: 0.38, blue: 0.14, alpha: 1),
            SKColor(red: 0.09, green: 0.22, blue: 0.07, alpha: 1),
        ]
        var x = -size.width
        while x < size.width {
            var y = -size.height
            while y < size.height {
                if Int.random(in: 0..<5) == 0 {
                    let tuft = SKSpriteNode(color: palette.randomElement()!,
                                           size: CGSize(width: tileSize, height: tileSize))
                    tuft.position = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                    tuft.zPosition = -199
                    gameWorldNode.addChild(tuft)
                }
                y += tileSize
            }
            x += tileSize
        }
    }

    private func setupBoard() {
        let boardContainer = SKNode()
        boardContainer.position = CGPoint(x: 0, y: boardY)
        boardContainer.zPosition = 5
        gameWorldNode.addChild(boardContainer)

        let bw = boardHalfW * 2
        let bh = boardHalfH * 2

        // Drop shadow (offset so it reads as depth)
        let shadowNode = SKSpriteNode(color: .black,
                                      size: CGSize(width: bw + 4, height: bh + 4))
        shadowNode.alpha = 0.45
        shadowNode.position = CGPoint(x: 4, y: -5)
        shadowNode.zPosition = -1
        boardContainer.addChild(shadowNode)

        // Board surface — use the 16-bit sprite asset
        let boardTex = SKTexture(imageNamed: "board_16bit")
        boardTex.filteringMode = .nearest
        let surface = SKSpriteNode(texture: boardTex, size: CGSize(width: bw, height: bh))
        surface.zPosition = 0
        boardContainer.addChild(surface)

        // Hole — dark circle positioned in the upper third of the board
        let holeRelY = holeCenter.y - boardY
        let holeTex = makePixelCircleTexture(
            radius:      holeRadius,
            fill:        UIColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 1),
            border:      UIColor(red: 0.25, green: 0.13, blue: 0.04, alpha: 1),
            pixelSize:   3)
        let hole = SKSpriteNode(texture: holeTex,
                                size: CGSize(width: holeRadius * 2, height: holeRadius * 2))
        hole.position  = CGPoint(x: 0, y: holeRelY)
        hole.zPosition = 2
        boardContainer.addChild(hole)
    }

    /// Rasterises a circle as a grid of square pixels so it looks 16-bit rather
    /// than smooth. pixelSize controls the coarseness (3 = chunky, 1 = no effect).
    private func makePixelCircleTexture(radius: CGFloat,
                                        fill: UIColor,
                                        border: UIColor,
                                        pixelSize: Int) -> SKTexture {
        let ps    = CGFloat(pixelSize)
        let cells = Int(ceil(radius * 2 / ps)) + 2   // grid cells across diameter
        let imgPx = cells * pixelSize                 // total image size in points
        let size  = CGSize(width: CGFloat(imgPx), height: CGFloat(imgPx))
        let cx    = CGFloat(cells) / 2.0
        let cy    = CGFloat(cells) / 2.0
        let r     = radius / ps   // radius in grid-cell units

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }

        for row in 0..<cells {
            for col in 0..<cells {
                // Distance from cell centre to circle centre (in grid units)
                let dx   = CGFloat(col) + 0.5 - cx
                let dy   = CGFloat(row) + 0.5 - cy
                let dist = sqrt(dx * dx + dy * dy)

                let rect = CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps,
                                  width: ps, height: ps)
                if dist <= r - 0.7 {
                    ctx.setFillColor(fill.cgColor)
                    ctx.fill(rect)
                } else if dist <= r + 0.3 {
                    ctx.setFillColor(border.cgColor)
                    ctx.fill(rect)
                }
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex   = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - UI

    private func setupUI() {
        let topH    = size.height * 0.10
        let bottomH = size.height * 0.09
        let fs      = max(5, size.width * 0.040)

        // Top chrome bar
        addChrome(y: size.height / 2 - topH / 2, h: topH)
        // Bottom chrome bar
        addChrome(y: -size.height / 2 + bottomH / 2, h: bottomH)

        // Player score — top left
        let pLabel = makeLabel(text: "YOU: 0", size: fs, color: SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1))
        pLabel.horizontalAlignmentMode = .left
        pLabel.position = CGPoint(x: -size.width / 2 + 8, y: size.height / 2 - topH / 2)
        pLabel.zPosition = 600
        addChild(pLabel)
        playerScoreLabel = pLabel

        // AI score — top center-right (leave room for close button)
        let aLabel = makeLabel(text: "BOT: 0", size: fs, color: SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        aLabel.horizontalAlignmentMode = .right
        aLabel.position = CGPoint(x: size.width / 2 - 30, y: size.height / 2 - topH / 2)
        aLabel.zPosition = 600
        addChild(aLabel)
        aiScoreLabel = aLabel

        // Wind label — bottom center
        let wLabel = makeLabel(text: "CALM", size: max(5, fs * 0.80), color: SKColor(white: 0.75, alpha: 1))
        wLabel.horizontalAlignmentMode = .center
        wLabel.position = CGPoint(x: 0, y: -size.height / 2 + bottomH / 2)
        wLabel.zPosition = 600
        addChild(wLabel)
        windLabel = wLabel

        // Round score labels (bottom left/right, shown during play)
        let rndPLabel = makeLabel(text: "", size: fs, color: SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1))
        rndPLabel.horizontalAlignmentMode = .left
        rndPLabel.position = CGPoint(x: -size.width / 2 + 8, y: -size.height / 2 + bottomH / 2)
        rndPLabel.zPosition = 600
        rndPLabel.name = "rndPlayerLabel"
        addChild(rndPLabel)

        let rndALabel = makeLabel(text: "", size: fs, color: SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        rndALabel.horizontalAlignmentMode = .right
        rndALabel.position = CGPoint(x: size.width / 2 - 8, y: -size.height / 2 + bottomH / 2)
        rndALabel.zPosition = 600
        rndALabel.name = "rndAILabel"
        addChild(rndALabel)

        // Close button — top right corner
        let closeBtn = makeButton(label: "X", fg: .white,
                                  bg: SKColor(red: 0.55, green: 0.12, blue: 0.12, alpha: 0.9),
                                  size: CGSize(width: 20, height: 14))
        closeBtn.position = CGPoint(x: size.width / 2 - 14, y: size.height / 2 - topH / 2)
        closeBtn.name = "closeButton"
        closeBtn.zPosition = 700
        addChild(closeBtn)

        // Turn-indicator bag (oscillates at the throw line, in gameWorld so it pixellates)
        let indTex = SKTexture(imageNamed: "bag_16bit")
        indTex.filteringMode = .nearest
        let indicator = SKSpriteNode(texture: indTex, size: CGSize(width: 50, height: 50))
        indicator.color            = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        indicator.colorBlendFactor = 0.65
        indicator.position  = CGPoint(x: 0, y: throwLineY)
        indicator.zPosition = 30
        gameWorldNode.addChild(indicator)
        turnIndicator = indicator

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.18, duration: 0.55),
            SKAction.scale(to: 1.00, duration: 0.55),
        ])
        indicator.run(SKAction.repeatForever(pulse))
    }

    private func addChrome(y: CGFloat, h: CGFloat) {
        let bar = SKSpriteNode(color: SKColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 0.88),
                               size: CGSize(width: size.width, height: h))
        bar.position = CGPoint(x: 0, y: y)
        bar.zPosition = 500
        addChild(bar)
        // 1px pixel-art border on the inner edge
        let border = SKSpriteNode(color: SKColor(red: 0.50, green: 0.35, blue: 0.15, alpha: 0.7),
                                  size: CGSize(width: size.width, height: 1))
        border.position = CGPoint(x: 0, y: y + (y > 0 ? -h / 2 : h / 2))
        border.zPosition = 501
        addChild(border)
    }

    private func makeLabel(text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.fontSize = size
        l.fontColor = color
        l.text = text
        l.verticalAlignmentMode = .center
        return l
    }

    private func makeButton(label: String, fg: SKColor, bg: SKColor, size: CGSize) -> SKNode {
        let n = SKNode()
        let backing = SKSpriteNode(color: bg, size: size)
        backing.zPosition = 0
        n.addChild(backing)
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.fontSize = max(5, size.height * 0.55)
        lbl.fontColor = fg
        lbl.text = label
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.zPosition = 1
        n.addChild(lbl)
        return n
    }

    // MARK: - Game Flow

    private func startRound() {
        roundNumber += 1

        // Toggle rain on/off for this round
        let shouldRain = rainStartRound >= 0 && roundNumber >= rainStartRound && roundNumber < rainEndRound
        if shouldRain && !rainActive  { activateRain() }
        if !shouldRain && rainActive  { deactivateRain() }

        wind = CGVector(dx: CGFloat.random(in: -2.0...2.0), dy: 0)
        updateWindLabel()

        playerBagsThrown    = 0
        aiBagsThrown        = 0
        hasCalculatedScore  = false

        for bag in activeBags {
            bag.node.removeFromParent()
            bag.shadow.removeFromParent()
        }
        activeBags.removeAll()

        messageNode?.removeFromParent()
        messageNode = nil

        gameState = .playerTurn
        lastThrower = .ai
        targetX = 0
        turnIndicator?.isHidden = false

        updateScoreLabels()
        updateTurnIndicator()
        updateRoundLabels()
    }

    private var allBagsThrown: Bool {
        playerBagsThrown >= bagsPerPlayer && aiBagsThrown >= bagsPerPlayer
    }

    private func handleTurnEnd() {
        guard gameState == .resolving else { return }

        if allBagsThrown {
            calculateRoundScore()
        } else if lastThrower == .player {
            gameState = .aiTurn
            updateTurnIndicator()
            run(SKAction.wait(forDuration: 0.50)) { [weak self] in self?.aiThrow() }
        } else {
            gameState = .playerTurn
            targetX = 0
            turnIndicator?.position.x = 0
            turnIndicator?.isHidden = false
            updateTurnIndicator()
        }
    }

    private func calculateRoundScore() {
        guard !hasCalculatedScore else { return }
        hasCalculatedScore = true

        var roundPlayer = 0
        var roundAI     = 0

        for bag in activeBags {
            let isInHole  = bag.hasScored
            let isOnBoard = !isInHole && checkIsOnBoard(bag)
            let pts       = isInHole ? 3 : (isOnBoard ? 1 : 0)
            if bag.owner == .player { roundPlayer += pts }
            else                    { roundAI     += pts }
        }

        let net = roundPlayer - roundAI
        if net > 0 { playerScore += net }
        else if net < 0 { aiScore += abs(net) }

        updateScoreLabels()

        if playerScore >= winScore || aiScore >= winScore {
            gameState = .gameOver
            // PLACEHOLDER: add game_win.wav / game_lose.wav to Copy Bundle Resources
            let resultSound = playerScore > aiScore ? "game_win.wav" : "game_lose.wav"
            run(SKAction.playSoundFileNamed(resultSound, waitForCompletion: false))
            run(SKAction.wait(forDuration: 0.6)) { [weak self] in
                guard let s = self else { return }
                s.showGameOverPanel(playerWon: s.playerScore > s.aiScore)
            }
        } else {
            // PLACEHOLDER: add round_end.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("round_end.wav", waitForCompletion: false))
            showRoundResultMessage(roundPlayer: roundPlayer, roundAI: roundAI)
            run(SKAction.wait(forDuration: 2.0)) { [weak self] in self?.startRound() }
        }
    }

    // MARK: - Physics update

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat = 1.0 / 60.0

        if gameState == .playerTurn {
            updateTargetOscillation(dt: dt)
        }

        var anyMoving = false
        for bag in activeBags {
            guard !bag.isGrounded || bag.isMoving else { continue }
            updateBagPhysics(bag, dt: dt)
            if bag.isMoving { anyMoving = true }
        }

        resolveBagCollisions()

        // Re-check movement after collisions may have woken grounded bags
        for bag in activeBags where bag.isMoving { anyMoving = true }

        updateRoundLabels()

        if gameState == .resolving && !anyMoving {
            handleTurnEnd()
        }
    }

    // Elastic bag-to-bag collision — bags knock each other around on the board
    // and on the ground, and a well-aimed bag can push another into the hole.
    private func resolveBagCollisions() {
        let bagRadius: CGFloat = 22           // collision half-size (slightly under visual half)
        let minDist:   CGFloat = bagRadius * 2
        let restitution: CGFloat = 0.68       // bounciness: 0 = dead stop, 1 = fully elastic

        for i in 0..<activeBags.count {
            for j in (i + 1)..<activeBags.count {
                let a = activeBags[i]
                let b = activeBags[j]

                guard !a.hasScored && !b.hasScored else { continue }

                // Bags that fell off the board are locked in place — skip
                guard !a.hasAppliedGroundScale && !b.hasAppliedGroundScale else { continue }

                // Ignore if one bag is flying well above the other
                guard abs(a.bz - b.bz) < bagRadius else { continue }

                let dx = b.bx - a.bx
                let dy = b.by - a.by
                let distSq = dx * dx + dy * dy
                guard distSq < minDist * minDist, distSq > 0.01 else { continue }

                let dist = sqrt(distSq)
                let nx = dx / dist   // collision normal
                let ny = dy / dist

                // Only resolve if the bags are approaching each other
                let dvx = b.vx - a.vx
                let dvy = b.vy - a.vy
                let relVel = dvx * nx + dvy * ny
                guard relVel < 0 else { continue }

                // Equal-mass impulse
                let impulse = -(1.0 + restitution) * relVel * 0.5
                a.vx -= impulse * nx;  a.vy -= impulse * ny
                b.vx += impulse * nx;  b.vy += impulse * ny

                // Un-ground board bags so they slide freely after impact
                a.isGrounded = false
                b.isGrounded = false

                // Positional correction — push apart so they no longer overlap
                let correction = (minDist - dist) * 0.5
                a.bx -= nx * correction;  a.by -= ny * correction
                b.bx += nx * correction;  b.by += ny * correction
            }
        }
    }

    private func updateTargetOscillation(dt: CGFloat) {
        let step = targetSpeed * dt
        if targetMovingRight {
            targetX += step
            if targetX >= targetRange { targetX = targetRange; targetMovingRight = false }
        } else {
            targetX -= step
            if targetX <= -targetRange { targetX = -targetRange; targetMovingRight = true }
        }
        turnIndicator?.position.x = targetX
    }

    private func updateBagPhysics(_ bag: MiniGameBag, dt: CGFloat) {
        // Airborne wind push
        if bag.bz > 0 {
            bag.vx += wind.dx * dt * 0.07
        }

        // Integrate
        bag.vz -= gravityPerFrame
        bag.bx += bag.vx
        bag.by += bag.vy
        bag.bz += bag.vz

        bag.rot += bag.rotV
        bag.node.zRotation = bag.rot

        if bag.bz <= 0 {
            bag.bz = 0
            if checkIsOnBoard(bag) {
                // Haptic on first board touchdown
                if !bag.hasLanded {
                    bag.hasLanded = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    // PLACEHOLDER: add bag_land.wav to Copy Bundle Resources
                    run(SKAction.playSoundFileNamed("bag_land.wav", waitForCompletion: false))
                }

                // Small bounce then slide — rain makes the surface very slippery
                let boardFriction: CGFloat = rainActive ? 0.968 : 0.92
                if abs(bag.vz) > 0.5 {
                    bag.vz = abs(bag.vz) * 0.18
                } else {
                    bag.vz = 0
                    bag.isGrounded = true
                }
                bag.vx *= boardFriction
                bag.vy *= boardFriction
                bag.rotV *= rainActive ? 0.88 : 0.65

                // Hole detection
                let dist = hypot(bag.bx - holeCenter.x, bag.by - holeCenter.y)
                if dist <= holeRadius && !bag.hasScored {
                    bag.hasScored  = true
                    bag.isGrounded = true
                    bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    // PLACEHOLDER: add hole_score.wav to Copy Bundle Resources
                    run(SKAction.playSoundFileNamed("hole_score.wav", waitForCompletion: false))
                    showHoleEffect(at: CGPoint(x: bag.bx, y: bag.by))
                    let sink = SKAction.sequence([
                        SKAction.group([
                            SKAction.scale(to: 0.3, duration: 0.20),
                            SKAction.fadeOut(withDuration: 0.20),
                        ]),
                        SKAction.hide(),
                    ])
                    bag.node.run(sink)
                    bag.shadow.run(SKAction.fadeOut(withDuration: 0.15))
                }
            } else {
                // Lands off-board — stop dead and shrink to show depth vs. board level
                bag.isGrounded = true
                bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                if !bag.hasAppliedGroundScale {
                    bag.hasAppliedGroundScale = true
                    bag.baseScale = 0.75
                    bag.node.run(SKAction.scale(to: 0.75, duration: 0.12))
                    bag.shadow.run(SKAction.scale(to: 0.75, duration: 0.12))
                }
            }
        }

        // Friction stop on board surface — rain raises the stop threshold so bags
        // slide until nearly stationary rather than snapping to a halt.
        let stopThreshold: CGFloat = rainActive ? 0.012 : 0.04
        if bag.isGrounded && abs(bag.vx) < stopThreshold && abs(bag.vy) < stopThreshold {
            bag.vx = 0; bag.vy = 0
        }

        // Render: visual Y elevated by z for arc perspective effect
        let visualY = bag.by + bag.bz * 0.50
        bag.node.position   = CGPoint(x: bag.bx, y: visualY)
        bag.shadow.position = CGPoint(x: bag.bx + bag.bz * 0.08, y: bag.by)

        let heightScale = 1.0 + bag.bz * 0.012
        bag.node.setScale(bag.baseScale * heightScale)
        bag.shadow.alpha   = max(0.08, 0.35 - bag.bz * 0.005)
        bag.shadow.setScale(max(0.5, 1.0 - bag.bz * 0.005))

        // Depth sort: bags closer to camera (lower on screen) appear in front
        bag.node.zPosition = 20 + bag.bz * 0.1 - bag.by * 0.02
    }

    private func checkIsOnBoard(_ bag: MiniGameBag) -> Bool {
        abs(bag.bx) <= boardHalfW &&
        bag.by >= boardY - boardHalfH &&
        bag.by <= boardY + boardHalfH
    }

    // MARK: - Throwing

    private func throwBag(owner: BagOwner, startX: CGFloat, vx: CGFloat, vy: CGFloat) {
        let bag = MiniGameBag(owner: owner, startX: startX, startY: throwLineY)
        bag.vx = vx
        bag.vy = vy
        bag.vz = vzInitial

        let speed = sqrt(vx * vx + vy * vy)
        bag.rotV = (Bool.random() ? 1.0 : -1.0) * (0.04 + speed * 0.015)

        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)

        if owner == .player {
            playerBagsThrown += 1
            lastThrower = .player
        } else {
            aiBagsThrown += 1
            lastThrower = .ai
        }

        gameState = .resolving
        turnIndicator?.isHidden = true
    }

    // MARK: - AI

    private func aiThrow() {
        guard gameState == .aiTurn, aiBagsThrown < bagsPerPlayer else { return }

        // Aim at the hole — rain makes both players less accurate
        let noiseFactor: CGFloat = rainActive ? 2.6 : 1.8
        let noise: CGFloat = holeRadius * noiseFactor
        let aimX = holeCenter.x + CGFloat.random(in: -noise...noise)
        let aimY = holeCenter.y + CGFloat.random(in: -noise * 0.5...noise * 0.5)

        let startX = CGFloat.random(in: -targetRange * 0.55...targetRange * 0.55)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 93 frames

        let vx = (aimX - startX) / flightFrames
        let vy = (aimY - throwLineY) / flightFrames

        throwBag(owner: .ai, startX: startX, vx: vx, vy: vy)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Tutorial overlay consumes all input until dismissed
        if tutorialActive { handleButtonTap(at: loc); return }

        // Quit-confirm modal consumes all input until resolved
        if confirmingQuit { handleButtonTap(at: loc); return }

        guard gameState == .playerTurn else {
            // Allow tapping game-over buttons in any state
            handleButtonTap(at: loc)
            return
        }

        // Check UI buttons first
        if handleButtonTap(at: loc) { return }

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
        guard let touch = touches.first, let start = touchStart, let line = aimingLine else { return }
        let loc = touch.location(in: self)
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

        if gameState != .playerTurn {
            handleButtonTap(at: end)
            touchStart = nil
            return
        }

        if handleButtonTap(at: end) { touchStart = nil; return }

        guard let start = touchStart else { return }
        touchStart = nil

        guard playerBagsThrown < bagsPerPlayer else { return }

        let dx = end.x - start.x
        let dy = end.y - start.y

        throwBag(owner: .player,
                 startX: turnIndicator?.position.x ?? 0,
                 vx: dx * powerScale,
                 vy: dy * powerScale)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimingLine?.removeFromParent()
        aimingLine = nil
        touchStart = nil
    }

    // Returns true if a named button was tapped (consuming the touch).
    // Uses nodes(at:) so nested buttons (inside panels) are found correctly.
    @discardableResult
    private func handleButtonTap(at location: CGPoint) -> Bool {
        for node in nodes(at: location) {
            var n: SKNode? = node
            while let current = n {
                switch current.name {
                case "closeButton":
                    showConfirmQuit()
                    return true
                case "confirmQuitBtn":
                    hideConfirmPanel()
                    dismissScene(playerWon: false)
                    return true
                case "cancelQuitBtn":
                    hideConfirmPanel()
                    return true
                case "tutorialDismissBtn":
                    hideTutorial()
                    return true
                case "playAgainBtn":
                    playerScore = 0
                    aiScore     = 0
                    roundNumber = 0
                    if rainActive { deactivateRain() }
                    rollRainScenario()
                    startRound()
                    return true
                case "exitBtn":
                    dismissScene(playerWon: playerScore > aiScore)
                    return true
                default:
                    n = current.parent
                }
            }
        }
        return false
    }

    // MARK: - Effects

    private func showHoleEffect(at pos: CGPoint) {
        let flash = SKSpriteNode(color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 0.9),
                                 size: CGSize(width: holeRadius * 1.5, height: holeRadius * 1.5))
        flash.position = pos
        flash.zPosition = 50
        gameWorldNode.addChild(flash)

        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.2, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.28),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Game-Over Panel

    private func showGameOverPanel(playerWon: Bool) {
        messageNode?.removeFromParent()

        let panel = SKNode()
        panel.zPosition = 1000

        let panelW = size.width * 0.82
        let panelH = size.height * 0.52
        let backing = SKSpriteNode(color: SKColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 0.94),
                                   size: CGSize(width: panelW, height: panelH))
        panel.addChild(backing)

        // Pixel-art border
        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        panel.addChild(border)

        let fs = max(6, size.width * 0.050)

        // Result title
        let title = makeLabel(
            text: playerWon ? "YOU WIN!" : "BOT WINS!",
            size: fs * 1.10,
            color: playerWon
                ? SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1)
                : SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        title.position = CGPoint(x: 0, y: panelH * 0.28)
        panel.addChild(title)

        // Final score
        let scoreLbl = makeLabel(
            text: "YOU \(playerScore)  —  \(aiScore) BOT",
            size: fs * 0.80,
            color: SKColor(white: 0.80, alpha: 1))
        scoreLbl.position = CGPoint(x: 0, y: panelH * 0.06)
        panel.addChild(scoreLbl)

        // Win target reminder
        let targetLbl = makeLabel(
            text: "FIRST TO \(winScore)",
            size: max(5, fs * 0.60),
            color: SKColor(white: 0.50, alpha: 1))
        targetLbl.position = CGPoint(x: 0, y: -panelH * 0.08)
        panel.addChild(targetLbl)

        // Play Again
        let playBtn = makeButton(label: "PLAY AGAIN",
                                 fg: .white,
                                 bg: SKColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1),
                                 size: CGSize(width: panelW * 0.60, height: fs * 1.8))
        playBtn.position = CGPoint(x: 0, y: -panelH * 0.25)
        playBtn.name = "playAgainBtn"
        panel.addChild(playBtn)

        // Exit
        let exitBtn = makeButton(label: "EXIT",
                                 fg: .white,
                                 bg: SKColor(red: 0.42, green: 0.10, blue: 0.10, alpha: 1),
                                 size: CGSize(width: panelW * 0.40, height: fs * 1.8))
        exitBtn.position = CGPoint(x: 0, y: -panelH * 0.38)
        exitBtn.name = "exitBtn"
        panel.addChild(exitBtn)

        addChild(panel)
        messageNode = panel

        // Fade in
        panel.alpha = 0
        panel.run(SKAction.fadeIn(withDuration: 0.30))
    }

    private func showRoundResultMessage(roundPlayer: Int, roundAI: Int) {
        let net = roundPlayer - roundAI
        let text: String
        if net > 0      { text = "+\(net) YOU" }
        else if net < 0 { text = "+\(abs(net)) BOT" }
        else            { text = "WASH" }

        let lbl = makeLabel(text: text, size: max(6, size.width * 0.055),
                            color: net >= 0
                                ? SKColor(red: 0.9, green: 0.42, blue: 0.42, alpha: 1)
                                : SKColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1))
        lbl.position   = CGPoint(x: 0, y: 0)
        lbl.zPosition  = 800
        lbl.alpha      = 0
        addChild(lbl)

        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: 1.4),
            SKAction.fadeOut(withDuration: 0.30),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - HUD updates

    private func updateScoreLabels() {
        playerScoreLabel?.text = "YOU: \(playerScore)"
        aiScoreLabel?.text     = "BOT: \(aiScore)"
    }

    private func updateRoundLabels() {
        // Show live per-round bag counts in bottom chrome
        (childNode(withName: "rndPlayerLabel") as? SKLabelNode)?.text =
            playerBagsThrown > 0 ? "▪\(playerBagsThrown)/\(bagsPerPlayer)" : ""
        (childNode(withName: "rndAILabel") as? SKLabelNode)?.text =
            aiBagsThrown > 0 ? "\(aiBagsThrown)/\(bagsPerPlayer)▪" : ""
    }

    private func updateTurnIndicator() {
        switch gameState {
        case .playerTurn:
            turnIndicator?.color = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
            turnIndicator?.isHidden = false
        case .aiTurn:
            turnIndicator?.color = SKColor(red: 0.30, green: 0.50, blue: 0.90, alpha: 1)
            turnIndicator?.isHidden = false
        default:
            turnIndicator?.isHidden = true
        }
    }

    private func updateWindLabel() {
        let strength = abs(wind.dx)
        let windText: String
        if strength < 0.30 {
            windText = "CALM"
        } else {
            let arrow = wind.dx > 0 ? ">" : "<"
            windText = "\(arrow) \(String(format: "%.1f", strength))"
        }
        windLabel?.text = rainActive ? "RAIN | \(windText)" : windText
        windLabel?.fontColor = rainActive
            ? SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1)
            : SKColor(white: 0.75, alpha: 1)
    }

    // MARK: - Rain

    private func rollRainScenario() {
        rainStartRound = -1
        rainEndRound   = Int.max

        // 40% chance of rain this game
        guard Int.random(in: 0..<10) < 4 else { return }

        rainStartRound = Int.random(in: 1...2)   // rain begins round 1 or 2
        let wholeGame = Bool.random()
        if !wholeGame {
            let duration = Int.random(in: 1...2)
            rainEndRound = rainStartRound + duration
        }
    }

    private func activateRain() {
        rainActive = true
        spawnRainParticles()
        addBoardWetOverlay()
        showRainAnnouncement()
        updateWindLabel()
        // PLACEHOLDER: add rain_start.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("rain_start.wav", waitForCompletion: false))
    }

    private func deactivateRain() {
        rainActive = false

        rainParticleNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.6),
            SKAction.removeFromParent(),
        ]))
        rainParticleNode = nil

        boardRainOverlay?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent(),
        ]))
        boardRainOverlay = nil

        let cleared = makeLabel(text: "RAIN STOPPED",
                                size: max(5, size.width * 0.042),
                                color: SKColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 1))
        cleared.position  = CGPoint(x: 0, y: size.height * 0.12)
        cleared.zPosition = 800
        cleared.alpha     = 0
        addChild(cleared)
        cleared.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: 1.2),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))

        updateWindLabel()
    }

    private func spawnRainParticles() {
        let container = SKNode()
        // Add directly to the scene, not to gameWorldNode (SKEffectNode).
        // Children that move far off-screen inside an SKEffectNode expand its render
        // bounds, which shifts the entire pixellated world — hence the "view moves up"
        // bug when rain starts.
        container.zPosition = 100  // above game world, below chrome at 500
        addChild(container)
        rainParticleNode = container

        let w = size.width
        let h = size.height
        let count = 60

        for _ in 0..<count {
            let drop = SKSpriteNode(
                color: SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 0.60),
                size: CGSize(width: 2, height: 10))
            drop.zRotation = -0.12   // slight diagonal slant

            let startX = CGFloat.random(in: -w / 2 ... w / 2)
            let startY = CGFloat.random(in: -h / 2 ... h / 2)
            drop.position = CGPoint(x: startX, y: startY)
            container.addChild(drop)

            let duration = TimeInterval(CGFloat.random(in: 0.22...0.48))
            let fallDist = h + 30
            let driftX   = fallDist * -0.12

            let resetAction = SKAction.customAction(withDuration: 0) { [weak drop] _, _ in
                drop?.position = CGPoint(
                    x: CGFloat.random(in: -w / 2 ... w / 2),
                    y: h / 2 + 15)
            }

            let cycle = SKAction.sequence([
                SKAction.moveBy(x: driftX, y: -fallDist, duration: duration),
                resetAction,
            ])

            let delay = SKAction.wait(forDuration: TimeInterval(CGFloat.random(in: 0...0.5)))
            drop.run(SKAction.sequence([delay, SKAction.repeatForever(cycle)]))
        }
    }

    private func addBoardWetOverlay() {
        let overlay = SKSpriteNode(
            color: SKColor(red: 0.22, green: 0.42, blue: 0.72, alpha: 0.30),
            size: CGSize(width: boardHalfW * 2, height: boardHalfH * 2))
        overlay.position  = CGPoint(x: 0, y: boardY)
        overlay.zPosition = 8
        gameWorldNode.addChild(overlay)
        boardRainOverlay = overlay

        // Subtle shimmer to suggest wet surface
        let shimmer = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.38, duration: 0.9),
            SKAction.fadeAlpha(to: 0.22, duration: 0.9),
        ])
        overlay.run(SKAction.repeatForever(shimmer))
    }

    private func showRainAnnouncement() {
        let lbl = makeLabel(text: "RAIN! SLIPPERY!",
                            size: max(6, size.width * 0.048),
                            color: SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1))
        lbl.position  = CGPoint(x: 0, y: size.height * 0.12)
        lbl.zPosition = 800
        lbl.alpha     = 0
        addChild(lbl)

        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.28),
            SKAction.wait(forDuration: 1.5),
            SKAction.fadeOut(withDuration: 0.38),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - First-time Tutorial

    private func showFirstTimeTutorial() {
        tutorialActive = true
        print("🎓 Cornhole tutorial overlay added (zPosition 2000)")

        let panelW = size.width  * 0.84
        let panelH = size.height * 0.60
        let fs     = max(5, size.width * 0.040)

        let overlay = SKNode()
        overlay.zPosition = 2000
        overlay.name      = "tutorialOverlay"

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.78),
                               size: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.addChild(dim)

        let panel = SKSpriteNode(color: SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.97),
                                 size: CGSize(width: panelW, height: panelH))
        overlay.addChild(panel)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        overlay.addChild(border)

        let title = makeLabel(text: "CORNHOLE!", size: fs * 1.1,
                              color: SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1))
        title.position = CGPoint(x: 0, y: panelH * 0.34)
        overlay.addChild(title)

        let instructions: [(String, CGFloat)] = [
            ("Swipe to aim \u{2192} release to throw", panelH * 0.18),
            ("Distance = power",                        panelH * 0.06),
            ("Hole = 3 pts \u{00B7} Board = 1 pt",     -panelH * 0.06),
            ("First to 11 wins!",                       -panelH * 0.18),
        ]
        for (text, y) in instructions {
            let lbl = makeLabel(text: text, size: fs * 0.72,
                                color: SKColor(white: 0.82, alpha: 1))
            lbl.position = CGPoint(x: 0, y: y)
            overlay.addChild(lbl)
        }

        let gotIt = makeButton(label: "GOT IT!",
                               fg: .white,
                               bg: SKColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1),
                               size: CGSize(width: panelW * 0.55, height: fs * 1.9))
        gotIt.position = CGPoint(x: 0, y: -panelH * 0.36)
        gotIt.name     = "tutorialDismissBtn"
        overlay.addChild(gotIt)

        overlay.alpha = 0
        addChild(overlay)
        overlay.run(.fadeIn(withDuration: 0.25))
    }

    private func hideTutorial() {
        tutorialActive = false
        childNode(withName: "tutorialOverlay")?.run(.sequence([
            .fadeOut(withDuration: 0.20),
            .removeFromParent(),
        ]))
        startRound()
    }

    // MARK: - Quit Confirmation

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true

        let panelW = size.width  * 0.70
        let panelH = size.height * 0.30
        let fs     = max(5, size.width * 0.042)

        let panel = SKNode()
        panel.zPosition = 3000
        panel.name      = "confirmPanel"

        let bg = SKSpriteNode(color: SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.97),
                              size: CGSize(width: panelW, height: panelH))
        panel.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        panel.addChild(border)

        let question = makeLabel(text: "QUIT GAME?", size: fs,
                                 color: SKColor(white: 0.88, alpha: 1))
        question.position = CGPoint(x: 0, y: panelH * 0.22)
        panel.addChild(question)

        let cancelBtn = makeButton(label: "CANCEL",
                                   fg: .white,
                                   bg: SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                                   size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        cancelBtn.position = CGPoint(x: -panelW * 0.24, y: -panelH * 0.22)
        cancelBtn.name     = "cancelQuitBtn"
        panel.addChild(cancelBtn)

        let quitBtn = makeButton(label: "QUIT",
                                 fg: .white,
                                 bg: SKColor(red: 0.50, green: 0.10, blue: 0.10, alpha: 1),
                                 size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        quitBtn.position = CGPoint(x: panelW * 0.24, y: -panelH * 0.22)
        quitBtn.name     = "confirmQuitBtn"
        panel.addChild(quitBtn)

        panel.alpha = 0
        addChild(panel)
        confirmPanel = panel
        panel.run(.fadeIn(withDuration: 0.18))
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        let transition = SKTransition.push(with: .down, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(prev, transition: transition)
    }
}
