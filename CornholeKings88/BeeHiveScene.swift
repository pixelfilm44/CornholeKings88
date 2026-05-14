import SpriteKit
import UIKit

// MARK: - BeeHiveScene
// Mini-game: bees fly down from a hive toward the player.
// The player swipes (same mechanic as CornholeMiniGameScene) to throw bags at them.
// 10 bees total, ramping from 1 → 3 concurrent. Bees zigzag for difficulty.
// Uses the player's current heart count from GameScene; writes remainingHearts back.

final class BeeHiveScene: SKScene {

    // MARK: - Public contract (mirrors CornholeMiniGameScene pattern)
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    /// Set by GameScene before presenting — reflects player's current hearts.
    var startingHearts: Int = 3
    /// Written before onComplete fires; GameScene reads this to sync the main HUD.
    private(set) var remainingHearts: Int = 3

    // MARK: - Private types

    private final class BeeBag {
        // 3D position (matches CornholeMiniGameScene.MiniGameBag)
        var bx, by, bz: CGFloat
        var vx, vy, vz: CGFloat
        var rot: CGFloat = 0
        var rotV: CGFloat = 0
        var isAlive = true
        var isGrounded = false
        let node: SKSpriteNode
        let shadow: SKSpriteNode
        var isHoney: Bool = false

        init(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, vz: CGFloat, isHoney: Bool = false) {
            self.bx = x; self.by = y; self.bz = 3
            self.vx = vx; self.vy = vy; self.vz = vz
            self.isHoney = isHoney

            let tex = SKTexture(imageNamed: "bag_16bit")
            tex.filteringMode = .nearest
            node = SKSpriteNode(texture: tex, size: CGSize(width: 44, height: 44))
            node.color = isHoney
                ? SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
                : SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
            node.colorBlendFactor = 0.65
            node.zPosition = 20

            shadow = SKSpriteNode(color: .black, size: CGSize(width: 44, height: 30))
            shadow.alpha = 0.35
            shadow.zPosition = 6
        }
    }

    private final class BeeEnemy {
        var x, y: CGFloat
        var baseX: CGFloat
        var speed: CGFloat
        var amplitude: CGFloat
        var frequency: CGFloat
        var zigzagTime: CGFloat = 0
        var isAlive = true
        let node: SKNode       // container positioned each frame
        let sprite: SKSpriteNode

        init(x: CGFloat, y: CGFloat,
             speed: CGFloat, amplitude: CGFloat, frequency: CGFloat,
             sprite: SKSpriteNode) {
            self.x = x; self.y = y; self.baseX = x
            self.speed = speed; self.amplitude = amplitude; self.frequency = frequency
            self.sprite = sprite
            node = SKNode()
            node.addChild(sprite)
            node.position = CGPoint(x: x, y: y)
            node.zPosition = 15
        }
    }

    // MARK: - Layout constants (computed in computeLayout)
    private var hiveY:      CGFloat = 0
    private var playerY:    CGFloat = 0
    private var powerScale: CGFloat = 0   // px-per-frame per px-of-swipe
    private let bagHitRadius: CGFloat = 35
    private let stingY:     CGFloat = 0   // unused; compare against playerY directly

    // MARK: - Physics constants (mirror CornholeMiniGameScene)
    private let gravityPerFrame: CGFloat = 0.50
    private let vzInitial:       CGFloat = 15.0

    // MARK: - Game state
    private var playerHearts: Int = 3
    private var activeBags:   [BeeBag]    = []
    private var activeBees:   [BeeEnemy]  = []
    private var beesSpawned:  Int = 0
    private var beesHit:      Int = 0
    private let totalBees:    Int = 10
    private var isGameOver    = false
    private var gameResult    = false
    private var spawnPending  = false

    // MARK: - Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // MARK: - Tutorial / confirm-quit state
    private var tutorialActive  = false
    private var confirmingQuit  = false
    private var confirmPanel:    SKNode?

    // MARK: - Node references
    private var gameWorldNode:       SKEffectNode!
    private var heartsNode:          SKNode?
    private var heartLabels:         [SKLabelNode] = []
    private var beesRemainingLabel:  SKLabelNode?
    private var timerLabel:          SKLabelNode?
    private var playerIndicator:     SKSpriteNode?
    private var messageNode:         SKNode?

