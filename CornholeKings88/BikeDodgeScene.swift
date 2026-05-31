import SpriteKit
import UIKit

// MARK: - Game state
private enum BikeGameState { case menu, countdown, racing, gameOver, victory }

// MARK: - Entity models
private struct RacerData {
    enum Kind { case player, pink, green }
    var kind: Kind
    var distanceRemaining: CGFloat = 5.0
    var speed: CGFloat = 0
    var x: CGFloat = 0
    var xVelocity: CGFloat = 0
    var hearts: Int = 3
    var maxHearts: Int = 5
    var isInvincible: Bool = false
    var invTimer: CGFloat = 0
    var isCrashing: Bool = false
    var crashTimer: CGFloat = 0
    var isBoosting: Bool = false
    var boostTimer: CGFloat = 0
    var isJumping: Bool = false
    var jumpTimer: CGFloat = 0
    var finished: Bool = false
    var finishRank: Int = 0
    // AI only
    var targetLaneX: CGFloat = 0
    var errorCooldown: CGFloat = 0
}

private struct JumpTruckData {
    var x: CGFloat
    var screenY: CGFloat
    var forwardSpeed: CGFloat
    var node: SKNode
    var isActive: Bool = true
    var hasLaunched: Bool = false
}

private struct CarData {
    var x: CGFloat
    var screenY: CGFloat
    var forwardSpeed: CGFloat
    var node: SKNode
    var isActive: Bool = true
}

private struct BeanBagData {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var node: SKSpriteNode
    var isActive: Bool = true
}

private struct PickupData {
    enum Kind { case heart, boost }
    var kind: Kind
    var x: CGFloat
    var screenY: CGFloat
    var node: SKNode
    var isActive: Bool = true
}

private struct BullyKidData {
    var screenX: CGFloat
    var screenY: CGFloat
    var node: SKNode
    var armNode: SKSpriteNode
    var facingRight: Bool   // true = left-side kid faces right (toward road)
    var isAnimating: Bool = false
}

// MARK: - Main Scene
final class BikeDodgeScene: SKScene {

    // MARK: - Public
    weak var bikeDodgeDelegate: BikeDodgeSceneDelegate?
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    /// True only when launched from story mode; gates prize display + the world-map unlock.
    var awardsRewards: Bool = false

    // MARK: - Layout
    private var W: CGFloat = 0, H: CGFloat = 0
    private var roadLeft:  CGFloat = 0, roadRight: CGFloat = 0
    private var roadWidth: CGFloat = 0, laneWidth: CGFloat = 0
    private var laneCenter: [CGFloat] = [0, 0, 0]
    private var playerScreenY: CGFloat = 0

    // MARK: - Speed constants
    private let baseSpeed:    CGFloat = 160
    private let maxSpeed:     CGFloat = 360
    private let boostMult:    CGFloat = 3.2
    private let accel:        CGFloat = 28
    private let steerAccel:   CGFloat = 310
    private let maxSteerVel:  CGFloat = 210
    private let distPerPx:    CGFloat = 1.0 / 11_000   // miles per scene-pt scroll
    private let distToPixScale: CGFloat = 1_500         // scene-pts per mile
    private let brakeDecel:   CGFloat = 420             // speed units/s lost while braking

    // MARK: - Game state
    private var gState:     BikeGameState = .menu
    private var lastTime:   TimeInterval  = 0
    private var elapsed:    CGFloat = 0
    private var cdValue:    Int     = 3
    private var cdTimer:    CGFloat = 0
    private var finishCount: Int    = 0
    private var timeSinceLastCrash: CGFloat = 0
    private var finishLineNode: SKNode?
    private var finishLineSpawned = false

    // MARK: - Racers
    private var pr = RacerData(kind: .player)
    private var pk = RacerData(kind: .pink)
    private var gr = RacerData(kind: .green)

    // MARK: - Sprites
    private var playerSprite: SKSpriteNode!
    private var pinkSprite:   SKSpriteNode!
    private var greenSprite:  SKSpriteNode!
    private var playerBoostNode: SKNode?
    private var pinkBoostNode:   SKNode?
    private var greenBoostNode:  SKNode?

    // MARK: - Road
    private var roadBG1: SKSpriteNode!
    private var roadBG2: SKSpriteNode!

    // MARK: - Entities
    private var cars:       [CarData]       = []
    private var bags:       [BeanBagData]   = []
    private var pickups:    [PickupData]    = []
    private var jumpTrucks: [JumpTruckData] = []
    private var bullyKids:  [BullyKidData]  = []

    // MARK: - Jump truck config
    private var jumpTruckTimer:    CGFloat = 0
    private var jumpTruckInterval: CGFloat = 20.0   // first truck after ~20s
    private var jumpTrucksSpawned: Int     = 0
    private let maxJumpTrucks:     Int     = 2
    private var jumpBagsEarned:    Int     = 0
    private let jumpDuration:      CGFloat = 1.6

    // MARK: - Spawn timers
    private var carTimer:  CGFloat = 1.5,  carInterval:  CGFloat = 2.5
    private var pkTimer:   CGFloat = 4.0,  pkInterval:   CGFloat = 5.0
    private var bagTimer:  CGFloat = 2.0,  bagInterval:  CGFloat = 3.0

    // MARK: - Input
    private var steerLeft  = false
    private var steerRight = false
    private var isBraking  = false
    private var leftTouches:  Set<UITouch> = []
    private var rightTouches: Set<UITouch> = []
    private var brakeTouches: Set<UITouch> = []

    // MARK: - HUD
    private var hudPanelNode:    SKShapeNode!
    private var bottomHudNode:   SKShapeNode?
    private var distLabel:       SKLabelNode!
    private var timeLabel:       SKLabelNode!
    private var heartSprites:    [SKLabelNode] = []
    private var pauseBtn:        SKSpriteNode!
    private var closeBtn:        SKSpriteNode!
    private var minimapBG:       SKShapeNode!
    private var mmDots:          [SKShapeNode] = []
    private var brakeButtonNode: SKSpriteNode?
    private var brakeFrame:      CGRect = .zero
    private var pauseBtnFrame:   CGRect = .zero
    private var closeBtnFrame:   CGRect = .zero
    private var confirmingQuit = false
    private var confirmPanel: SKNode?
    private var mmBottom:    CGFloat = 0, mmHeight: CGFloat = 0

    // MARK: - Pause
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?

    // MARK: - Overlay
    private var overlayNode:    SKNode?
    private var countdownLabel: SKLabelNode?

    // MARK: - Car colors
    private static let carColors: [UIColor] = [
        UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1),
        UIColor(red: 0.15, green: 0.25, blue: 0.70, alpha: 1),
        UIColor(red: 0.65, green: 0.60, blue: 0.10, alpha: 1),
        UIColor(red: 0.45, green: 0.20, blue: 0.55, alpha: 1),
        UIColor(white: 0.75, alpha: 1),
        UIColor(red: 0.20, green: 0.55, blue: 0.20, alpha: 1),
    ]

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        roadWidth = W * 0.64
        roadLeft  = -roadWidth / 2
        roadRight =  roadWidth / 2
        laneWidth = roadWidth / 3
        laneCenter = [roadLeft + laneWidth * 0.5, 0, roadRight - laneWidth * 0.5]
        playerScreenY = -H * 0.19
        backgroundColor = SKColor(red: 0.14, green: 0.40, blue: 0.10, alpha: 1)

        setupRoad()
        setupBikes()
        setupBullyKids()
        setupHUD()
        setupMinimap()
        showStartMenu()
        addCrtOverlay()
    }

    // MARK: - Road
    private func setupRoad() {
        let tex = makeRoadTexture()
        let sz  = CGSize(width: roadWidth, height: H)
        roadBG1 = SKSpriteNode(texture: tex, size: sz)
        roadBG1.position  = .zero; roadBG1.zPosition = -5; addChild(roadBG1)
        roadBG2 = SKSpriteNode(texture: tex, size: sz)
        roadBG2.position  = CGPoint(x: 0, y: H); roadBG2.zPosition = -5; addChild(roadBG2)
    }

    private func makeRoadTexture() -> SKTexture {
        let iw = roadWidth, ih = H
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: iw, height: ih), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.20, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: iw, height: ih))
            c.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
            c.fill(CGRect(x: 0,    y: 0, width: 4, height: ih))
            c.fill(CGRect(x: iw-4, y: 0, width: 4, height: ih))
            c.setStrokeColor(UIColor(red: 0.95, green: 0.85, blue: 0.10, alpha: 1).cgColor)
            c.setLineWidth(3)
            c.setLineDash(phase: 0, lengths: [20, 10])
            for lx in [iw / 3, iw * 2 / 3] {
                c.move(to: CGPoint(x: lx, y: 0)); c.addLine(to: CGPoint(x: lx, y: ih)); c.strokePath()
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - Bikes
    private func setupBikes() {
        let cyanC  = UIColor(red: 0.10, green: 0.85, blue: 0.90, alpha: 1)
        let pinkC  = UIColor(red: 0.95, green: 0.30, blue: 0.60, alpha: 1)
        let greenC = UIColor(red: 0.20, green: 0.85, blue: 0.35, alpha: 1)

        pr.x = laneCenter[1]; pr.speed = baseSpeed
        if HeartsManager.shared.currentHearts <= 0 { HeartsManager.shared.refill() }
        pr.hearts    = HeartsManager.shared.currentHearts
        pr.maxHearts = HeartsManager.shared.maxHearts
        pk.x = laneCenter[0]; pk.speed = baseSpeed; pk.targetLaneX = laneCenter[0]
        gr.x = laneCenter[2]; gr.speed = baseSpeed; gr.targetLaneX = laneCenter[2]

        playerSprite = makeBikeSprite(color: cyanC)
        playerSprite.position  = CGPoint(x: pr.x, y: playerScreenY)
        playerSprite.zPosition = 10; addChild(playerSprite)

        pinkSprite = makeBikeSprite(color: pinkC)
        pinkSprite.position  = CGPoint(x: pk.x, y: screenYFor(pk))
        pinkSprite.zPosition = 10; addChild(pinkSprite)

        greenSprite = makeBikeSprite(color: greenC)
        greenSprite.position  = CGPoint(x: gr.x, y: screenYFor(gr))
        greenSprite.zPosition = 10; addChild(greenSprite)
    }

    private func makeBikeSprite(color: UIColor) -> SKSpriteNode {
        let bw: CGFloat = 22, bh: CGFloat = 34
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: bw, height: bh), format: fmt).image { ctx in
            let c = ctx.cgContext
            let tire = UIColor(white: 0.17, alpha: 1).cgColor
            let rim  = UIColor(white: 0.46, alpha: 1).cgColor
            let hub  = UIColor(white: 0.68, alpha: 1).cgColor
            let bar  = UIColor(white: 0.82, alpha: 1).cgColor
            let grip = UIColor(white: 0.50, alpha: 1).cgColor
            let sad  = UIColor(white: 0.88, alpha: 1).cgColor

            // ── Front wheel (top of sprite = front of bike) ──────────
            c.setFillColor(tire); c.fillEllipse(in: CGRect(x: 4,  y: 0,  width: 14, height: 7))
            c.setFillColor(rim);  c.fillEllipse(in: CGRect(x: 6,  y: 1,  width: 10, height: 5))
            c.setFillColor(hub);  c.fillEllipse(in: CGRect(x: 9,  y: 1,  width: 4,  height: 4))

            // ── Fork / stem ───────────────────────────────────────────
            c.setFillColor(color.cgColor)
            c.fill(CGRect(x: 9, y: 6, width: 4, height: 5))

            // ── Handlebars ────────────────────────────────────────────
            c.setFillColor(bar);  c.fill(CGRect(x: 2,  y: 10, width: 18, height: 2))
            c.setFillColor(grip); c.fill(CGRect(x: 2,  y: 12, width: 3,  height: 2))
            c.setFillColor(grip); c.fill(CGRect(x: 17, y: 12, width: 3,  height: 2))

            // ── Top tube (frame above rider) ──────────────────────────
            c.setFillColor(color.cgColor)
            c.fill(CGRect(x: 9, y: 11, width: 4, height: 3))

            // ── Rider (jersey matches bike color) ─────────────────────
            c.setFillColor(color.cgColor)
            c.fillEllipse(in: CGRect(x: 7, y: 13, width: 8, height: 9))
            c.setFillColor(UIColor(white: 1.0, alpha: 0.22).cgColor)
            c.fillEllipse(in: CGRect(x: 8, y: 14, width: 3, height: 4))

            // ── Seat tube ─────────────────────────────────────────────
            c.setFillColor(color.cgColor)
            c.fill(CGRect(x: 9, y: 21, width: 4, height: 4))

            // ── Saddle ────────────────────────────────────────────────
            c.setFillColor(sad)
            c.fillEllipse(in: CGRect(x: 5, y: 22, width: 12, height: 5))

            // ── Rear wheel (bottom of sprite = rear of bike) ──────────
            c.setFillColor(tire); c.fillEllipse(in: CGRect(x: 4, y: 27, width: 14, height: 7))
            c.setFillColor(rim);  c.fillEllipse(in: CGRect(x: 6, y: 28, width: 10, height: 5))
            c.setFillColor(hub);  c.fillEllipse(in: CGRect(x: 9, y: 29, width: 4,  height: 4))
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return SKSpriteNode(texture: tex, size: CGSize(width: bw, height: bh))
    }

    // MARK: - HUD (Bit-Wood Brawler design system)

    // Design-system colors
    private static let dsPrimaryContainer = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1)  // #1a0a04
    private static let dsSurfaceLowest    = SKColor(red: 0.063, green: 0.055, blue: 0.051, alpha: 1)  // #100e0d
    private static let dsSecondaryGold    = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)  // #f0c060
    private static let dsGoldDim          = SKColor(red: 0.651, green: 0.502, blue: 0.251, alpha: 1)  // #a68040
    private static let dsHeartRed         = SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1)  // #d4441e
    private static let dsTimerBlue        = SKColor(red: 0.353, green: 0.612, blue: 0.831, alpha: 1)  // #5a9cd4
    private static let dsIronGray         = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1)  // #595959
    private static let dsErrorContainer   = SKColor(red: 0.576, green: 0.0,   blue: 0.039, alpha: 1)  // #93000a
    private static let dsOnErrorContainer = SKColor(red: 1.0,   green: 0.855, blue: 0.839, alpha: 1)  // #ffdad6

    private func setupHUD() {
        let topInset = self.view?.safeAreaInsets.top ?? 0
        let panelH: CGFloat = 48
        let panelTopY: CGFloat = H / 2 - topInset
        let hudY: CGFloat = panelTopY - panelH / 2

        // Solid dark wood ribbon — #1a0a04
        let panelRect = CGRect(x: -W / 2, y: panelTopY - panelH, width: W, height: panelH)
        hudPanelNode = SKShapeNode(rect: panelRect)
        hudPanelNode.fillColor   = Self.dsPrimaryContainer
        hudPanelNode.strokeColor = .clear
        hudPanelNode.lineWidth   = 0
        hudPanelNode.zPosition   = 49
        addChild(hudPanelNode)

        // 2px solid gold bottom border
        let goldRule = SKSpriteNode(color: Self.dsSecondaryGold, size: CGSize(width: W, height: 2))
        goldRule.position  = CGPoint(x: 0, y: panelTopY - panelH + 1)
        goldRule.zPosition = 50
        addChild(goldRule)

        // Zone A — Pause button (32×32 hit, 24×24 icon)
        pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size      = CGSize(width: 24, height: 24)
        pauseBtn.position  = CGPoint(x: -W / 2 + 24, y: hudY)
        pauseBtn.zPosition = 51
        pauseBtn.name      = "pauseBtn"
        addChild(pauseBtn)

        // Zone C — Close button (right-most, replaces UIKit close)
        closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 24, height: 24)
        closeBtn.position  = CGPoint(x: W / 2 - 24, y: hudY)
        closeBtn.zPosition = 51
        closeBtn.name      = "closeBtn"
        addChild(closeBtn)

        // Cache 44pt-min tap targets for O(1) hit-testing in touchesBegan
        pauseBtnFrame = CGRect(x: -W / 2,        y: hudY - 24, width: 60, height: 48)
        closeBtnFrame = CGRect(x:  W / 2 - 60,   y: hudY - 24, width: 60, height: 48)

        // Zone B — Hearts row, centered; dist left of hearts, time right
        let heartSpacing: CGFloat = 20
        let heartFs: CGFloat = 18
        let startX = -(CGFloat(pr.maxHearts - 1) * heartSpacing) / 2
        let heartsHalfWidth = CGFloat(pr.maxHearts - 1) * heartSpacing / 2
        heartSprites.removeAll()
        for i in 0..<pr.maxHearts {
            let h = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            h.text = "♥"
            h.fontSize = heartFs
            h.fontColor = Self.dsHeartRed
            h.horizontalAlignmentMode = .center
            h.verticalAlignmentMode   = .center
            h.position  = CGPoint(x: startX + CGFloat(i) * heartSpacing, y: hudY - 1)
            h.zPosition = 51
            addChild(h)
            heartSprites.append(h)
        }

        // Distance — gold, left-aligned against the pause button
        distLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        distLabel.fontSize                = 9
        distLabel.fontColor               = Self.dsSecondaryGold
        distLabel.horizontalAlignmentMode = .left
        distLabel.verticalAlignmentMode   = .center
        distLabel.position  = CGPoint(x: -W / 2 + 50, y: hudY)
        distLabel.zPosition = 51
        addChild(distLabel)

        // Timer — blue, right-aligned against the close button
        timeLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        timeLabel.fontSize                = 9
        timeLabel.fontColor               = Self.dsTimerBlue
        timeLabel.horizontalAlignmentMode = .right
        timeLabel.verticalAlignmentMode   = .center
        timeLabel.position  = CGPoint(x: W / 2 - 50, y: hudY)
        timeLabel.zPosition = 51
        addChild(timeLabel)

        // Iron-bolt corner accents — just below the top HUD where it meets the play area
        addIronBolt(at: CGPoint(x: -W / 2 + 4, y: panelTopY - panelH - 6))
        addIronBolt(at: CGPoint(x:  W / 2 - 4, y: panelTopY - panelH - 6))

        setupBrakeButton()
        refreshHUD()
    }

    private func addIronBolt(at pos: CGPoint) {
        let bolt = SKSpriteNode(color: Self.dsIronGray, size: CGSize(width: 4, height: 4))
        bolt.position  = pos
        bolt.zPosition = 52
        addChild(bolt)
    }

    private func setupBrakeButton() {
        let bw: CGFloat = 144, bh: CGFloat = 48
        let bottomInset = self.view?.safeAreaInsets.bottom ?? 0
        let brakeY = -H / 2 + bottomInset + 48 + bh / 2 + 16 - 75  // above bottom HUD ribbon

        // Drop-shadow rectangle (offset 4,-4) — primary-container color
        let shadow = SKSpriteNode(color: Self.dsPrimaryContainer,
                                  size: CGSize(width: bw, height: bh))
        shadow.position  = CGPoint(x: 4, y: brakeY - 4)
        shadow.zPosition = 50
        shadow.name      = "brakeBtn"
        addChild(shadow)

        // Main button background — sharp rectangle, #93000a
        let bg = SKSpriteNode(color: Self.dsErrorContainer, size: CGSize(width: bw, height: bh))
        bg.position  = CGPoint(x: 0, y: brakeY)
        bg.zPosition = 51
        bg.name      = "brakeBtn"
        addChild(bg)
        brakeButtonNode = bg

        // 4px gold border (4 sharp sprites)
        let borders: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-bw / 2 + 2, 0,            4,  bh),
            ( bw / 2 - 2, 0,            4,  bh),
            ( 0,           bh / 2 - 2,  bw, 4),
            ( 0,          -bh / 2 + 2,  bw, 4),
        ]
        for (dx, dy, w, h) in borders {
            let edge = SKSpriteNode(color: Self.dsSecondaryGold,
                                    size: CGSize(width: w, height: h))
            edge.position  = CGPoint(x: dx, y: brakeY + dy)
            edge.zPosition = 52
            edge.name      = "brakeBtn"
            addChild(edge)
        }

        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text      = "BRAKE"
        lbl.fontSize  = 12
        lbl.fontColor = Self.dsOnErrorContainer
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center
        lbl.position  = CGPoint(x: 0, y: brakeY - 1)
        lbl.zPosition = 53
        lbl.name      = "brakeBtn"
        addChild(lbl)

        // Cache for O(1) hit-testing in touchesBegan (avoids nodes(at:) traversal per tap)
        brakeFrame = CGRect(x: -bw / 2, y: brakeY - bh / 2, width: bw, height: bh)
    }

    private func refreshHUD() {
        let m = Int(elapsed) / 60, s = Int(elapsed) % 60
        distLabel.text = String(format: "%.2fmi", max(0, pr.distanceRemaining))
        timeLabel.text = String(format: "%d:%02d", m, s)

        for (i, h) in heartSprites.enumerated() {
            let filled = i < pr.hearts
            h.text      = filled ? "♥" : "♡"
            h.fontColor = filled ? Self.dsHeartRed : Self.dsIronGray
        }
    }

    // MARK: - Minimap
    private func setupMinimap() {
        // 4px track per design spec (sharp pixel-art, no rounded corners)
        let barW: CGFloat = 4
        mmHeight = H * 0.68; mmBottom = -mmHeight / 2
        let barX = W / 2 - 22

        minimapBG = SKShapeNode(rect: CGRect(x: barX - barW / 2, y: mmBottom - 2,
                                             width: barW, height: mmHeight + 4))
        minimapBG.fillColor   = Self.dsIronGray
        minimapBG.strokeColor = Self.dsSecondaryGold.withAlphaComponent(0.5)
        minimapBG.lineWidth   = 1
        minimapBG.zPosition   = 50
        addChild(minimapBG)

        // 8×8 square dots — player slightly larger (10×10) with gold outline
        let dotColors: [SKColor] = [
            Self.dsTimerBlue,                                                // player
            SKColor(red: 1.0, green: 0.412, blue: 0.706, alpha: 1),          // pink rival #ff69b4
            SKColor(red: 0.196, green: 0.804, blue: 0.196, alpha: 1),        // green rival #32cd32
        ]
        for (i, col) in dotColors.enumerated() {
            let s: CGFloat = i == 0 ? 10 : 8
            let dot = SKShapeNode(rect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
            dot.fillColor   = col
            dot.strokeColor = i == 0 ? Self.dsSecondaryGold : .black
            dot.lineWidth   = i == 0 ? 2 : 1
            dot.position    = CGPoint(x: barX, y: mmBottom)
            dot.zPosition   = 52
            addChild(dot); mmDots.append(dot)
        }
    }

    private func updateMinimap() {
        let barX = W / 2 - 22
        let pairs: [(RacerData, Int)] = [(pr, 0), (pk, 1), (gr, 2)]
        for (racer, i) in pairs {
            let prog = 1.0 - racer.distanceRemaining / 5.0
            mmDots[i].position = CGPoint(x: barX, y: mmBottom + prog * mmHeight)
        }
    }

    // MARK: - Start menu
    private func showStartMenu() {
        let ov = buildOverlayContainer()
        let bg = SKShapeNode(rect: CGRect(x: -W/2, y: -H/2, width: W, height: H))
        bg.fillColor = SKColor(white: 0, alpha: 0.72); bg.strokeColor = .clear; ov.addChild(bg)

        ov.addChild(label("BEANBAG BIKE",     font: "PressStart2P-Regular", size: min(20, W/17), color: .yellow,  at: CGPoint(x:0, y:90)))
        ov.addChild(label("5 MILE RACE",      font: "PressStart2P-Regular", size: min(9, W/40),  color: .white,   at: CGPoint(x:0, y:48)))
        ov.addChild(label("STEER: HOLD LEFT OR RIGHT HALF", font: "PressStart2P-Regular",
                          size: min(7, W/50), color: SKColor(white:0.7,alpha:1), at: CGPoint(x:0,y:26)))
        ov.addChild(label("BRAKE: TAP CENTER BOTTOM BUTTON", font: "PressStart2P-Regular",
                          size: min(7, W/50), color: SKColor(white:0.7,alpha:1), at: CGPoint(x:0,y:9)))

        let start = label("▶  TAP TO START", font: "PressStart2P-Regular", size: min(13, W/26), color: .white, at: CGPoint(x:0, y:-40))
        start.name = "startBtn"
        start.run(.repeatForever(.sequence([.scale(to:1.06,duration:0.6),.scale(to:0.94,duration:0.6)])))
        ov.addChild(start)

        addChild(ov); overlayNode = ov
        gState = .menu

        // Auto-show the tutorial the first time the player ever opens this scene.
        if !TutorialManager.shared.hasSeen(TutorialManager.bike) {
            presentBikeTutorial(autoTriggered: true)
        }
    }

    // MARK: - Tutorial
    private func presentBikeTutorial(autoTriggered: Bool) {
        let steeringY = -H / 2 + H * 0.18
        let topInset    = self.view?.safeAreaInsets.top ?? 0
        let bottomInset = self.view?.safeAreaInsets.bottom ?? 0
        let heartsY   = H / 2 - topInset - 22
        let brakeHintY = -H / 2 + bottomInset + 36
        let steps: [TutorialStep] = [
            .card(title: "BEANBAG BIKE",
                  body:  "RACE 5 MILES! FINISH 1ST OUT OF 3 RIDERS TO WIN THE PRIZE."),
            .hint(at: CGPoint(x: 0, y: steeringY),
                  title: "STEERING",
                  body:  "HOLD THE LEFT OR RIGHT HALF OF THE SCREEN TO STEER YOUR BIKE."),
            .hint(at: CGPoint(x: 0, y: brakeHintY),
                  title: "BRAKE",
                  body:  "TAP THE BRAKE BUTTON TO SLOW DOWN. HOLD IT TO STOP COMPLETELY!"),
            .hint(at: CGPoint(x: 0, y: heartsY),
                  title: "HEARTS",
                  body:  "AVOID CARS AND BEANBAGS! EACH CRASH COSTS A HEART. RUN OUT AND YOUR RACE IS OVER."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) {
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.bike)
            }
        }
        addChild(overlay)
    }

    // MARK: - Countdown
    private func startCountdown() {
        overlayNode?.removeFromParent(); overlayNode = nil
        cdValue = 3; cdTimer = 0
        let lbl = label("3", font: "PressStart2P-Regular", size: min(60, W/5), color: .yellow, at: .zero)
        lbl.zPosition = 100; lbl.name = "cd"; addChild(lbl); countdownLabel = lbl
        gState = .countdown
    }

    private func updateCountdown(dt: CGFloat) {
        cdTimer += dt
        if cdTimer < 1.0 { return }
        cdTimer = 0; cdValue -= 1
        if cdValue <= 0 {
            countdownLabel?.removeFromParent(); countdownLabel = nil
            gState = .racing; return
        }
        countdownLabel?.text = cdValue == 1 ? "GO!" : "\(cdValue)"
        countdownLabel?.run(.sequence([.scale(to:1.4,duration:0.1),.scale(to:1.0,duration:0.3)]))
    }

    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        if isPausedGame || confirmingQuit { lastTime = currentTime; return }
        let dt = CGFloat(lastTime == 0 ? 0.016 : min(currentTime - lastTime, 0.033))
        lastTime = currentTime
        switch gState {
        case .menu:              return
        case .countdown:         updateCountdown(dt: dt)
        case .racing:            updateRacing(dt: dt)
        case .gameOver, .victory: return
        }
    }

    private func updateRacing(dt: CGFloat) {
        // Self-heal stuck touches — iOS occasionally drops touchesEnded for rapid taps,
        // which left both steer flags true and made forces cancel out.
        pruneStaleTouches()
        elapsed += dt
        updateSpeeds(dt: dt)
        updateRoad(dt: dt)
        updatePlayerSteering(dt: dt)
        updateAISteering(dt: dt)
        applyBumping()
        updateCarPositions(dt: dt)
        updateJumpTrucks(dt: dt)
        updateBullyKids(dt: dt)
        updateBagPositions(dt: dt)
        updatePickupPositions(dt: dt)
        updateInvincibility(dt: dt)
        updateCrashTimers(dt: dt)
        updateBoostTimers(dt: dt)
        spawnStep(dt: dt)
        checkCollisions()
        syncBikePositions()
        // Spawn when the finish line is exactly H*1.2 pts of road scroll away from
        // the player — uses distPerPx (not distToPixScale) so the line arrives at the
        // player's screen position precisely when distanceRemaining reaches 0.
        let finishLineTriggerDist = H * 1.2 * distPerPx
        if pr.distanceRemaining <= finishLineTriggerDist && !finishLineSpawned { spawnFinishLine() }
        updateFinishLine(dt: dt)
        refreshHUD()
        updateMinimap()
        checkRaceEnd()
    }

    // MARK: - Speed update
    private func updateSpeeds(dt: CGFloat) {
        if !pr.isCrashing {
            timeSinceLastCrash += dt
        }
        // Acceleration scales with no-crash streak: 3× accel by ~15s, capped at 3.5×.
        let accelMult = min(3.5, 1.0 + timeSinceLastCrash / 6.0)
        // Speed cap also grows with streak: up to +160 bonus pts after ~20s.
        let streakBonus: CGFloat = min(160, timeSinceLastCrash * 8)
        let playerAccel = accel * accelMult

        if !pr.isCrashing {
            let jumpCap: CGFloat = pr.isJumping ? (maxSpeed + streakBonus) * 1.8 : maxSpeed + streakBonus
            let cap = pr.isBoosting ? (maxSpeed + streakBonus) * boostMult : jumpCap
            if isBraking {
                pr.speed = max(0, pr.speed - brakeDecel * dt)
            } else {
                pr.speed = min(cap, pr.speed + playerAccel * dt)
            }
            pr.distanceRemaining = max(0, pr.distanceRemaining - pr.speed * distPerPx * dt)
        }
        // AI uses a fixed accel independent of player's no-crash streak.
        let aiAccel = accel * 2.2
        if !pk.isCrashing {
            let cap = pk.isBoosting ? maxSpeed * boostMult * 0.95 : maxSpeed * 1.15
            pk.speed = min(cap, pk.speed + aiAccel * dt)
            pk.distanceRemaining = max(0, pk.distanceRemaining - pk.speed * distPerPx * dt)
        }
        if !gr.isCrashing {
            let cap = gr.isBoosting ? maxSpeed * boostMult * 0.97 : maxSpeed * 1.20
            gr.speed = min(cap, gr.speed + aiAccel * dt)
            gr.distanceRemaining = max(0, gr.distanceRemaining - gr.speed * distPerPx * dt)
        }
    }

    // MARK: - Road scroll
    private func updateRoad(dt: CGFloat) {
        let s = pr.speed * dt
        roadBG1.position.y -= s; roadBG2.position.y -= s
        if roadBG1.position.y + H/2 < -H/2 { roadBG1.position.y = roadBG2.position.y + H }
        if roadBG2.position.y + H/2 < -H/2 { roadBG2.position.y = roadBG1.position.y + H }
    }

    // MARK: - Player steering
    private func updatePlayerSteering(dt: CGFloat) {
        guard !pr.isJumping else { return }
        if steerLeft  { pr.xVelocity -= steerAccel * dt }
        if steerRight { pr.xVelocity += steerAccel * dt }
        if !steerLeft && !steerRight { pr.xVelocity *= max(0, 1 - 6 * dt) }
        pr.xVelocity = pr.xVelocity.bikeClamp(-maxSteerVel...maxSteerVel)
        pr.x = (pr.x + pr.xVelocity * dt).bikeClamp(roadLeft + 10...roadRight - 10)
    }

    // MARK: - AI steering
    private func updateAISteering(dt: CGFloat) {
        updateSingleAI(racer: &pk, dt: dt)
        updateSingleAI(racer: &gr, dt: dt)
    }

    private func updateSingleAI(racer: inout RacerData, dt: CGFloat) {
        guard !racer.isCrashing else { return }
        racer.errorCooldown -= dt
        let myY = screenYFor(racer)
        var target = racer.targetLaneX

        // Dodge cars ahead
        for car in cars where car.isActive {
            let ahead = car.screenY - myY
            if ahead > 0 && ahead < 300 && abs(car.x - racer.x) < laneWidth * 1.0 {
                if racer.errorCooldown <= 0 && Float.random(in: 0...1) > 0.02 {
                    let curr = laneIndexFor(x: racer.targetLaneX)
                    let alt  = curr == 0 ? 1 : (curr == 2 ? 1 : (Bool.random() ? 0 : 2))
                    racer.targetLaneX = laneCenter[alt]
                    racer.errorCooldown = 0.7
                }
                target = racer.targetLaneX; break
            }
        }
        // Seek pickups
        for pu in pickups where pu.isActive {
            let ahead = pu.screenY - myY
            if ahead > -40 && ahead < 160 && abs(pu.x - racer.x) < laneWidth * 1.5 {
                target = pu.x; break
            }
        }

        let diff = target - racer.x
        racer.xVelocity += diff.bikeClamp(-steerAccel...steerAccel) * dt * 5
        racer.xVelocity *= max(0, 1 - 5 * dt)
        racer.xVelocity = racer.xVelocity.bikeClamp(-maxSteerVel...maxSteerVel)
        racer.x = (racer.x + racer.xVelocity * dt).bikeClamp(roadLeft + 10...roadRight - 10)
    }

    private func laneIndexFor(x: CGFloat) -> Int {
        laneCenter.enumerated().min(by: { abs($0.element - x) < abs($1.element - x) })!.offset
    }

    // MARK: - Bumping
    private func applyBumping() {
        let pyY = playerScreenY
        let pkY = screenYFor(pk)
        let grY = screenYFor(gr)
        var playerBumped = false

        func bump(_ r1: inout RacerData, y1: CGFloat, _ r2: inout RacerData, y2: CGFloat) {
            guard abs(y1 - y2) < 28 else { return }
            let overlap: CGFloat = 20 - abs(r1.x - r2.x)
            guard overlap > 0 else { return }
            let push = overlap / 2 + 1
            if r1.x < r2.x { r1.x -= push; r2.x += push }
            else            { r1.x += push; r2.x -= push }
            r1.x = r1.x.bikeClamp(roadLeft + 10...roadRight - 10)
            r2.x = r2.x.bikeClamp(roadLeft + 10...roadRight - 10)
            spawnSparks(at: CGPoint(x: (r1.x + r2.x) / 2, y: (y1 + y2) / 2))
            if r1.kind == .player || r2.kind == .player { playerBumped = true }
        }
        bump(&pr, y1: pyY, &pk, y2: pkY)
        bump(&pr, y1: pyY, &gr, y2: grY)
        bump(&pk, y1: pkY, &gr, y2: grY)
        if playerBumped { triggerBagHitHaptics() }
    }

    // MARK: - Sync sprite positions
    private func syncBikePositions() {
        playerSprite.position = CGPoint(x: pr.x, y: playerScreenY)
        pinkSprite.position   = CGPoint(x: pk.x, y: screenYFor(pk))
        greenSprite.position  = CGPoint(x: gr.x, y: screenYFor(gr))
        if !pr.isJumping { playerSprite.zRotation = (-pr.xVelocity / maxSteerVel) * 0.20 }
        if let n = playerBoostNode { n.position = CGPoint(x: pr.x, y: playerScreenY - playerSprite.size.height/2 - 8) }
        if let n = pinkBoostNode   { n.position = CGPoint(x: pk.x, y: screenYFor(pk) - pinkSprite.size.height/2 - 8) }
        if let n = greenBoostNode  { n.position = CGPoint(x: gr.x, y: screenYFor(gr) - greenSprite.size.height/2 - 8) }
    }

    // 0 at the start line, 1 at the finish line.
    private var raceProgress: CGFloat { (1.0 - pr.distanceRemaining / 5.0).bikeClamp(0...1) }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    // MARK: - Car spawn + update
    private func spawnStep(dt: CGFloat) {
        let p = raceProgress

        carTimer += dt
        if carTimer >= carInterval {
            carTimer = 0
            // Interval shrinks from [1.8, 3.5]s → [0.45, 0.90]s as the race progresses.
            carInterval = CGFloat.random(in: lerp(1.8, 0.45, p)...lerp(3.5, 0.90, p))
            spawnCar()
            // Past 55% distance a second car can spawn in the same tick.
            if p > 0.55 && Float.random(in: 0...1) < Float((p - 0.55) * 2.2) { spawnCar() }
        }
        pkTimer += dt
        if pkTimer >= pkInterval {
            pkTimer = 0; pkInterval = CGFloat.random(in: 3.5...7.0); spawnPickup()
        }
        bagTimer += dt
        if bagTimer >= bagInterval {
            bagTimer = 0
            // Interval shrinks from [5.0, 8.0]s → [0.80, 1.40]s as the race progresses,
            // keeping the first half sparse and ramping up pressure in the second half.
            bagInterval = CGFloat.random(in: lerp(5.0, 0.80, p)...lerp(8.0, 1.40, p))
            spawnBeanBag()
            // Past 70% distance a second bag can fly in the same tick (max ~45% chance).
            if p > 0.70 && Float.random(in: 0...1) < Float((p - 0.70) * 1.5) { spawnBeanBag() }
        }

        // Jump truck — up to 2 per race, first appears after 20% progress
        if jumpTrucksSpawned < maxJumpTrucks && p > 0.20 {
            jumpTruckTimer += dt
            if jumpTruckTimer >= jumpTruckInterval {
                jumpTruckTimer = 0
                jumpTruckInterval = CGFloat.random(in: 22.0...30.0)
                spawnJumpTruck()
            }
        }
    }

    private func spawnCar() {
        let lane = Int.random(in: 0..<3); let cx = laneCenter[lane]; let spY = H/2 + 50
        for c in cars where c.isActive {
            if abs(c.x - cx) < laneWidth * 0.6 && abs(c.screenY - spY) < 80 { return }
        }
        let cidx = Int.random(in: 0..<BikeDodgeScene.carColors.count)
        let n = makeCarNode(cidx: cidx)
        n.position = CGPoint(x: cx, y: spY); n.zPosition = 9; addChild(n)
        cars.append(CarData(x: cx, screenY: spY,
                            forwardSpeed: CGFloat.random(in: 40...100), node: n))
    }

    private func updateCarPositions(dt: CGFloat) {
        for i in cars.indices {
            guard cars[i].isActive else { continue }
            cars[i].screenY -= max(0, pr.speed - cars[i].forwardSpeed) * dt
            cars[i].node.position.y = cars[i].screenY
            if cars[i].screenY < -H/2 - 80 { cars[i].node.removeFromParent(); cars[i].isActive = false }
        }
        cars.removeAll { !$0.isActive }
    }

    private func makeCarNode(cidx: Int) -> SKNode {
        let col = BikeDodgeScene.carColors[cidx]
        let cw: CGFloat = 30, ch: CGFloat = 46
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: cw, height: ch), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
            for r in [CGRect(x:0,y:3,width:6,height:10), CGRect(x:cw-6,y:3,width:6,height:10),
                      CGRect(x:0,y:ch-13,width:6,height:10), CGRect(x:cw-6,y:ch-13,width:6,height:10)] {
                c.fill(r)
            }
            c.setFillColor(col.cgColor)
            c.fill(CGRect(x: 3, y: 4, width: cw-6, height: ch-8))
            c.setFillColor(col.withAlphaComponent(0.75).cgColor)
            c.fill(CGRect(x: 5, y: ch*0.28, width: cw-10, height: ch*0.36))
            c.setFillColor(UIColor(red:0.55,green:0.75,blue:0.92,alpha:0.80).cgColor)
            c.fill(CGRect(x: 6, y: ch*0.30, width: cw-12, height: ch*0.14))
            c.fill(CGRect(x: 6, y: ch*0.52, width: cw-12, height: ch*0.10))
            c.setFillColor(UIColor(red:1.0,green:0.95,blue:0.6,alpha:1).cgColor)
            c.fill(CGRect(x:5,   y:ch-6,width:7,height:4))
            c.fill(CGRect(x:cw-12,y:ch-6,width:7,height:4))
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return SKSpriteNode(texture: tex, size: CGSize(width: cw, height: ch))
    }

    // MARK: - Bean bag
    private func spawnBeanBag() {
        let targetRacer: RacerData = Float.random(in: 0...1) < 0.70 ? pr : (Bool.random() ? pk : gr)
        let targetX: CGFloat
        let targetY: CGFloat
        if targetRacer.kind == .player {
            targetX = pr.x; targetY = playerScreenY
        } else {
            let ty = screenYFor(targetRacer); guard abs(ty) < H/2 else { return }
            targetX = targetRacer.x; targetY = ty
        }

        // Pick a side, then find an idle kid on that side who is ahead of the target
        // and currently on-screen.  The bag spawns from the kid's hand position so the
        // throw animation and projectile origin always match.
        let fromLeft = Bool.random()
        guard let kidIdx = bullyKids.indices.filter({
            bullyKids[$0].facingRight == fromLeft &&
            !bullyKids[$0].isAnimating &&
            bullyKids[$0].screenY > targetY &&          // kid is ahead of (above) the target
            bullyKids[$0].screenY <  H / 2 + 80         // kid is on or just above screen
        }).min(by: {
            abs(bullyKids[$0].screenY - targetY) < abs(bullyKids[$1].screenY - targetY)
        }) else { return }   // no suitable kid — skip this throw

        // Bag originates from the kid's hand (arm tip ≈ 8 pts below shoulder on the road side)
        let kid = bullyKids[kidIdx]
        let sx = kid.screenX + (fromLeft ? 8 : -8)   // offset toward road
        let sy = kid.screenY - 5                      // hand height

        // Aim toward where the racer will be, with a small lateral lead
        let lead = targetRacer.xVelocity * 0.28
        let dx = targetX + lead - sx
        let dy = targetY - sy
        let dist = max(1, sqrt(dx * dx + dy * dy))
        let spd: CGFloat = 260

        let n = SKSpriteNode(color: SKColor(red: 0.15, green: 0.40, blue: 0.90, alpha: 1),
                             size: CGSize(width: 15, height: 15))
        n.position = CGPoint(x: sx, y: sy); n.zPosition = 12
        n.run(.repeatForever(.rotate(byAngle: .pi * 4, duration: 0.5))); addChild(n)
        bags.append(BeanBagData(x: sx, y: sy, vx: dx / dist * spd, vy: dy / dist * spd, node: n))
        triggerBullyThrow(fromLeft: fromLeft, kidIdx: kidIdx)
    }

    private func updateBagPositions(dt: CGFloat) {
        for i in bags.indices {
            guard bags[i].isActive else { continue }
            bags[i].x += bags[i].vx * dt; bags[i].y += bags[i].vy * dt
            bags[i].node.position = CGPoint(x: bags[i].x, y: bags[i].y)
            if bags[i].x < roadLeft - 60 || bags[i].x > roadRight + 60
                || bags[i].y < -H/2 - 50 || bags[i].y > H/2 + 60 {
                bags[i].node.removeFromParent(); bags[i].isActive = false
            }
        }
        bags.removeAll { !$0.isActive }
    }

    // MARK: - Bully Kids
    private func setupBullyKids() {
        let shirtColors: [UIColor] = [
            UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1),
            UIColor(red: 0.15, green: 0.35, blue: 0.80, alpha: 1),
            UIColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 1),
            UIColor(red: 0.20, green: 0.65, blue: 0.25, alpha: 1),
            UIColor(red: 0.65, green: 0.10, blue: 0.65, alpha: 1),
            UIColor(red: 0.80, green: 0.80, blue: 0.10, alpha: 1),
        ]
        // 3 per side; stagger initial y above the screen so they scroll in naturally.
        let stagger = H / 3
        var colorIdx = 0
        for slot in 0..<3 {
            for facingRight in [true, false] {
                let kidX: CGFloat = facingRight
                    ? roadLeft  - CGFloat.random(in: 14...22)
                    : roadRight + CGFloat.random(in: 14...22)
                let startY = H / 2 + CGFloat(slot) * stagger + CGFloat.random(in: 0...40)
                let (container, armNode) = makeBullyKid(
                    shirtColor: shirtColors[colorIdx % shirtColors.count],
                    facingRight: facingRight
                )
                colorIdx += 1
                container.position = CGPoint(x: kidX, y: startY)
                container.zPosition = 8
                container.yScale = -1
                addChild(container)
                // Arm idle sway only — no position bob (y is driven by updateBullyKids)
                startArmIdle(armNode: armNode, facingRight: facingRight,
                             delay: Double.random(in: 0...0.5))
                bullyKids.append(BullyKidData(screenX: kidX, screenY: startY,
                                              node: container, armNode: armNode,
                                              facingRight: facingRight))
            }
        }
    }

    private func updateBullyKids(dt: CGFloat) {
        let scroll = pr.speed * dt
        for i in bullyKids.indices {
            bullyKids[i].screenY -= scroll
            bullyKids[i].node.position.y = bullyKids[i].screenY
            // Recycle off-screen kids to a random distance ahead of the screen top.
            if bullyKids[i].screenY < -H / 2 - 60 {
                let newY = H / 2 + CGFloat.random(in: 40...160)
                bullyKids[i].screenY = newY
                bullyKids[i].node.position.y = newY
                // Allow the kid to throw again after respawning
                if bullyKids[i].isAnimating {
                    bullyKids[i].isAnimating = false
                    startArmIdle(armNode: bullyKids[i].armNode,
                                 facingRight: bullyKids[i].facingRight, delay: 0)
                }
            }
        }
    }

    private func makeBullyKid(shirtColor: UIColor, facingRight: Bool) -> (SKNode, SKSpriteNode) {
        let container = SKNode()
        let kw: CGFloat = 14, kh: CGFloat = 22
        let skin  = UIColor(red: 0.96, green: 0.76, blue: 0.58, alpha: 1)
        let hair  = UIColor(red: 0.20, green: 0.12, blue: 0.04, alpha: 1)
        let pants = UIColor(red: 0.14, green: 0.18, blue: 0.45, alpha: 1)
        let shoe  = UIColor(white: 0.12, alpha: 1)
        let fmt   = UIGraphicsImageRendererFormat(); fmt.scale = 1

        // Body texture — no road-facing arm (that's a separate animatable node).
        // Non-throwing arm drawn on the left side of texture so the xScale flip
        // puts it on the away-from-road side for both kid orientations.
        let bodyImg = UIGraphicsImageRenderer(
            size: CGSize(width: kw, height: kh), format: fmt
        ).image { ctx in
            let c = ctx.cgContext
            // Shoes
            c.setFillColor(shoe.cgColor)
            c.fill(CGRect(x: 1, y: 0, width: 5, height: 3))
            c.fill(CGRect(x: 8, y: 0, width: 5, height: 3))
            // Pants
            c.setFillColor(pants.cgColor)
            c.fill(CGRect(x: 2, y: 2, width: 10, height: 6))
            c.setFillColor(UIColor(red: 0.10, green: 0.14, blue: 0.38, alpha: 1).cgColor)
            c.fill(CGRect(x: 6, y: 2, width: 2, height: 6))          // crease
            // Shirt
            c.setFillColor(shirtColor.cgColor)
            c.fill(CGRect(x: 2, y: 8, width: 10, height: 7))
            // Non-throwing arm stub (always on left side of texture)
            c.setFillColor(shirtColor.cgColor)
            c.fill(CGRect(x: 0, y: 9, width: 3, height: 5))
            c.setFillColor(skin.cgColor)
            c.fill(CGRect(x: 0, y: 8, width: 3, height: 3))          // hand
            // Neck
            c.setFillColor(skin.cgColor)
            c.fill(CGRect(x: 5, y: 15, width: 4, height: 2))
            // Head
            c.setFillColor(skin.cgColor)
            c.fill(CGRect(x: 3, y: 15, width: 8, height: 7))
            // Hair top + sideburns
            c.setFillColor(hair.cgColor)
            c.fill(CGRect(x: 3, y: 20, width: 8, height: 2))
            c.fill(CGRect(x: 3, y: 18, width: 2, height: 2))
            c.fill(CGRect(x: 9, y: 18, width: 2, height: 2))
            // Mean V-shaped eyebrows
            c.fill(CGRect(x: 3, y: 19, width: 3, height: 1))
            c.fill(CGRect(x: 8, y: 19, width: 3, height: 1))
            c.fill(CGRect(x: 5, y: 18, width: 1, height: 1))
            c.fill(CGRect(x: 8, y: 18, width: 1, height: 1))
            // Eyes
            c.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
            c.fill(CGRect(x: 4, y: 17, width: 2, height: 2))
            c.fill(CGRect(x: 8, y: 17, width: 2, height: 2))
            // Smirk
            c.setFillColor(UIColor(red: 0.50, green: 0.15, blue: 0.10, alpha: 1).cgColor)
            c.fill(CGRect(x: 5, y: 15, width: 5, height: 1))
            c.fill(CGRect(x: 9, y: 16, width: 1, height: 1))         // smirk lift
        }
        let bodyTex = SKTexture(image: bodyImg); bodyTex.filteringMode = .nearest
        let bodySprite = SKSpriteNode(texture: bodyTex, size: CGSize(width: kw, height: kh))
        // Flip so the non-throwing stub is always on the away-from-road side
        if !facingRight { bodySprite.xScale = -1 }
        container.addChild(bodySprite)

        // Throwing arm — anchor at top (shoulder) so rotation swings the whole arm
        let aw: CGFloat = 4, ah: CGFloat = 11
        let armImg = UIGraphicsImageRenderer(
            size: CGSize(width: aw, height: ah), format: fmt
        ).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(shirtColor.cgColor)
            c.fill(CGRect(x: 0, y: 5, width: aw, height: 6))         // sleeve
            c.setFillColor(skin.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: aw, height: 6))         // forearm + hand
            c.setFillColor(UIColor(red: 0.85, green: 0.64, blue: 0.46, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 2, height: 2))          // knuckle accent
            c.fill(CGRect(x: 2, y: 1, width: 2, height: 2))
        }
        let armTex = SKTexture(image: armImg); armTex.filteringMode = .nearest
        let armSprite = SKSpriteNode(texture: armTex, size: CGSize(width: aw, height: ah))
        armSprite.anchorPoint = CGPoint(x: 0.5, y: 1.0)  // pivot at shoulder (top)
        // Place at road-facing shoulder. Body kh=22, center at y=11 in texture.
        // Shirt shoulder at texture y≈14 → container y = 14 - 11 = 3.
        // Road-facing side: +x for facingRight, -x for !facingRight.
        armSprite.position = CGPoint(x: facingRight ? 6 : -6, y: 3)
        armSprite.zPosition = 1
        container.addChild(armSprite)

        return (container, armSprite)
    }

    private func startArmIdle(armNode: SKSpriteNode, facingRight: Bool, delay: Double) {
        let swing: CGFloat = 0.14
        let dir: CGFloat = facingRight ? 1 : -1
        armNode.run(.sequence([
            .wait(forDuration: delay),
            .repeatForever(.sequence([
                .rotate(toAngle:  dir * swing, duration: 0.45),
                .rotate(toAngle: -dir * swing, duration: 0.45)
            ]))
        ]))
    }

    private func triggerBullyThrow(fromLeft: Bool, kidIdx: Int) {
        let idx = kidIdx
        bullyKids[idx].isAnimating = true
        let arm = bullyKids[idx].armNode
        let facing = bullyKids[idx].facingRight
        let windUp: CGFloat  = (facing ? 1 : -1) *  CGFloat.pi * 0.50  // arm back
        let release: CGFloat = (facing ? -1 : 1) *  CGFloat.pi * 0.35  // arm forward

        arm.removeAllActions()
        arm.run(.sequence([
            .rotate(toAngle: windUp,  duration: 0.14),   // wind up
            .rotate(toAngle: release, duration: 0.11),   // throw
            .rotate(toAngle: 0,       duration: 0.20),   // return to neutral
            .run { [weak self] in
                guard let self else { return }
                self.bullyKids[idx].isAnimating = false
                self.startArmIdle(armNode: arm, facingRight: facing, delay: 0)
            }
        ]))
    }

    // MARK: - Pickups
    private func spawnPickup() {
        let kind: PickupData.Kind = Float.random(in: 0...1) < 0.4 ? .heart : .boost
        let lane = Int.random(in: 0..<3); let cx = laneCenter[lane]; let spY = H/2 + 40
        for c in cars where c.isActive {
            if abs(c.x - cx) < laneWidth * 0.7 && abs(c.screenY - spY) < 60 { return }
        }
        let n = makePickupNode(kind: kind)
        n.position = CGPoint(x: cx, y: spY); n.zPosition = 8
        n.run(.repeatForever(.sequence([.scale(to:1.15,duration:0.5),.scale(to:0.90,duration:0.5)])))
        addChild(n)
        pickups.append(PickupData(kind: kind, x: cx, screenY: spY, node: n))
    }

    private func updatePickupPositions(dt: CGFloat) {
        for i in pickups.indices {
            guard pickups[i].isActive else { continue }
            pickups[i].screenY -= pr.speed * dt
            pickups[i].node.position.y = pickups[i].screenY
            if pickups[i].screenY < -H/2 - 60 { pickups[i].node.removeFromParent(); pickups[i].isActive = false }
        }
        pickups.removeAll { !$0.isActive }
    }

    private func makePickupNode(kind: PickupData.Kind) -> SKNode {
        let sz: CGFloat = 18
        let col: SKColor = kind == .heart
            ? SKColor(red:0.92,green:0.15,blue:0.15,alpha:1)
            : SKColor(red:1.00,green:0.52,blue:0.05,alpha:1)   // orange
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sz, height: sz), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(col.cgColor)
            if kind == .heart {
                let px = sz / 8
                let pts: [(Int,Int)] = [(1,0),(2,0),(5,0),(6,0),
                                        (0,1),(1,1),(2,1),(3,1),(4,1),(5,1),(6,1),(7,1),
                                        (0,2),(1,2),(2,2),(3,2),(4,2),(5,2),(6,2),(7,2),
                                        (1,3),(2,3),(3,3),(4,3),(5,3),(6,3),
                                        (2,4),(3,4),(4,4),(5,4),(3,5),(4,5),(3,6),(4,6)]
                for (px_, py_) in pts {
                    c.fill(CGRect(x:CGFloat(px_)*px,y:CGFloat(py_)*px,width:px,height:px))
                }
            } else {
                // Orange body
                c.move(to: CGPoint(x:sz/2,       y:2))
                c.addLine(to: CGPoint(x:sz-2,    y:sz*0.55))
                c.addLine(to: CGPoint(x:sz*0.62, y:sz*0.55))
                c.addLine(to: CGPoint(x:sz*0.62, y:sz-2))
                c.addLine(to: CGPoint(x:sz*0.38, y:sz-2))
                c.addLine(to: CGPoint(x:sz*0.38, y:sz*0.55))
                c.addLine(to: CGPoint(x:2,       y:sz*0.55))
                c.closePath(); c.fillPath()
                // Yellow highlight: left half of arrowhead
                c.setFillColor(UIColor(red:1.0,green:0.92,blue:0.10,alpha:1).cgColor)
                c.move(to: CGPoint(x:sz/2,       y:2))
                c.addLine(to: CGPoint(x:2,       y:sz*0.55))
                c.addLine(to: CGPoint(x:sz*0.38, y:sz*0.55))
                c.addLine(to: CGPoint(x:sz*0.38, y:sz*0.35))
                c.closePath(); c.fillPath()
            }
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return SKSpriteNode(texture: tex, size: CGSize(width: sz, height: sz))
    }

    // MARK: - Collision detection
    private func checkCollisions() {
        checkVsCars()
        checkVsBags()
        checkVsPickups()
    }

    private func bikeRect(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x-10, y: y-16, width: 20, height: 32)
    }

    private func checkVsCars() {
        for c in cars where c.isActive {
            let cr = CGRect(x: c.x - 14, y: c.screenY - 22, width: 28, height: 44)
            if !pr.isCrashing && !pr.isInvincible && !pr.isJumping && bikeRect(x:pr.x,y:playerScreenY).intersects(cr) {
                triggerCarCrash(player: true); return
            }
            let pkY = screenYFor(pk)
            if !pk.isCrashing && !pk.isInvincible && abs(pkY) < H && bikeRect(x:pk.x,y:pkY).intersects(cr) {
                triggerCarCrash(player: false, isGreen: false)
            }
            let grY = screenYFor(gr)
            if !gr.isCrashing && !gr.isInvincible && abs(grY) < H && bikeRect(x:gr.x,y:grY).intersects(cr) {
                triggerCarCrash(player: false, isGreen: true)
            }
        }
    }

    private func checkVsBags() {
        let sz: CGFloat = 14
        for i in bags.indices {
            guard bags[i].isActive else { continue }
            let br = CGRect(x:bags[i].x-sz/2, y:bags[i].y-sz/2, width:sz, height:sz)
            if !pr.isInvincible && !pr.isJumping && bikeRect(x:pr.x,y:playerScreenY).intersects(br) {
                bags[i].node.removeFromParent(); bags[i].isActive = false
                damageBag(player: true); continue
            }
            let pkY = screenYFor(pk)
            if !pk.isInvincible && abs(pkY)<H && bikeRect(x:pk.x,y:pkY).intersects(br) {
                bags[i].node.removeFromParent(); bags[i].isActive = false
                damageBag(player: false, isGreen: false); continue
            }
            let grY = screenYFor(gr)
            if !gr.isInvincible && abs(grY)<H && bikeRect(x:gr.x,y:grY).intersects(br) {
                bags[i].node.removeFromParent(); bags[i].isActive = false
                damageBag(player: false, isGreen: true); continue
            }
        }
    }

    private func checkVsPickups() {
        let sz: CGFloat = 22
        for i in pickups.indices {
            guard pickups[i].isActive else { continue }
            let pr_ = CGRect(x:pickups[i].x-sz/2, y:pickups[i].screenY-sz/2, width:sz, height:sz)
            if bikeRect(x:pr.x,y:playerScreenY).intersects(pr_) {
                collectPickup(idx: i, player: true); continue
            }
            let pkY = screenYFor(pk)
            if abs(pkY)<H && bikeRect(x:pk.x,y:pkY).intersects(pr_) {
                collectPickup(idx: i, player: false); continue
            }
            let grY = screenYFor(gr)
            if abs(grY)<H && bikeRect(x:gr.x,y:grY).intersects(pr_) {
                collectPickup(idx: i, player: false); continue
            }
        }
    }

    // MARK: - Damage
    private func triggerCarCrash(player: Bool, isGreen: Bool = false) {
        if player {
            guard !pr.isCrashing && !pr.isInvincible else { return }
            triggerCrashHaptics()
            playCrashAnimation(on: playerSprite, isPlayer: true)
            pr.isCrashing = true; pr.crashTimer = 2.0; pr.speed = baseSpeed
            timeSinceLastCrash = 0
            pr.hearts = max(0, pr.hearts - 1)
            HeartsManager.shared.lose()
            pr.isInvincible = true; pr.invTimer = 1.5
            if pr.hearts <= 0 { showGameOver() }
        } else if isGreen {
            guard !gr.isCrashing && !gr.isInvincible else { return }
            playCrashAnimation(on: greenSprite)
            gr.isCrashing = true; gr.crashTimer = 2.0; gr.speed = baseSpeed
            gr.isInvincible = true; gr.invTimer = 2.0
        } else {
            guard !pk.isCrashing && !pk.isInvincible else { return }
            playCrashAnimation(on: pinkSprite)
            pk.isCrashing = true; pk.crashTimer = 2.0; pk.speed = baseSpeed
            pk.isInvincible = true; pk.invTimer = 2.0
        }
    }

    private func playCrashAnimation(on sprite: SKSpriteNode, isPlayer: Bool = false) {
        sprite.removeAction(forKey: "crash")

        if isPlayer {
            shakeScreen()
            spawnCrashExplosion(at: sprite.position)
        }

        sprite.run(.sequence([
            // Phase 1 — impact: white flash + scale spike
            .group([
                .colorize(with: .white, colorBlendFactor: 1.0, duration: 0.06),
                .scale(to: 2.0, duration: 0.10),
            ]),
            // Phase 2 — tumble: wild spin, shrink, orange fire glow
            .group([
                .sequence([
                    .colorize(withColorBlendFactor: 0.0, duration: 0.12),
                    .colorize(with: SKColor(red:1, green:0.4, blue:0, alpha:1),
                              colorBlendFactor: 0.75, duration: 0.08),
                    .colorize(withColorBlendFactor: 0.0, duration: 0.20),
                ]),
                .sequence([
                    .scale(to: 1.65, duration: 0.15),
                    .scale(to: 0.85, duration: 0.20),
                    .scale(to: 1.15, duration: 0.15),
                ]),
                .rotate(byAngle: .pi * 3.5, duration: 0.65),
            ]),
            // Phase 3 — settle: right the bike
            .group([
                .scale(to: 1.0, duration: 0.22),
                .rotate(toAngle: 0, duration: 0.22),
            ]),
        ]), withKey: "crash")
    }

    private func shakeScreen() {
        guard let view = self.view else { return }
        let animX = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animX.values = [-10, 10, -9, 9, -6, 6, -4, 4, -2, 2, 0]
        animX.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let animY = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animY.values = [-5, 5, -4, 4, -3, 3, -2, 2, -1, 1, 0]
        animY.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let group = CAAnimationGroup()
        group.animations = [animX, animY]
        group.duration = 0.45
        view.layer.add(group, forKey: "crashShake")
    }

    private func spawnCrashExplosion(at pos: CGPoint) {
        let sparkColors: [SKColor] = [
            SKColor(red:1.0, green:0.90, blue:0.20, alpha:1),
            SKColor(red:1.0, green:0.40, blue:0.10, alpha:1),
            SKColor(red:1.0, green:1.00, blue:1.00, alpha:1),
            SKColor(red:0.9, green:0.70, blue:0.10, alpha:1),
        ]
        // Radial spark burst
        for i in 0..<16 {
            let angle = CGFloat(i) * (.pi * 2 / 16) + CGFloat.random(in: -0.15...0.15)
            let speed = CGFloat.random(in: 80...180)
            let sz    = CGFloat.random(in: 3...8)
            let sp    = SKSpriteNode(color: sparkColors.randomElement()!,
                                     size: CGSize(width: sz, height: sz))
            sp.position = pos; sp.zPosition = 30; addChild(sp)
            sp.run(.sequence([
                .group([
                    .moveBy(x: cos(angle)*speed, y: sin(angle)*speed, duration: 0.50),
                    .sequence([.wait(forDuration: 0.08), .fadeOut(withDuration: 0.42)]),
                ]),
                .removeFromParent()
            ]))
        }
        // Smoke puffs
        for _ in 0..<6 {
            let r     = CGFloat.random(in: 8...18)
            let smoke = SKShapeNode(circleOfRadius: r)
            smoke.fillColor   = SKColor(white: CGFloat.random(in: 0.4...0.65), alpha: 0.55)
            smoke.strokeColor = .clear
            smoke.position    = CGPoint(x: pos.x + CGFloat.random(in: -14...14),
                                        y: pos.y + CGFloat.random(in: -14...14))
            smoke.zPosition   = 26; addChild(smoke)
            smoke.run(.sequence([
                .group([.scale(to: 3.0, duration: 0.55), .fadeOut(withDuration: 0.55)]),
                .removeFromParent()
            ]))
        }
    }

    private func damageBag(player: Bool, isGreen: Bool = false) {
        let sp = player ? playerSprite! : (isGreen ? greenSprite! : pinkSprite!)
        sp.run(.sequence([.colorize(with:.white,colorBlendFactor:1.0,duration:0.05),
                          .colorize(withColorBlendFactor:0.0,duration:0.15)]))
        if player {
            guard !pr.isInvincible else { return }
            triggerBagHitHaptics()
            pr.hearts = max(0, pr.hearts - 1)
            HeartsManager.shared.lose()
            pr.isInvincible = true; pr.invTimer = 1.5
            if pr.hearts <= 0 { showGameOver() }
        } else if isGreen {
            guard !gr.isInvincible else { return }
            gr.isInvincible = true; gr.invTimer = 1.5
        } else {
            guard !pk.isInvincible else { return }
            pk.isInvincible = true; pk.invTimer = 1.5
        }
    }

    private func collectPickup(idx: Int, player: Bool) {
        let pu = pickups[idx]
        pu.node.run(.sequence([.scale(to:1.5,duration:0.1),.fadeOut(withDuration:0.1),.removeFromParent()]))
        pickups[idx].isActive = false
        if player {
            switch pu.kind {
            case .heart:
                pr.hearts = min(pr.maxHearts, pr.hearts + 1)
                HeartsManager.shared.gain()
                triggerHeartPickupHaptic()
            case .boost:
                triggerBoostHaptics()
                pr.isBoosting = true; pr.boostTimer = 3.5
                // Instant speed floor — player feels the kick immediately.
                pr.speed = max(pr.speed, maxSpeed * 1.6)
                attachBoost(to: playerSprite, store: &playerBoostNode)
                flashBoostScreen()
                playerSprite.run(.sequence([
                    .group([.colorize(with: .yellow, colorBlendFactor: 0.85, duration: 0.07),
                            .scale(to: 1.25, duration: 0.07)]),
                    .group([.colorize(with: .yellow, colorBlendFactor: 0.0, duration: 0.18),
                            .scale(to: 1.0,  duration: 0.18)]),
                ]))
            }
        } else {
            if pu.kind == .boost {
                if Bool.random() {
                    gr.isBoosting = true; gr.boostTimer = 3.5
                    gr.speed = max(gr.speed, maxSpeed * 1.4)
                    attachBoost(to: greenSprite, store: &greenBoostNode)
                } else {
                    pk.isBoosting = true; pk.boostTimer = 3.5
                    pk.speed = max(pk.speed, maxSpeed * 1.4)
                    attachBoost(to: pinkSprite, store: &pinkBoostNode)
                }
            }
        }
    }

    private func attachBoost(to sprite: SKSpriteNode, store: inout SKNode?) {
        store?.removeFromParent()

        let container = SKNode()
        container.position = CGPoint(x: sprite.position.x,
                                     y: sprite.position.y - sprite.size.height / 2 - 4)
        container.zPosition = 9
        addChild(container); store = container

        // Three flame tongues: left / center / right
        let tongues: [(dx: CGFloat, w: CGFloat, h: CGFloat, color: SKColor, t1: Double, t2: Double)] = [
            (-4, 6, 14, SKColor(red:1.0, green:0.35, blue:0.0, alpha:0.85), 0.09, 0.12),
            ( 0, 8, 22, SKColor(red:1.0, green:0.80, blue:0.1, alpha:1.00), 0.06, 0.09),
            ( 4, 6, 14, SKColor(red:1.0, green:0.35, blue:0.0, alpha:0.85), 0.08, 0.11),
        ]
        for t in tongues {
            let f = SKSpriteNode(color: t.color, size: CGSize(width: t.w, height: t.h))
            f.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            f.position = CGPoint(x: t.dx, y: 0)
            f.run(.repeatForever(.sequence([
                .group([.scale(to: 1.35, duration: t.t1),
                        .fadeAlpha(to: 0.65, duration: t.t1)]),
                .group([.scale(to: 0.70, duration: t.t2),
                        .fadeAlpha(to: 1.00, duration: t.t2)]),
            ])))
            container.addChild(f)
        }

        // Ember sparks
        for _ in 0..<5 {
            let ember = SKSpriteNode(color: SKColor(red:1.0, green:0.85, blue:0.2, alpha:1),
                                     size: CGSize(width: 2, height: 2))
            let ox = CGFloat.random(in: -5...5)
            ember.position = CGPoint(x: ox, y: 0)
            let angle = CGFloat.random(in: -.pi * 0.85 ... -.pi * 0.15)
            let dist  = CGFloat.random(in: 14...26)
            let dur   = Double.random(in: 0.30...0.50)
            ember.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: dur),
                    .sequence([.fadeAlpha(to: 0.9, duration: dur * 0.4),
                               .fadeAlpha(to: 0.0, duration: dur * 0.6)]),
                    .scale(to: 0.2, duration: dur),
                ]),
                .run { ember.position = CGPoint(x: ox, y: 0); ember.alpha = 1; ember.setScale(1) },
            ])))
            container.addChild(ember)
        }
    }

    private func flashBoostScreen() {
        let flash = SKSpriteNode(color: SKColor(red:1.0, green:0.65, blue:0.0, alpha:0.40),
                                 size: CGSize(width: W, height: H))
        flash.position  = .zero
        flash.zPosition = 200
        addChild(flash)
        flash.run(.sequence([.fadeAlpha(to: 0, duration: 0.30), .removeFromParent()]))

        // Speed-streak lines
        for _ in 0..<10 {
            let line = SKShapeNode()
            let path = CGMutablePath()
            let sx = CGFloat.random(in: -W/2...W/2)
            let sy = CGFloat.random(in: -H/2...H/2)
            let len = CGFloat.random(in: 35...90)
            path.move(to: CGPoint(x: sx, y: sy))
            path.addLine(to: CGPoint(x: sx, y: sy - len))
            line.path = path
            line.strokeColor = SKColor(white: 1, alpha: CGFloat.random(in: 0.4...0.7))
            line.lineWidth  = 1
            line.zPosition  = 199
            addChild(line)
            line.run(.sequence([.fadeAlpha(to: 0, duration: 0.25), .removeFromParent()]))
        }
    }

    // MARK: - Timer helpers
    private func updateInvincibility(dt: CGFloat) {
        func tick(racer: inout RacerData, sprite: SKSpriteNode) {
            guard racer.isInvincible else { return }
            racer.invTimer -= dt
            sprite.alpha = fmod(racer.invTimer * 8, 2) < 1 ? 0.35 : 1.0
            if racer.invTimer <= 0 { racer.isInvincible = false; sprite.alpha = 1.0 }
        }
        tick(racer: &pr, sprite: playerSprite)
        tick(racer: &pk, sprite: pinkSprite)
        tick(racer: &gr, sprite: greenSprite)
    }

    private func updateCrashTimers(dt: CGFloat) {
        func tick(racer: inout RacerData) {
            guard racer.isCrashing else { return }
            racer.crashTimer -= dt
            if racer.crashTimer <= 0 { racer.isCrashing = false }
        }
        tick(racer: &pr); tick(racer: &pk); tick(racer: &gr)
    }

    private func updateBoostTimers(dt: CGFloat) {
        func tick(racer: inout RacerData, boostNode: inout SKNode?) {
            guard racer.isBoosting else { return }
            racer.boostTimer -= dt
            if racer.boostTimer <= 0 {
                racer.isBoosting = false
                boostNode?.removeFromParent(); boostNode = nil
            }
        }
        tick(racer: &pr, boostNode: &playerBoostNode)
        tick(racer: &pk, boostNode: &pinkBoostNode)
        tick(racer: &gr, boostNode: &greenBoostNode)
    }

    // MARK: - Jump Truck
    private func spawnJumpTruck() {
        let lane   = Int.random(in: 0..<3)
        let cx     = laneCenter[lane]
        let spY    = H / 2 + 80
        let speed  = CGFloat.random(in: 35...55)   // slow — player will catch up
        let n = makeJumpTruckNode()
        n.position  = CGPoint(x: cx, y: spY)
        n.zPosition = 9
        addChild(n)
        jumpTrucks.append(JumpTruckData(x: cx, screenY: spY, forwardSpeed: speed, node: n))
        jumpTrucksSpawned += 1
    }

    private func makeJumpTruckNode() -> SKNode {
        let tw: CGFloat = 44, th: CGFloat = 76
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: tw, height: th), format: fmt).image { ctx in
            let c = ctx.cgContext

            // Cab (top/front of truck — orange-yellow)
            c.setFillColor(UIColor(red: 0.95, green: 0.55, blue: 0.05, alpha: 1).cgColor)
            c.fill(CGRect(x: 4, y: 2, width: tw - 8, height: 32))

            // Windshield
            c.setFillColor(UIColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 0.85).cgColor)
            c.fill(CGRect(x: 8, y: 6, width: tw - 16, height: 14))

            // Headlights (front)
            c.setFillColor(UIColor(red: 1.0, green: 0.98, blue: 0.7, alpha: 1).cgColor)
            c.fill(CGRect(x: 5, y: th - 7, width: 7, height: 4))
            c.fill(CGRect(x: tw - 12, y: th - 7, width: 7, height: 4))

            // Truck tires (4 corners)
            c.setFillColor(UIColor(white: 0.13, alpha: 1).cgColor)
            for r in [CGRect(x: 0, y: 3, width: 7, height: 12),
                      CGRect(x: tw - 7, y: 3, width: 7, height: 12),
                      CGRect(x: 0, y: th - 15, width: 7, height: 12),
                      CGRect(x: tw - 7, y: th - 15, width: 7, height: 12)] {
                c.fill(r)
            }

            // Flatbed / ramp body (bottom portion — darker)
            c.setFillColor(UIColor(red: 0.55, green: 0.35, blue: 0.08, alpha: 1).cgColor)
            c.fill(CGRect(x: 4, y: 36, width: tw - 8, height: 28))

            // Ramp face at the very back (bottom) — bright yellow wedge shape
            c.setFillColor(UIColor(red: 1.0, green: 0.88, blue: 0.05, alpha: 1).cgColor)
            c.move(to: CGPoint(x: 4,      y: 36))
            c.addLine(to: CGPoint(x: tw - 4, y: 36))
            c.addLine(to: CGPoint(x: tw - 4, y: 62))
            c.addLine(to: CGPoint(x: 4,      y: 72))
            c.closePath(); c.fillPath()

            // Ramp stripe
            c.setFillColor(UIColor(white: 0.2, alpha: 0.6).cgColor)
            c.fill(CGRect(x: 4, y: 50, width: tw - 8, height: 3))
            c.fill(CGRect(x: 4, y: 58, width: tw - 8, height: 3))

            // "JUMP" label area — black bar
            c.setFillColor(UIColor.black.cgColor)
            c.fill(CGRect(x: 8, y: 20, width: tw - 16, height: 10))
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: tex, size: CGSize(width: tw, height: th))

        // Pulsing gold glow ring to make it obvious
        let glow = SKShapeNode(rectOf: CGSize(width: tw + 10, height: th + 10), cornerRadius: 4)
        glow.fillColor   = .clear
        glow.strokeColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.85)
        glow.lineWidth   = 3
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.4),
            .fadeAlpha(to: 1.00, duration: 0.4),
        ])))
        sprite.addChild(glow)

        // "JUMP TRUCK" label
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text      = "JUMP"
        lbl.fontSize  = 6
        lbl.fontColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
        lbl.position  = CGPoint(x: 0, y: -6)
        sprite.addChild(lbl)

        return sprite
    }

    private func makeAirGoldBagNode() -> SKNode {
        let container = SKNode()
        let body = SKShapeNode(rectOf: CGSize(width: 14, height: 14), cornerRadius: 3)
        body.fillColor   = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1)
        body.strokeColor = SKColor(red: 0.7, green: 0.50, blue: 0.0, alpha: 1)
        body.lineWidth   = 1.5
        container.addChild(body)
        let glow = SKShapeNode(rectOf: CGSize(width: 22, height: 22), cornerRadius: 5)
        glow.fillColor   = .clear
        glow.strokeColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.85)
        glow.lineWidth   = 2
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.25),
            .fadeAlpha(to: 1.0, duration: 0.25),
        ])))
        container.addChild(glow)
        return container
    }

    private func updateJumpTrucks(dt: CGFloat) {
        for i in jumpTrucks.indices {
            guard jumpTrucks[i].isActive else { continue }
            // Scroll down relative to player speed
            jumpTrucks[i].screenY -= max(0, pr.speed - jumpTrucks[i].forwardSpeed) * dt
            jumpTrucks[i].node.position.y = jumpTrucks[i].screenY

            // Remove when scrolled off-screen
            if jumpTrucks[i].screenY < -H / 2 - 100 {
                jumpTrucks[i].node.removeFromParent()
                jumpTrucks[i].isActive = false
                continue
            }

            // Check if player is in position to use the ramp
            guard !jumpTrucks[i].hasLaunched && !pr.isCrashing && !pr.isJumping else { continue }
            let aheadDist = jumpTrucks[i].screenY - playerScreenY
            let lateralOk = abs(jumpTrucks[i].x - pr.x) < laneWidth * 0.55
            if aheadDist > 0 && aheadDist < 70 && lateralOk {
                jumpTrucks[i].hasLaunched = true
                triggerPlayerJump(truckX: jumpTrucks[i].x)
            }
        }
        jumpTrucks.removeAll { !$0.isActive }
    }

    private func triggerPlayerJump(truckX: CGFloat) {
        // Snap player into the truck's lane
        pr.x = truckX
        pr.xVelocity = 0

        pr.isJumping  = true
        pr.jumpTimer  = 0
        // Immediate speed kick
        pr.speed = max(pr.speed, maxSpeed * 1.6)

        // Scale-up-and-down arc: bigger = closer to camera = going up, then back down
        playerSprite.removeAction(forKey: "jump")
        playerSprite.zPosition = 15   // above traffic during jump
        playerSprite.run(.sequence([
            // Rising — scale up quickly
            .scale(to: 2.4, duration: 0.45),
            // At peak — brief hold with slight wobble
            .group([
                .scale(to: 2.2, duration: 0.20),
                .rotate(byAngle: .pi * 0.08, duration: 0.20),
            ]),
            .group([
                .scale(to: 2.4, duration: 0.15),
                .rotate(byAngle: -.pi * 0.08, duration: 0.15),
            ]),
            // Descent — scale back down to land
            .group([
                .scale(to: 1.0, duration: 0.60),
                .rotate(toAngle: 0, duration: 0.60),
            ]),
            // Land — brief squish then settle
            .scale(to: 0.85, duration: 0.08),
            .scale(to: 1.00, duration: 0.12),
            .run { [weak self] in
                self?.playerSprite.zPosition = 10
                self?.pr.isJumping  = false
                self?.pr.jumpTimer  = 0
                self?.pr.isInvincible = true
                self?.pr.invTimer = 2.5
                self?.landingShake()
                self?.knockCarsOnLanding()
            }
        ]), withKey: "jump")

        // Gold flash on jump launch
        let flash = SKSpriteNode(color: SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.45),
                                 size: CGSize(width: W, height: H))
        flash.position = .zero; flash.zPosition = 200; addChild(flash)
        flash.run(.sequence([.fadeAlpha(to: 0, duration: 0.30), .removeFromParent()]))

        // "JUMP!" popup label
        let jlbl = label("JUMP!", font: "PressStart2P-Regular",
                          size: min(26, W / 13),
                          color: SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1),
                          at: CGPoint(x: 0, y: playerScreenY + 60))
        jlbl.zPosition = 110; addChild(jlbl)
        jlbl.run(.sequence([
            .group([
                .moveBy(x: 0, y: 30, duration: 0.6),
                .sequence([.scale(to: 1.2, duration: 0.15), .scale(to: 1.0, duration: 0.25)]),
            ]),
            .wait(forDuration: 0.3),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))

        // Gold bag floating in the air — auto-caught at jump peak
        let airBag = makeAirGoldBagNode()
        let bagStartX = pr.x + CGFloat.random(in: -12...12)
        airBag.position = CGPoint(x: bagStartX, y: playerScreenY + 155)
        airBag.zPosition = 155
        airBag.alpha = 0
        airBag.setScale(1.4)
        addChild(airBag)
        airBag.run(.sequence([
            .wait(forDuration: 0.20),
            .group([
                .fadeIn(withDuration: 0.15),
                .scale(to: 1.0, duration: 0.15),
            ]),
            .wait(forDuration: 0.22),
            .group([
                .move(to: CGPoint(x: pr.x, y: playerScreenY + 12), duration: 0.22),
                .sequence([
                    .wait(forDuration: 0.08),
                    .group([
                        .scale(to: 0, duration: 0.14),
                        .fadeOut(withDuration: 0.14),
                    ]),
                ]),
            ]),
            .run { [weak self] in
                guard let self else { return }
                self.jumpBagsEarned += 1
                HeartsManager.shared.refill()
                self.pr.hearts = HeartsManager.shared.currentHearts
                self.refreshHUD()
                self.showJumpBagPickup()
            },
            .removeFromParent(),
        ]))

        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.prepare(); haptic.impactOccurred(intensity: 1.0)
    }

    private func landingShake() {
        guard let view = self.view else { return }
        let animY = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animY.values = [-6, 6, -4, 4, -2, 2, 0]
        animY.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animY.duration = 0.25
        view.layer.add(animY, forKey: "landingShake")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
    }

    private func knockCarsOnLanding() {
        // Tight zone centered on the bike's landing spot so we only knock cars
        // the player visibly comes down on, not anything half a screen ahead.
        let zoneH: CGFloat = 56
        let zoneW: CGFloat = 44
        let knockZone = CGRect(x: pr.x - zoneW / 2,
                               y: playerScreenY - zoneH / 2,
                               width: zoneW, height: zoneH)
        for i in cars.indices {
            guard cars[i].isActive else { continue }
            let carCenter = CGPoint(x: cars[i].x, y: cars[i].screenY)
            guard knockZone.contains(carCenter) else { continue }
            // Fling the car sideways off the road with a spin + fade
            let knockDir: CGFloat = cars[i].x >= pr.x ? 1 : -1
            let exitX = cars[i].x + knockDir * (W * 0.6)
            cars[i].node.run(.sequence([
                .group([
                    .move(to: CGPoint(x: exitX, y: cars[i].screenY - H * 0.15), duration: 0.55),
                    .rotate(byAngle: knockDir * .pi * 3, duration: 0.55),
                    .sequence([
                        .scale(to: 1.2, duration: 0.10),
                        .fadeOut(withDuration: 0.45),
                    ])
                ]),
                .removeFromParent()
            ]))
            cars[i].isActive = false
        }
    }

    private func showJumpBagPickup() {
        let lbl = label("+1 GOLD BAG", font: "PressStart2P-Regular",
                        size: min(10, W / 34),
                        color: SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1),
                        at: CGPoint(x: pr.x, y: playerScreenY + 90))
        lbl.zPosition = 160
        addChild(lbl)
        lbl.run(.sequence([
            .group([
                .moveBy(x: 0, y: 28, duration: 0.65),
                .sequence([.scale(to: 1.15, duration: 0.15), .scale(to: 1.0, duration: 0.20)]),
            ]),
            .wait(forDuration: 0.20),
            .fadeOut(withDuration: 0.30),
            .removeFromParent(),
        ]))
    }

    // MARK: - Finish line
    private func spawnFinishLine() {
        finishLineSpawned = true
        // Place the finish line H*1.2 pts above the player — matches the trigger
        // distance so the line scrolls into the player exactly when the race ends.
        let startY = playerScreenY + H * 1.2

        let container = SKNode()
        container.position = CGPoint(x: 0, y: startY)
        container.zPosition = 11
        addChild(container)

        // Checkered strip — two rows of alternating black / white squares.
        let sq: CGFloat = 12
        let cols = Int(roadWidth / sq) + 1
        for row in 0..<2 {
            for col in 0..<cols {
                let isWhite = (col + row) % 2 == 0
                let cell = SKSpriteNode(color: isWhite ? .white : .black,
                                        size: CGSize(width: sq, height: sq))
                cell.position = CGPoint(x: roadLeft + CGFloat(col) * sq + sq / 2,
                                        y: CGFloat(row) * sq + sq / 2)
                container.addChild(cell)
            }
        }

        // Poles on each road edge.
        for xPos in [roadLeft, roadRight] {
            let pole = SKSpriteNode(color: SKColor(white: 0.88, alpha: 1),
                                    size: CGSize(width: 5, height: 56))
            pole.anchorPoint = CGPoint(x: 0.5, y: 0)
            pole.position    = CGPoint(x: xPos, y: sq * 2)
            container.addChild(pole)
        }

        // "FINISH" label above the banner.
        let lbl = label("FINISH", font: "PressStart2P-Regular",
                         size: min(16, W / 22), color: .yellow,
                         at: CGPoint(x: 0, y: sq * 2 + 64))
        lbl.run(.repeatForever(.sequence([
            .scale(to: 1.10, duration: 0.35),
            .scale(to: 0.92, duration: 0.35),
        ])))
        container.addChild(lbl)

        finishLineNode = container
    }

    private func updateFinishLine(dt: CGFloat) {
        guard let node = finishLineNode else { return }
        node.position.y -= pr.speed * dt
        if node.position.y < -H / 2 - 100 {
            node.removeFromParent(); finishLineNode = nil
        }
    }

    // MARK: - Race end
    private func checkRaceEnd() {
        func markFinish(racer: inout RacerData) {
            guard !racer.finished && racer.distanceRemaining <= 0 else { return }
            racer.finished = true; finishCount += 1; racer.finishRank = finishCount
        }
        markFinish(racer: &pr); markFinish(racer: &pk); markFinish(racer: &gr)

        if pr.finished && pr.finishRank == 1 { showVictory(); return }
        if (pk.finished && pk.finishRank == 1) || (gr.finished && gr.finishRank == 1) {
            showGameOver(aiWon: true)
        }
    }

    // MARK: - End screens
    private func showGameOver(aiWon: Bool = false) {
        guard gState == .racing else { return }
        gState = .gameOver
        let sub = aiWon ? "AN AI FINISHED FIRST" : "YOU CRASHED OUT"
        let ov = buildEndOverlay(won: false, title: "RACE OVER", subtitle: sub, rewards: [])
        onComplete?(false); addChild(ov); overlayNode = ov
    }

    private func showVictory() {
        guard gState == .racing else { return }
        gState = .victory
        let bagCount = jumpBagsEarned
        let m = Int(elapsed)/60, s = Int(elapsed)%60
        let timeStr = String(format: "TIME  %d:%02d", m, s)

        var rewards: [GameResultModal.Reward] = []
        if awardsRewards {
            // First-ever win unlocks the backyard world map.
            ProgressManager.shared.worldUnlocked = true
            rewards.append(.unlock("WORLD MAP UNLOCKED!"))
            if bagCount > 0 {
                InventoryManager().collect(.goldenBag, count: bagCount)
                rewards.append(GameResultModal.Reward(item: .goldenBag, count: bagCount))
            }
        }
        let ov = buildEndOverlay(won: true, title: "1ST PLACE!", subtitle: timeStr, rewards: rewards)
        onComplete?(true); addChild(ov); overlayNode = ov
    }

    private func buildEndOverlay(won: Bool, title: String, subtitle: String,
                                 rewards: [GameResultModal.Reward]) -> SKNode {
        let ov = buildOverlayContainer()
        let bg = SKShapeNode(rect: CGRect(x:-W/2,y:-H/2,width:W,height:H))
        bg.fillColor = SKColor(white:0,alpha:0.75); bg.strokeColor = .clear; ov.addChild(bg)

        let panel = GameResultModal.make(
            sceneSize: CGSize(width: W, height: H),
            won: won,
            title: won ? "VICTORY!" : "RACE OVER",
            subtitle: subtitle,
            rewards: rewards,
            buttons: [GameResultModal.Button(label: "PLAY AGAIN", name: "replayBtn", style: .primary),
                      GameResultModal.Button(label: "MAIN MENU", name: "menuBtn", style: .neutral)])
        ov.addChild(panel)
        return ov
    }

    private func buildOverlayContainer() -> SKNode {
        let n = SKNode(); n.zPosition = 100; return n
    }

    // MARK: - Reset
    private func resetGame() {
        cars.forEach       { $0.node.removeFromParent() }
        bags.forEach       { $0.node.removeFromParent() }
        pickups.forEach    { $0.node.removeFromParent() }
        jumpTrucks.forEach { $0.node.removeFromParent() }
        cars.removeAll(); bags.removeAll(); pickups.removeAll(); jumpTrucks.removeAll()
        jumpTruckTimer = 0; jumpTruckInterval = 20.0; jumpTrucksSpawned = 0; jumpBagsEarned = 0
        playerBoostNode?.removeFromParent(); playerBoostNode = nil
        pinkBoostNode?.removeFromParent();   pinkBoostNode   = nil
        greenBoostNode?.removeFromParent();  greenBoostNode  = nil
        overlayNode?.removeFromParent();     overlayNode     = nil
        pauseOverlayNode?.removeFromParent(); pauseOverlayNode = nil
        finishLineNode?.removeFromParent();  finishLineNode  = nil
        finishLineSpawned = false
        isPausedGame = false

        pr = RacerData(kind: .player); pk = RacerData(kind: .pink); gr = RacerData(kind: .green)
        pr.x = laneCenter[1]; pr.speed = baseSpeed
        if HeartsManager.shared.currentHearts <= 0 { HeartsManager.shared.refill() }
        pr.hearts    = HeartsManager.shared.currentHearts
        pr.maxHearts = HeartsManager.shared.maxHearts
        pk.x = laneCenter[0]; pk.speed = baseSpeed; pk.targetLaneX = laneCenter[0]
        gr.x = laneCenter[2]; gr.speed = baseSpeed; gr.targetLaneX = laneCenter[2]

        for sp in [playerSprite, pinkSprite, greenSprite] {
            sp?.setScale(1); sp?.zRotation = 0; sp?.alpha = 1
            sp?.removeAction(forKey: "crash"); sp?.removeAction(forKey: "jump")
        }
        pr.isJumping = false; pr.jumpTimer = 0
        elapsed = 0; finishCount = 0; timeSinceLastCrash = 0
        carTimer = 1.5; pkTimer = 4.0; bagTimer = 2.0
        steerLeft = false; steerRight = false
        leftTouches.removeAll(); rightTouches.removeAll()
        lastTime = 0
        startCountdown()
    }

    // MARK: - Helpers
    private func screenYFor(_ r: RacerData) -> CGFloat {
        if r.kind == .player { return playerScreenY }
        return playerScreenY + (pr.distanceRemaining - r.distanceRemaining) * distToPixScale
    }

    private func spawnSparks(at pos: CGPoint) {
        for _ in 0..<5 {
            let sp = SKSpriteNode(color: SKColor(red:1,green:0.90,blue:0.20,alpha:1), size:CGSize(width:4,height:4))
            sp.position = pos; sp.zPosition = 25; addChild(sp)
            sp.run(.sequence([.group([
                .moveBy(x:CGFloat.random(in:-70...70), y:CGFloat.random(in:-50...50), duration:0.28),
                .fadeOut(withDuration:0.28)]), .removeFromParent()]))
        }
    }

    private func label(_ text: String, font: String, size: CGFloat, color: SKColor, at pos: CGPoint) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font)
        l.text = text; l.fontSize = size; l.fontColor = color
        l.horizontalAlignmentMode = .center; l.verticalAlignmentMode = .center
        l.position = pos; return l
    }

    // MARK: - Haptic Feedback

    private func triggerCrashHaptics() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        let notification = UINotificationFeedbackGenerator()
        impact.prepare()
        notification.prepare()
        impact.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { impact.impactOccurred(intensity: 1.0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            impact.impactOccurred(intensity: 0.9)
            notification.notificationOccurred(.error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { impact.impactOccurred(intensity: 0.8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { impact.impactOccurred(intensity: 0.6) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { impact.impactOccurred(intensity: 0.4) }
        // Subtle "getting back up" pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
            let light = UIImpactFeedbackGenerator(style: .light)
            light.impactOccurred(intensity: 0.8)
        }
    }

    private func triggerHeartPickupHaptic() {
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()
        light.impactOccurred(intensity: 0.6)
    }

    private func triggerBagHitHaptics() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
    }

    private func triggerBoostHaptics() {
        let heavy  = UIImpactFeedbackGenerator(style: .heavy)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let notif  = UINotificationFeedbackGenerator()
        heavy.prepare(); medium.prepare(); notif.prepare()
        notif.notificationOccurred(.success)
        heavy.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { medium.impactOccurred(intensity: 0.8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { heavy.impactOccurred(intensity: 1.0) }
    }

    // MARK: - CRT Overlay
    private func addCrtOverlay() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: W, height: H))
            c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            var y: CGFloat = 0
            while y < H { c.fill(CGRect(x: 0, y: y, width: W, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.18).cgColor,
                           UIColor(white: 0, alpha: 0.70).cgColor] as CFArray
            let vGrad = CGGradient(colorsSpace: space, colors: vColors, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(vGrad,
                                 startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                                 endCenter:   CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: W, height: H))
        overlay.position  = .zero
        overlay.zPosition = 500
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let loc = t.location(in: self)

            // Tutorial overlay takes precedence — any tap advances it.
            if let overlay = TutorialOverlay.active(in: self) {
                overlay.advance(); return
            }

            // Quit-confirm modal consumes all input until resolved.
            if confirmingQuit {
                for n in nodes(at: loc) {
                    if QuitConfirmModal.isQuit(n)   { hideConfirmPanel(); dismissToMenu(); return }
                    if QuitConfirmModal.isCancel(n) { hideConfirmPanel(); return }
                }
                return
            }

            // Pause overlay — uses nodes(at:) since the panel has overlay-only buttons.
            if isPausedGame {
                for n in nodes(at: loc) {
                    let name = n.name ?? n.parent?.name ?? ""
                    if name == "resumeBtn" { resumeGame(); return }
                    if TutorialHelpButton.wasTapped(n) { presentBikeTutorial(autoTriggered: false); return }
                }
                return
            }

            // RACING FAST PATH — frame-based hit-testing, zero scene-graph traversal.
            // The tutorial help button is only present inside the pause overlay (handled above),
            // so we skip its nodes(at:) scan entirely while racing.
            if gState == .racing {
                if brakeFrame.contains(loc) {
                    brakeTouches.insert(t)
                    isBraking = true
                    brakeButtonNode?.color = SKColor(red: 0.741, green: 0.0, blue: 0.039, alpha: 1)
                    continue
                }
                if pauseBtnFrame.contains(loc) { pauseGame(); return }
                if closeBtnFrame.contains(loc) { showConfirmQuit(); return }
                // Steering — last-input-wins to recover from any stuck opposite touches.
                // Snap xVelocity to at least the kick threshold in the tapped direction
                // so the bike responds within one frame whether reversing or starting
                // from near-zero lateral velocity. steerAccel still ramps to the cap on hold.
                let kick = maxSteerVel * 0.30
                if loc.x < 0 {
                    rightTouches.removeAll(); steerRight = false
                    leftTouches.insert(t); steerLeft = true
                    if !pr.isJumping && pr.xVelocity > -kick {
                        pr.xVelocity = -kick
                    }
                } else {
                    leftTouches.removeAll(); steerLeft = false
                    rightTouches.insert(t); steerRight = true
                    if !pr.isJumping && pr.xVelocity < kick {
                        pr.xVelocity = kick
                    }
                }
                continue
            }

            // Non-racing states — keep the slower nodes(at:) paths.
            if closeBtnFrame.contains(loc) { showConfirmQuit(); return }

            switch gState {
            case .menu: startCountdown(); return
            case .countdown: return
            case .racing: break  // handled above
            case .gameOver, .victory:
                // Use nodes(at:) — atPoint can return the full-screen bg shape over the labels
                for n in nodes(at: loc) {
                    let name = n.name ?? n.parent?.name ?? ""
                    if name == "replayBtn" { resetGame(); return }
                    if name == "menuBtn"   { dismissToMenu(); return }
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        brakeTouches.subtract(touches)
        isBraking = !brakeTouches.isEmpty
        if !isBraking {
            brakeButtonNode?.color = Self.dsErrorContainer
        }
        leftTouches.subtract(touches); rightTouches.subtract(touches)
        steerLeft = !leftTouches.isEmpty; steerRight = !rightTouches.isEmpty
    }

    /// Drop UITouch references whose phase has moved past .moved.
    /// Recovers from iOS occasionally not delivering touchesEnded/Cancelled.
    private func pruneStaleTouches() {
        let isLive: (UITouch) -> Bool = { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary }
        let beforeL = leftTouches.count, beforeR = rightTouches.count, beforeB = brakeTouches.count
        leftTouches  = leftTouches.filter(isLive)
        rightTouches = rightTouches.filter(isLive)
        brakeTouches = brakeTouches.filter(isLive)
        if leftTouches.count  != beforeL { steerLeft  = !leftTouches.isEmpty }
        if rightTouches.count != beforeR { steerRight = !rightTouches.isEmpty }
        if brakeTouches.count != beforeB {
            isBraking = !brakeTouches.isEmpty
            if !isBraking { brakeButtonNode?.color = Self.dsErrorContainer }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func dismissToMenu() {
        bikeDodgeDelegate?.bikeDodgeSceneDidRequestDismiss(self)
        onComplete?(false)
    }

    // MARK: - Quit Confirmation
    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true
        steerLeft = false; steerRight = false; isBraking = false
        leftTouches.removeAll(); rightTouches.removeAll(); brakeTouches.removeAll()
        let panel = QuitConfirmModal.make(sceneSize: size)
        addChild(panel)
        confirmPanel = panel
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        confirmPanel = nil
    }

    // MARK: - Pause / Resume
    private func pauseGame() {
        guard gState == .racing, !isPausedGame else { return }
        isPausedGame = true
        steerLeft = false; steerRight = false; isBraking = false
        leftTouches.removeAll(); rightTouches.removeAll(); brakeTouches.removeAll()
        brakeButtonNode?.color = Self.dsErrorContainer
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        lastTime = 0
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
    }

    private func showPauseOverlay() {
        let ov = SKNode()
        ov.zPosition = 80
        pauseOverlayNode = ov
        addChild(ov)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2, width: W, height: H))
        dim.fillColor = SKColor(white: 0, alpha: 0.65)
        dim.strokeColor = .clear
        ov.addChild(dim)

        let panelW: CGFloat = min(W - 48, 280)
        let panelH: CGFloat = 200
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH), cornerRadius: 10)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.8)
        panel.lineWidth   = 2
        ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text      = "PAUSED"
        title.fontSize  = 16
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: 0, y: 56)
        ov.addChild(title)

        // Resume button
        let btnW: CGFloat = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 8)
        resumeBg.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
        resumeBg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        resumeBg.lineWidth   = 1.5
        resumeBg.position    = CGPoint(x: 0, y: 6)
        resumeBg.name        = "resumeBtn"
        ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text      = "RESUME"
        resumeLbl.fontSize  = 11
        resumeLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        resumeLbl.horizontalAlignmentMode = .center
        resumeLbl.verticalAlignmentMode   = .center
        resumeLbl.position  = CGPoint(x: 0, y: -1)
        resumeLbl.name      = "resumeBtn"
        resumeBg.addChild(resumeLbl)

        // Tutorial (?) help button inside pause panel
        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: 0, y: -62)
        ov.addChild(help)

        let helpHint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        helpHint.text      = "TUTORIAL"
        helpHint.fontSize  = 7
        helpHint.fontColor = SKColor(white: 0.6, alpha: 0.8)
        helpHint.horizontalAlignmentMode = .center
        helpHint.verticalAlignmentMode   = .top
        helpHint.position  = CGPoint(x: 0, y: -80)
        ov.addChild(helpHint)
    }
}

// MARK: - Numeric clamp helper (scoped to this file)
private extension CGFloat {
    func bikeClamp(_ range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