    // MARK: - Elapsed timer
    private var elapsedSeconds: Int = 0
    private var elapsedFraction: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        playerHearts  = startingHearts
        remainingHearts = playerHearts
        computeLayout()
        setupGameWorld()
        setupUI()
        showFirstTimeTutorial()
        addCrtOverlay()
    }

    // MARK: - Layout

    private func computeLayout() {
        hiveY   =  size.height * 0.28
        playerY = -size.height * 0.30
        // Match cornhole's powerScale derivation: a swipe of ~38% screen height
        // should send the bag from playerY up to hiveY within one gravity arc.
        let distToHive   = abs(hiveY - playerY)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 60 frames
        let idealSwipe   = size.height * 0.38
        powerScale = distToHive / (flightFrames * idealSwipe)
    }

    // MARK: - Scene setup

    private func setupGameWorld() {
        gameWorldNode = SKEffectNode()
        if let filter = CIFilter(name: "CIPixellate") {
            filter.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = filter
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        addChild(gameWorldNode)

        // Grass background
        let bg = SKSpriteNode(color: SKColor(red: 0.18, green: 0.38, blue: 0.13, alpha: 1),
                              size: CGSize(width: size.width * 2, height: size.height * 2))
        bg.zPosition = -200
        gameWorldNode.addChild(bg)

        addGrassPattern()

        // Throw line at player position
        let throwLine = SKSpriteNode(
            color: SKColor(white: 1.0, alpha: 0.45),
            size: CGSize(width: size.width * 0.55, height: 1))
        throwLine.position = CGPoint(x: 0, y: playerY)
        throwLine.zPosition = -1
        gameWorldNode.addChild(throwLine)

        // Beehive art
        let hive = makeHiveSprite()
        hive.position = CGPoint(x: 0, y: hiveY)
        hive.zPosition = 12
        gameWorldNode.addChild(hive)

        // Player indicator (pulsing bag at the throw line)
        let bagTex = SKTexture(imageNamed: "bag_16bit")
        bagTex.filteringMode = .nearest
        let indicator = SKSpriteNode(texture: bagTex, size: CGSize(width: 40, height: 40))
        indicator.color = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        indicator.colorBlendFactor = 0.65
        indicator.position = CGPoint(x: 0, y: playerY)
        indicator.zPosition = 25
        gameWorldNode.addChild(indicator)
        playerIndicator = indicator
        indicator.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.55),
            SKAction.scale(to: 1.00, duration: 0.55),
        ])))
    }

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

    private func makeHiveSprite() -> SKNode {
        let container = SKNode()
        let ps = 5
        // Hexagonal hive dome — 1=dark amber outline, 2=amber fill
        let grid: [[Int]] = [
            [0,0,0,1,1,1,1,1,0,0,0],
            [0,0,1,2,2,2,2,2,1,0,0],
            [0,1,2,2,1,2,1,2,2,1,0],
            [0,1,2,1,2,2,2,1,2,1,0],
            [1,2,2,2,2,1,2,2,2,2,1],
            [1,2,2,1,2,2,2,1,2,2,1],
            [1,2,2,2,2,2,2,2,2,2,1],
            [0,1,2,2,1,2,1,2,2,1,0],
            [0,0,1,2,2,2,2,2,1,0,0],
            [0,0,0,1,1,2,1,1,0,0,0],
            [0,0,0,0,1,1,1,0,0,0,0],
        ]
        let cols = grid[0].count, rows = grid.count
        let imgW = CGFloat(cols * ps), imgH = CGFloat(rows * ps)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: imgW, height: imgH), false, 1.0)
        if let ctx = UIGraphicsGetCurrentContext() {
            let amber  = UIColor(red: 0.85, green: 0.60, blue: 0.10, alpha: 1)
            let dark   = UIColor(red: 0.50, green: 0.32, blue: 0.04, alpha: 1)
            for row in 0..<rows {
                for col in 0..<cols {
                    let v = grid[row][col]; guard v > 0 else { continue }
                    ctx.setFillColor((v == 2 ? amber : dark).cgColor)
                    ctx.fill(CGRect(x: CGFloat(col * ps), y: CGFloat(row * ps),
                                    width: CGFloat(ps), height: CGFloat(ps)))
                }
            }
        }
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: tex,
                                  size: CGSize(width: imgW * 2.5, height: imgH * 2.5))
        container.addChild(sprite)
        // Gentle sway
        container.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(byAngle:  0.05, duration: 1.4),
            SKAction.rotate(byAngle: -0.05, duration: 1.4),
        ])))
        return container
    }

    private func makeBeeSprite() -> SKSpriteNode {
        let ps = 5
        // 8 wide × 7 tall — head faces down (toward player), stinger at top.
        // 0=transparent, 1=black, 2=yellow, 3=wing (light blue-white)
        let grid: [[Int]] = [
            [0,0,0,1,1,0,0,0],   // stinger / tail (top)
            [0,3,1,2,2,1,3,0],   // wings + yellow stripe
            [3,3,1,1,1,1,3,3],   // wings spread + black thorax
            [0,3,1,2,2,1,3,0],   // wings + yellow stripe
            [0,0,1,1,1,1,0,0],   // black abdomen / neck
            [0,0,1,2,2,1,0,0],   // yellow head (facing down)
            [0,0,0,1,1,0,0,0],   // antennae
        ]
        let cols = grid[0].count, rows = grid.count
        let imgW = CGFloat(cols * ps), imgH = CGFloat(rows * ps)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: imgW, height: imgH), false, 1.0)
        if let ctx = UIGraphicsGetCurrentContext() {
            let black  = UIColor(red: 0.08, green: 0.06, blue: 0.02, alpha: 1)
            let yellow = UIColor(red: 0.95, green: 0.82, blue: 0.10, alpha: 1)
            let wing   = UIColor(red: 0.78, green: 0.90, blue: 1.00, alpha: 0.72)
            for row in 0..<rows {
                for col in 0..<cols {
                    let v = grid[row][col]; guard v > 0 else { continue }
                    let color: UIColor
                    switch v {
                    case 1: color = black
                    case 2: color = yellow
                    default: color = wing
                    }
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(CGRect(x: CGFloat(col * ps), y: CGFloat(row * ps),
                                    width: CGFloat(ps), height: CGFloat(ps)))
                }
            }
        }
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: tex, size: CGSize(width: imgW * 2, height: imgH * 2))
        // Wing-flap
        sprite.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: 0.70, duration: 0.07),
            SKAction.scaleX(to: 1.00, duration: 0.07),
        ])))
        return sprite
    }

    // MARK: - UI

    private func setupUI() {
        let topH    = size.height * 0.135
        let bottomH = size.height * 0.085

        addChrome(y:  size.height / 2 - topH    / 2, h: topH)
        addChrome(y: -size.height / 2 + bottomH / 2, h: bottomH)

        let barCenterY = size.height / 2 - topH / 2
        let btnSize: CGFloat = min(44, topH * 0.88)

        // ── Close button — metal iron style, LEFT side ──
        let closeBtn = makeMetalCloseButton(size: btnSize)
        closeBtn.position  = CGPoint(x: -size.width / 2 + btnSize / 2 + 8, y: barCenterY)
        closeBtn.name      = "closeButton"
        closeBtn.zPosition = 700
        addChild(closeBtn)

        // ── HUD chip — dark panel to the right of the close button ──
        let chipLeft:   CGFloat = -size.width / 2 + btnSize + 8 + 8
        let chipRight:  CGFloat =  size.width / 2 - 8
        let chipWidth              = chipRight - chipLeft
        let chipCenterX            = chipLeft + chipWidth / 2

        let chip = makeHudChip(width: chipWidth, height: btnSize)
        chip.position  = CGPoint(x: chipCenterX, y: barCenterY)
        chip.zPosition = 600
        addChild(chip)

        // Content inside chip — three sections: HIT | timer | hearts
        let halfW = chipWidth / 2
        let pad: CGFloat = 10

        // Section 1 — HIT count (gold, left-aligned)
        let hitLbl = makeLabel(text: "HIT:0", size: 8,
                               color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        hitLbl.horizontalAlignmentMode = .left
        hitLbl.position  = CGPoint(x: -halfW + pad, y: 0)
        hitLbl.zPosition = 601
        chip.addChild(hitLbl)
        beesRemainingLabel = hitLbl

        // Divider 1
        let div1 = SKSpriteNode(
            color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.28),
            size: CGSize(width: 1, height: btnSize * 0.50))
        div1.position  = CGPoint(x: -halfW + chipWidth * 0.36, y: 0)
        div1.zPosition = 601
        chip.addChild(div1)

        // Section 2 — elapsed timer (blue, centered)
        let tLbl = makeLabel(text: "0:00", size: 8,
                             color: SKColor(red: 0.35, green: 0.61, blue: 0.83, alpha: 1))
        tLbl.horizontalAlignmentMode = .center
        tLbl.position  = CGPoint(x: -halfW + chipWidth * 0.52, y: 0)
        tLbl.zPosition = 601
        chip.addChild(tLbl)
        timerLabel = tLbl

        // Divider 2
        let div2 = SKSpriteNode(
            color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.28),
            size: CGSize(width: 1, height: btnSize * 0.50))
        div2.position  = CGPoint(x: -halfW + chipWidth * 0.68, y: 0)
        div2.zPosition = 601
        chip.addChild(div2)

        // Section 3 — hearts (3 slots, right side; color changes on loss, no remove)
        let totalSlots = playerHearts   // show exactly as many as the player started with
        let heartSpacing: CGFloat = 16
        let heartsWidth = CGFloat(totalSlots - 1) * heartSpacing
        let heartsStartX = halfW - pad - heartsWidth

        let hContainer = SKNode()
        hContainer.position  = CGPoint(x: heartsStartX, y: 0)
        hContainer.zPosition = 601
        chip.addChild(hContainer)
        heartsNode = hContainer
        heartLabels.removeAll()
        for i in 0..<totalSlots {
            let lbl = SKLabelNode(text: "♥")
            lbl.fontName = "AvenirNext-Heavy"
            lbl.fontSize = 15
            lbl.fontColor = SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1.0)
            lbl.verticalAlignmentMode   = .center
            lbl.horizontalAlignmentMode = .left
            lbl.position = CGPoint(x: CGFloat(i) * heartSpacing, y: 0)
            hContainer.addChild(lbl)
            heartLabels.append(lbl)
        }

        // Bottom chrome hint
        let hint = makeLabel(text: "SWIPE TO THROW", size: 7,
                             color: SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1))
        hint.horizontalAlignmentMode = .center
        hint.position  = CGPoint(x: 0, y: -size.height / 2 + bottomH / 2)
        hint.zPosition = 600
        addChild(hint)
    }

    // Metal close button matching design spec (iron gradient + rivets + red X)
    private func makeMetalCloseButton(size s: CGFloat) -> SKNode {
        let container = SKNode()

        // Iron gray background
        let bg = SKSpriteNode(color: SKColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1),
                              size: CGSize(width: s, height: s))
        bg.zPosition = 0
        container.addChild(bg)

        // Top highlight bevel (iron sheen)
        let bevel = SKSpriteNode(color: SKColor(white: 1.0, alpha: 0.12),
                                 size: CGSize(width: s - 4, height: 3))
        bevel.position  = CGPoint(x: 0, y: s / 2 - 4)
        bevel.zPosition = 1
        container.addChild(bevel)

        // Border outline
        let border = SKShapeNode(rect: CGRect(x: -s/2, y: -s/2, width: s, height: s),
                                 cornerRadius: 5)
        border.strokeColor = SKColor(white: 0.07, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 2
        border.zPosition   = 2
        container.addChild(border)

        // Red X mark
        let xPath = CGMutablePath()
        let inset: CGFloat = s * 0.28
        xPath.move(to: CGPoint(x: -s/2 + inset, y: -s/2 + inset))
        xPath.addLine(to: CGPoint(x:  s/2 - inset, y:  s/2 - inset))
        xPath.move(to: CGPoint(x:  s/2 - inset, y: -s/2 + inset))
        xPath.addLine(to: CGPoint(x: -s/2 + inset, y:  s/2 - inset))
        let xShape = SKShapeNode(path: xPath)
        xShape.strokeColor = SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1)
        xShape.lineWidth   = 3
        xShape.lineCap     = .square
        xShape.zPosition   = 3
        container.addChild(xShape)

        // Corner rivets
        for (rx, ry): (CGFloat, CGFloat) in [
            (-s/2 + 5,  s/2 - 5),
            ( s/2 - 5,  s/2 - 5),
            (-s/2 + 5, -s/2 + 5),
            ( s/2 - 5, -s/2 + 5),
        ] {
            let rivet = SKShapeNode(circleOfRadius: 2)
            rivet.fillColor   = SKColor(white: 0.55, alpha: 1)
            rivet.strokeColor = SKColor(white: 0.25, alpha: 1)
            rivet.lineWidth   = 0.5
            rivet.position    = CGPoint(x: rx, y: ry)
            rivet.zPosition   = 4
            container.addChild(rivet)
        }

        return container
    }

    // Dark HUD chip panel (design: dark bg + inner gold border + corner rivets)
    private func makeHudChip(width w: CGFloat, height h: CGFloat) -> SKNode {
        let container = SKNode()

        let bg = SKSpriteNode(
            color: SKColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 0.96),
            size: CGSize(width: w, height: h))
        bg.zPosition = 0
        container.addChild(bg)

        // Inner gold border inset
        let border = SKShapeNode(rect: CGRect(x: -w/2 + 1, y: -h/2 + 1, width: w - 2, height: h - 2),
                                 cornerRadius: 4)
        border.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.22)
        border.fillColor   = .clear
        border.lineWidth   = 1
        border.zPosition   = 1
        container.addChild(border)

        // Outer dark border
        let outer = SKShapeNode(rect: CGRect(x: -w/2, y: -h/2, width: w, height: h),
                                cornerRadius: 5)
        outer.strokeColor = SKColor(red: 0.10, green: 0.06, blue: 0.02, alpha: 1)
        outer.fillColor   = .clear
        outer.lineWidth   = 2
        outer.zPosition   = 2
        container.addChild(outer)

        // Corner rivets (4px diameter)
        for (rx, ry): (CGFloat, CGFloat) in [
            (-w/2 + 5,  h/2 - 5),
            ( w/2 - 5,  h/2 - 5),
            (-w/2 + 5, -h/2 + 5),
            ( w/2 - 5, -h/2 + 5),
        ] {
            let rivet = SKShapeNode(circleOfRadius: 2)
            rivet.fillColor   = SKColor(white: 0.50, alpha: 1)
            rivet.strokeColor = SKColor(white: 0.22, alpha: 1)
            rivet.lineWidth   = 0.5
            rivet.position    = CGPoint(x: rx, y: ry)
            rivet.zPosition   = 3
            container.addChild(rivet)
        }

        return container
    }

    private func addChrome(y: CGFloat, h: CGFloat) {
        let bar = SKSpriteNode(color: SKColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 0.88),
                               size: CGSize(width: size.width, height: h))
        bar.position  = CGPoint(x: 0, y: y)
        bar.zPosition = 500
        addChild(bar)

        let border = SKSpriteNode(color: SKColor(red: 0.35, green: 0.23, blue: 0.09, alpha: 1),
                                  size: CGSize(width: size.width, height: 2))
        border.position  = CGPoint(x: 0, y: y + (y > 0 ? -h / 2 : h / 2))
        border.zPosition = 501
        addChild(border)
    }

    private func makeLabel(text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.fontSize  = size
        l.fontColor = color
        l.text      = text
        l.verticalAlignmentMode = .center
        return l
    }

    private func makeButton(label: String, fg: SKColor, bg: SKColor, size: CGSize) -> SKNode {
        let n       = SKNode()
        let backing = SKSpriteNode(color: bg, size: size)
        backing.zPosition = 0
        n.addChild(backing)
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.fontSize              = 10
        lbl.fontColor             = fg
        lbl.text                  = label
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.zPosition             = 1
        n.addChild(lbl)
        return n
    }

    // MARK: - Game flow

    private func startGame() {
        spawnNextBee()
    }

    private var maxConcurrent: Int {
        if beesSpawned < 3 { return 1 }
        if beesSpawned < 7 { return 2 }
        return 3
    }

    private func spawnNextBee() {
        guard !isGameOver, activeBees.count < maxConcurrent else { return }

        beesSpawned += 1

        // Difficulty ramps linearly to bee 10 then plateaus at max difficulty.
        let t = min(1.0, CGFloat(beesSpawned - 1) / CGFloat(totalBees - 1))
        let speed     = CGFloat.random(in: (50 + t * 40)...(80 + t * 60))
        let amplitude = CGFloat.random(in: (20 + t * 20)...(40 + t * 25))
        let frequency = CGFloat.random(in: (1.0 + t * 1.0)...(1.8 + t * 1.4))
        let startX    = CGFloat.random(in: -size.width * 0.30...size.width * 0.30)

        let bee = BeeEnemy(x: startX, y: hiveY - 24,
                           speed: speed,
                           amplitude: amplitude,
                           frequency: frequency,
                           sprite: makeBeeSprite())
        gameWorldNode.addChild(bee.node)
        activeBees.append(bee)

        run(SKAction.playSoundFileNamed("gopher_pop.wav", waitForCompletion: false))
    }

    private func scheduleNextSpawn() {
        guard !spawnPending, !isGameOver else { return }
        spawnPending = true
        run(SKAction.sequence([
            SKAction.wait(forDuration: TimeInterval.random(in: 0.7...1.8)),
            SKAction.run { [weak self] in
                guard let self, !self.isGameOver else { return }
                self.spawnPending = false
                while self.activeBees.count < self.maxConcurrent {
                    self.spawnNextBee()
                }
            },
        ]), withKey: "beeSpawn")
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let dt: CGFloat = 1.0 / 60.0

        // Elapsed timer (counts up, updates once per second)
        if !tutorialActive {
            elapsedFraction += dt
            if elapsedFraction >= 1.0 {
                elapsedFraction -= 1.0
                elapsedSeconds += 1
                let m = elapsedSeconds / 60
                let s = elapsedSeconds % 60
                timerLabel?.text = "\(m):\(String(format: "%02d", s))"
            }
        }

        updateBags(dt)
        updateBees(dt)
        checkBagBeeCollisions()
        checkBeesReachedPlayer()

        if !spawnPending && activeBees.count < maxConcurrent {
            scheduleNextSpawn()
        }
    }

    private func updateBags(_ dt: CGFloat) {
        // Prune bags whose landing animation finished (node detached from scene).
        activeBags.removeAll { $0.isGrounded && $0.node.parent == nil }

        var dead: [BeeBag] = []
        for bag in activeBags where bag.isAlive && !bag.isGrounded {
            // Integrate physics — identical to CornholeMiniGameScene.updateBagPhysics
            bag.vz -= gravityPerFrame
            bag.bx += bag.vx
            bag.by += bag.vy
            bag.bz += bag.vz

            bag.rot += bag.rotV
            bag.node.zRotation = bag.rot

            if bag.bz <= 0 {
                bag.bz = 0
                landBag(bag)
                continue
            }

            // Render: visual Y elevated by z for arc perspective
            let visualY = bag.by + bag.bz * 0.50
            bag.node.position   = CGPoint(x: bag.bx, y: visualY)
            bag.shadow.position = CGPoint(x: bag.bx + bag.bz * 0.08, y: bag.by)

            let heightScale = 1.0 + bag.bz * 0.012
            bag.node.setScale(heightScale)
            bag.shadow.alpha   = max(0.08, 0.35 - bag.bz * 0.005)
            bag.shadow.setScale(max(0.5, 1.0 - bag.bz * 0.005))

            // Depth sort: bags closer to camera appear in front
            bag.node.zPosition = 20 + bag.bz * 0.1 - bag.by * 0.02

            let hw = size.width  / 2 + 40
            let hh = size.height / 2 + 40
            if bag.bx < -hw || bag.bx > hw || bag.by < -hh || bag.by > hh {
                dead.append(bag)
            }
        }
        dead.forEach { removeBag($0) }
    }

    /// Bag has landed at bz=0. Stop motion, settle visually, fade out.
    private func landBag(_ bag: BeeBag) {
        bag.isGrounded = true
        bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
        bag.node.position   = CGPoint(x: bag.bx, y: bag.by)
        bag.shadow.position = CGPoint(x: bag.bx, y: bag.by)

        // Land at base scale, then shrink to 0.75 (mirrors off-board cornhole behaviour)
        // before fading out so the player sees the bag come to rest.
        let settle = SKAction.scale(to: 0.75, duration: 0.12)
        let pause  = SKAction.wait(forDuration: 0.30)
        let fade   = SKAction.fadeOut(withDuration: 0.35)
        bag.node.setScale(1.0)
        bag.node.run(SKAction.sequence([settle, pause, fade, SKAction.removeFromParent()]))
        bag.shadow.setScale(1.0)
        bag.shadow.run(SKAction.sequence([
            SKAction.scale(to: 0.75, duration: 0.12),
            SKAction.wait(forDuration: 0.30),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))
    }

    private func updateBees(_ dt: CGFloat) {
        for bee in activeBees where bee.isAlive {
            bee.zigzagTime += dt
            bee.y -= bee.speed * dt
            bee.x  = bee.baseX + bee.amplitude * sin(bee.zigzagTime * bee.frequency)
            bee.node.position = CGPoint(x: bee.x, y: bee.y)
        }
    }

    private func checkBagBeeCollisions() {
        // Compare bee position against the bag's *visual* position (by + bz*0.50)
        // so a hit registers when the bag visually overlaps the bee mid-arc.
        var hits: [(bag: BeeBag, bee: BeeEnemy)] = []
        for bag in activeBags where bag.isAlive && !bag.isGrounded {
            let visualY = bag.by + bag.bz * 0.50
            for bee in activeBees where bee.isAlive {
                let dx = bag.bx - bee.x, dy = visualY - bee.y
                if dx * dx + dy * dy < bagHitRadius * bagHitRadius {
                    hits.append((bag, bee))
                    break
                }
            }
        }
        hits.forEach { hitBee($0.bee, withBag: $0.bag) }
    }

    private func checkBeesReachedPlayer() {
        let stingers = activeBees.filter { $0.isAlive && $0.y <= playerY + 10 }
        stingers.forEach { stingPlayer(bee: $0) }
    }

    private func hitBee(_ bee: BeeEnemy, withBag bag: BeeBag) {
        guard bee.isAlive && bag.isAlive else { return }
        bee.isAlive = false
        beesHit += 1
        updateBeesLabel()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        run(SKAction.playSoundFileNamed("hole_score.wav", waitForCompletion: false))

        bee.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.8, duration: 0.10),
                SKAction.fadeOut(withDuration: 0.14),
            ]),
            SKAction.removeFromParent(),
        ]))

        showFloatingLabel("HIT!", at: CGPoint(x: bee.x, y: bee.y),
                          color: SKColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1))

        removeBag(bag)
        activeBees.removeAll { $0 === bee }

        // Reaching 10 hits unlocks the honey-bag reward but does NOT end the game —
        // the player keeps fighting until they run out of hearts. Show a one-time
        // celebration so they know the bonus is locked in.
        if beesHit == totalBees {
            showFloatingLabel("+3 HONEY UNLOCKED!",
                              at: CGPoint(x: 0, y: 0),
                              color: SKColor(red: 0.95, green: 0.82, blue: 0.10, alpha: 1))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func stingPlayer(bee: BeeEnemy) {
        guard bee.isAlive else { return }
        bee.isAlive = false
        activeBees.removeAll { $0 === bee }

        bee.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.15, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18),
            ]),
            SKAction.removeFromParent(),
        ]))

        playerHearts = max(0, playerHearts - 1)
        updateHeartsDisplay()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        run(SKAction.playSoundFileNamed("dog_bite.wav", waitForCompletion: false))
        showFloatingLabel("OUCH!", at: CGPoint(x: bee.x, y: playerY + 24),
                          color: SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1))

        playerIndicator?.run(SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 1.0, duration: 0.0),
            SKAction.wait(forDuration: 0.12),
            SKAction.colorize(withColorBlendFactor: 0.65, duration: 0.20),
        ]))

        if playerHearts <= 0 {
            // Only end condition is running out of hearts. The win/lose flag is
            // determined by whether the player hit at least 10 bees during the run.
            triggerGameOver(playerWon: beesHit >= totalBees)
        }
    }

    private func removeBag(_ bag: BeeBag) {
        bag.isAlive = false
        bag.node.removeFromParent()
        bag.shadow.removeFromParent()
        activeBags.removeAll { $0 === bag }
    }

    // MARK: - Throwing (swipe mechanic identical to CornholeMiniGameScene)

    private func throwBag(dx: CGFloat, dy: CGFloat) {
        let vx = dx * powerScale
        let vy = dy * powerScale
        let bag = BeeBag(x: 0, y: playerY, vx: vx, vy: vy, vz: vzInitial)

        // Rotation spin proportional to throw speed (matches cornhole)
        let speed = sqrt(vx * vx + vy * vy)
        bag.rotV = (Bool.random() ? 1.0 : -1.0) * (0.04 + speed * 0.015)

        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)
        // PLACEHOLDER: add bag_throw.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("bag_land.wav", waitForCompletion: false))
    }

    // MARK: - CRT Overlay
    private func addCrtOverlay() {
        let w = size.width, h = size.height
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            var y: CGFloat = 0
            while y < h { c.fill(CGRect(x: 0, y: y, width: w, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.18).cgColor,
                           UIColor(white: 0, alpha: 0.70).cgColor] as CFArray
            let vGrad = CGGradient(colorsSpace: space, colors: vColors, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(vGrad,
                                 startCenter: CGPoint(x: w/2, y: h/2), startRadius: 0,
                                 endCenter:   CGPoint(x: w/2, y: h/2), endRadius: max(w, h) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: w, height: h))
        overlay.position  = .zero
        overlay.zPosition = 4000
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        if tutorialActive || confirmingQuit || isGameOver { handleButtonTap(at: loc); return }
        if handleButtonTap(at: loc) { return }

        touchStart = loc
        aimingLine?.removeFromParent()
        let line = SKShapeNode()
        line.strokeColor = SKColor(white: 1, alpha: 0.40)
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

        if isGameOver { handleButtonTap(at: end); touchStart = nil; return }
        if handleButtonTap(at: end) { touchStart = nil; return }

        guard let start = touchStart else { return }
        touchStart = nil

        let dx = end.x - start.x
        let dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) > 8 else { return }

        throwBag(dx: dx, dy: dy)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimingLine?.removeFromParent()
        aimingLine = nil
        touchStart = nil
    }

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
                    restartGame()
                    return true
                case "exitBtn":
                    dismissScene(playerWon: gameResult)
                    return true
                default:
                    n = current.parent
                }
            }
        }
        return false
    }

    // MARK: - Effects

    private func showFloatingLabel(_ text: String, at pos: CGPoint, color: SKColor) {
        let lbl = makeLabel(text: text, size: max(7, size.width * 0.048), color: color)
        lbl.position  = pos
        lbl.zPosition = 800
        lbl.alpha     = 0
        addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.08),
            SKAction.moveBy(x: 0, y: 30, duration: 0.60),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - HUD updates

    private func updateHeartsDisplay() {
        let lostIdx = playerHearts   // playerHearts was just decremented; this index is now lost
        guard lostIdx >= 0, lostIdx < heartLabels.count else { return }
        let lost = heartLabels[lostIdx]
        guard lost.parent != nil else { return }
        lost.run(.sequence([
            .scale(to: 1.50, duration: 0.08),
            .group([.scale(to: 0, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent(),
        ]))
    }

    private func updateBeesLabel() {
        let star = beesHit >= totalBees ? "★" : ""
        beesRemainingLabel?.text = "HIT:\(beesHit)\(star)"
    }

    private func rebuildHearts() {
        heartsNode?.removeAllChildren()
        heartLabels.removeAll()
        let heartSpacing: CGFloat = 16
        for i in 0..<playerHearts {
            let lbl = SKLabelNode(text: "♥")
            lbl.fontName = "AvenirNext-Heavy"
            lbl.fontSize = 15
            lbl.fontColor = SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1.0)
            lbl.verticalAlignmentMode   = .center
            lbl.horizontalAlignmentMode = .left
            lbl.position = CGPoint(x: CGFloat(i) * heartSpacing, y: 0)
            heartsNode?.addChild(lbl)
            heartLabels.append(lbl)
        }
    }

    // MARK: - Game-over panel

    private func triggerGameOver(playerWon: Bool) {
        guard !isGameOver else { return }
        isGameOver  = true
        gameResult  = playerWon
        remainingHearts = playerHearts
        removeAction(forKey: "beeSpawn")

        run(SKAction.playSoundFileNamed(playerWon ? "game_win.wav" : "game_lose.wav",
                                        waitForCompletion: false))
        run(SKAction.wait(forDuration: 0.55)) { [weak self] in
            self?.showGameOverPanel(playerWon: playerWon)
        }
    }

    private func showGameOverPanel(playerWon: Bool) {
        messageNode?.removeFromParent()

        let panelW = size.width  * 0.82
        let panelH = size.height * 0.56
        let fs     = max(6, size.width * 0.048)

        let panel = SKNode()
        panel.zPosition = 1000
        panel.alpha     = 0

        let backing = SKSpriteNode(
            color: SKColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 0.94),
            size: CGSize(width: panelW, height: panelH))
        panel.addChild(backing)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        panel.addChild(border)

        let titleColor = playerWon
            ? SKColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1)
            : SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)

        let title = makeLabel(text: playerWon ? "YOU WIN!" : "STUNG OUT!",
                              size: fs * 0.75, color: titleColor)
        title.position = CGPoint(x: 0, y: panelH * 0.30)
        panel.addChild(title)

        if playerWon {
            let reward = makeLabel(text: "+3 HONEY BAGS!",
                                   size: fs * 0.55,
                                   color: SKColor(red: 0.95, green: 0.82, blue: 0.10, alpha: 1))
            reward.position = CGPoint(x: 0, y: panelH * 0.10)
            panel.addChild(reward)

            let detail = makeLabel(text: "STICKY IN CORNHOLE!",
                                   size: fs * 0.44,
                                   color: SKColor(white: 0.68, alpha: 1))
            detail.position = CGPoint(x: 0, y: -panelH * 0.04)
            panel.addChild(detail)
        } else {
            let sub = makeLabel(text: "BEES HIT: \(beesHit) / \(totalBees)",
                                size: fs * 0.55,
                                color: SKColor(white: 0.78, alpha: 1))
            sub.position = CGPoint(x: 0, y: panelH * 0.08)
            panel.addChild(sub)

            let sub2 = makeLabel(text: "REACH \(totalBees) FOR HONEY",
                                 size: fs * 0.45,
                                 color: SKColor(white: 0.55, alpha: 1))
            sub2.position = CGPoint(x: 0, y: -panelH * 0.05)
            panel.addChild(sub2)
        }

        let tryBtn = makeButton(label: "TRY AGAIN",
                                fg: .white,
                                bg: SKColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1),
                                size: CGSize(width: panelW * 0.60, height: fs * 1.8))
        tryBtn.position = CGPoint(x: 0, y: -panelH * 0.24)
        tryBtn.name     = "playAgainBtn"
        panel.addChild(tryBtn)

        let exitBtn = makeButton(label: "EXIT",
                                 fg: .white,
                                 bg: SKColor(red: 0.42, green: 0.10, blue: 0.10, alpha: 1),
                                 size: CGSize(width: panelW * 0.40, height: fs * 1.8))
        exitBtn.position = CGPoint(x: 0, y: -panelH * 0.38)
        exitBtn.name     = "exitBtn"
        panel.addChild(exitBtn)

        addChild(panel)
        messageNode = panel
        panel.run(.fadeIn(withDuration: 0.28))
    }

    private func restartGame() {
        messageNode?.removeFromParent()
        messageNode = nil
        removeAction(forKey: "beeSpawn")

        activeBags.forEach { $0.node.removeFromParent(); $0.shadow.removeFromParent() }
        activeBags.removeAll()
        activeBees.forEach { $0.node.removeFromParent() }
        activeBees.removeAll()

        beesSpawned     = 0
        beesHit         = 0
        isGameOver      = false
        gameResult      = false
        spawnPending    = false
        playerHearts    = 3
        remainingHearts = playerHearts
        elapsedSeconds  = 0
        elapsedFraction = 0
        timerLabel?.text = "0:00"

        rebuildHearts()
        updateBeesLabel()
        spawnNextBee()
    }

    // MARK: - First-time tutorial

    private func showFirstTimeTutorial() {
        tutorialActive = true

        let panelW = size.width  * 0.84
        let panelH = size.height * 0.58
        let fs     = max(5, size.width * 0.038)

        let overlay = SKNode()
        overlay.zPosition = 2000
        overlay.name      = "tutorialOverlay"

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.78),
                               size: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.addChild(dim)

        let panel = SKSpriteNode(
            color: SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.97),
            size: CGSize(width: panelW, height: panelH))
        overlay.addChild(panel)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        overlay.addChild(border)

        let title = makeLabel(text: "BEEHIVE BATTLE!",
                              size: fs * 1.0,
                              color: SKColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1))
        title.position = CGPoint(x: 0, y: panelH * 0.34)
        overlay.addChild(title)

        let lines: [(String, CGFloat)] = [
            ("Bees fly down from the hive",  panelH * 0.18),
            ("Swipe up to throw a bag",       panelH * 0.05),
            ("Hit 10 bees to earn honey!",   -panelH * 0.08),
            ("Don't get stung!",             -panelH * 0.21),
        ]
        for (text, y) in lines {
            let lbl = makeLabel(text: text, size: fs * 0.68,
                                color: SKColor(white: 0.82, alpha: 1))
            lbl.position = CGPoint(x: 0, y: y)
            overlay.addChild(lbl)
        }

        let gotIt = makeButton(label: "GOT IT!",
                               fg: .white,
                               bg: SKColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1),
                               size: CGSize(width: panelW * 0.55, height: fs * 1.9))
        gotIt.position = CGPoint(x: 0, y: -panelH * 0.37)
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
        startGame()
    }

    // MARK: - Quit confirmation

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true

        let panelW = size.width  * 0.70
        let panelH = size.height * 0.30
        let fs     = max(5, size.width * 0.042)

        let panel = SKNode()
        panel.zPosition = 3000
        panel.name      = "confirmPanel"

        let bg = SKSpriteNode(
            color: SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.97),
            size: CGSize(width: panelW, height: panelH))
        panel.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        panel.addChild(border)

        let q = makeLabel(text: "QUIT GAME?", size: fs, color: SKColor(white: 0.88, alpha: 1))
        q.position = CGPoint(x: 0, y: panelH * 0.22)
        panel.addChild(q)

        let cancel = makeButton(label: "CANCEL", fg: .white,
                                bg: SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                                size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        cancel.position = CGPoint(x: -panelW * 0.24, y: -panelH * 0.22)
        cancel.name     = "cancelQuitBtn"
        panel.addChild(cancel)

        let quit = makeButton(label: "QUIT", fg: .white,
                              bg: SKColor(red: 0.50, green: 0.10, blue: 0.10, alpha: 1),
                              size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        quit.position = CGPoint(x: panelW * 0.24, y: -panelH * 0.22)
        quit.name     = "confirmQuitBtn"
        panel.addChild(quit)

        panel.alpha = 0
        addChild(panel)
        confirmPanel = panel
        panel.run(.fadeIn(withDuration: 0.18))
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        remainingHearts = playerHearts
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        let transition = SKTransition.push(with: .down, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(prev, transition: transition)
    }
}
