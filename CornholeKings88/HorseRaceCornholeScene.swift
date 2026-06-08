import SpriteKit
import UIKit

// MARK: - HorseRaceCornholeScene
//
// Simultaneous-throw cornhole horse race: player (red) vs AI (blue).
// One board with three holes:
//   • Large hole closest to player  → 1 space
//   • Medium hole middle distance   → 2 spaces
//   • Small hole farthest away      → 3 spaces
// Each side may throw a new bag as soon as their previous bag has touched
// down (board, hole, or off-board). Bags collide elastically and can knock
// each other into or away from a hole. First horse to 12 spaces wins.
//
// Picker-only mini-game: awardsRewards is left false and no item is granted.
final class HorseRaceCornholeScene: SKScene {

    // MARK: - Public
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?

    // MARK: - Types
    private enum BagOwner { case player, ai }

    enum Opponent { case tommy, jen }

    private final class RaceBag {
        var bx, by, bz: CGFloat
        var vx, vy, vz: CGFloat
        var rot:  CGFloat = 0
        var rotV: CGFloat = 0
        let owner: BagOwner
        var isGrounded = false
        var hasScored  = false
        var hasLanded  = false
        var hasAppliedGroundScale = false
        var hasAwardedSpaces = false
        var baseScale: CGFloat = 1.0
        let node:   SKSpriteNode
        let shadow: SKSpriteNode

        init(owner: BagOwner, startX: CGFloat, startY: CGFloat) {
            self.owner = owner
            self.bx = startX; self.by = startY; self.bz = 3
            self.vx = 0; self.vy = 0; self.vz = 0

            let color: SKColor = owner == .player
                ? SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
                : SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1)
            let tex = SKTexture(imageNamed: "bag_16bit")
            tex.filteringMode = .nearest
            node = SKSpriteNode(texture: tex, size: CGSize(width: 50, height: 50))
            node.color            = color
            node.colorBlendFactor = 0.65
            node.zPosition        = 20

            shadow = SKSpriteNode(color: .black,
                                  size: CGSize(width: 50, height: 35))
            shadow.alpha     = 0.35
            shadow.zPosition = 6

            node.position   = CGPoint(x: bx, y: by + bz * 0.50)
            shadow.position = CGPoint(x: bx, y: by)
        }

        var isMoving: Bool { bz > 0.15 || abs(vx) > 0.012 || abs(vy) > 0.012 }
    }

    private struct Hole {
        let center: CGPoint
        let radius: CGFloat
        let spaces: Int
    }

    // MARK: - Constants
    private let gravityPerFrame: CGFloat = 0.50
    private let vzInitial:       CGFloat = 15.0
    private let totalSpaces = 12

    // MARK: - Layout
    private var boardY:     CGFloat = 0
    private var throwLineY: CGFloat = 0
    private var boardHalfW: CGFloat = 0
    private var boardHalfH: CGFloat = 0
    private var powerScale: CGFloat = 0
    private var holes: [Hole] = []
    private var raceLeftX:  CGFloat = 0
    private var raceRightX: CGFloat = 0
    private var raceRedY:   CGFloat = 0
    private var raceBlueY:  CGFloat = 0

    // Oscillating throw-line indicator (red bag the player swipes up).
    private var turnIndicator: SKSpriteNode?
    private var targetX: CGFloat = 0
    private var targetRange: CGFloat = 0
    private var targetSpeed: CGFloat = 0   // source pixels per second
    private var targetMovingRight = true

    // MARK: - Game state
    private var isGameOver   = false
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var activeBags: [RaceBag] = []
    private var lastPlayerBag: RaceBag?
    private var lastAIBag:     RaceBag?
    private var playerSpaces = 0
    private var aiSpaces     = 0
    /// Earliest scene time when the AI is allowed to start its next throw.
    private var aiReadyTime: TimeInterval = 0
    private var currentSceneTime: TimeInterval = 0

    // Race horses
    private var redHorse:  SKSpriteNode?
    private var blueHorse: SKSpriteNode?

    // Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // HUD
    private var gameWorldNode: SKEffectNode!
    private var scoreLabel: SKLabelNode?
    private var messageNode: SKNode?
    private var confirmingQuit = false
    private var confirmPanel: SKNode?

    // Countdown + tutorial gating
    private var countdownActive = true
    private var tutorialUp = false

    // Opponent selection
    private var selectedOpponent: Opponent = .tommy
    private var awaitingOpponentChoice = true
    private var opponentPickerNode: SKNode?
    private var opponentName: String { selectedOpponent == .tommy ? "TOMMY" : "JEN" }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        preloadAssets()
        computeLayout()
        setupGameWorld()
        setupBoard()
        setupRaceLane()
        setupUI()
        addCrtOverlay()

        // Hide the throw-line indicator until the countdown reaches GO.
        turnIndicator?.isHidden = true

        // Pick the opponent first — tutorial + countdown run after the choice.
        presentOpponentPicker()
    }

    // MARK: - Opponent picker

    private func presentOpponentPicker() {
        awaitingOpponentChoice = true
        let W = size.width, H = size.height
        let gold = SKColor(red: 0xf0/255.0, green: 0xc0/255.0, blue: 0x60/255.0, alpha: 1)

        let container = SKNode()
        container.zPosition = 4000
        container.name = "horseOppPicker"

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.72),
                               size: CGSize(width: W, height: H))
        container.addChild(dim)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "CHOOSE OPPONENT"
        title.fontSize = min(16, W / 18)
        title.fontColor = gold
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: H * 0.22)
        container.addChild(title)

        let cardW = min(W * 0.40, 160)
        let cardH = min(H * 0.36, 230)
        let gap   = min(W * 0.06, 28)

        let tommy = makeOpponentCard(title: "TOMMY", subtitle: "STEADY +1",
                                     desc: "BIG-HOLE ACE",
                                     name: "horseOpp_tommy",
                                     accent: SKColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1),
                                     size: CGSize(width: cardW, height: cardH))
        tommy.position = CGPoint(x: -(cardW / 2 + gap / 2), y: -H * 0.02)
        container.addChild(tommy)

        let jen = makeOpponentCard(title: "JEN", subtitle: "MID +2 SHARP",
                                   desc: "RISKY 2-PT GUN",
                                   name: "horseOpp_jen",
                                   accent: SKColor(red: 0.85, green: 0.35, blue: 0.55, alpha: 1),
                                   size: CGSize(width: cardW, height: cardH))
        jen.position = CGPoint(x: (cardW / 2 + gap / 2), y: -H * 0.02)
        container.addChild(jen)

        addChild(container)
        opponentPickerNode = container
    }

    private func makeOpponentCard(title: String, subtitle: String, desc: String,
                                  name: String, accent: SKColor, size cardSize: CGSize) -> SKNode {
        let gold = SKColor(red: 0xf0/255.0, green: 0xc0/255.0, blue: 0x60/255.0, alpha: 1)
        let wood = SKColor(red: 0x1a/255.0, green: 0x0a/255.0, blue: 0x04/255.0, alpha: 1)

        let card = SKSpriteNode(color: wood, size: cardSize)
        card.name = name

        let border = SKShapeNode(rectOf: cardSize)
        border.strokeColor = gold; border.fillColor = .clear; border.lineWidth = 2
        border.name = name
        card.addChild(border)

        let titleLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        titleLabel.text = title
        titleLabel.fontSize = min(16, cardSize.width / 6)
        titleLabel.fontColor = accent
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: cardSize.height * 0.28)
        titleLabel.name = name
        card.addChild(titleLabel)

        let subLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        subLabel.text = subtitle
        subLabel.fontSize = min(8, cardSize.width / 13)
        subLabel.fontColor = gold
        subLabel.verticalAlignmentMode = .center
        subLabel.position = .zero
        subLabel.name = name
        card.addChild(subLabel)

        let descLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        descLabel.text = desc
        descLabel.fontSize = min(7, cardSize.width / 15)
        descLabel.fontColor = SKColor(white: 0.75, alpha: 1)
        descLabel.verticalAlignmentMode = .center
        descLabel.position = CGPoint(x: 0, y: -cardSize.height * 0.22)
        descLabel.name = name
        card.addChild(descLabel)

        return card
    }

    private func selectOpponent(_ opp: Opponent) {
        guard awaitingOpponentChoice else { return }
        selectedOpponent = opp
        awaitingOpponentChoice = false
        opponentPickerNode?.removeFromParent()
        opponentPickerNode = nil
        updateScoreLabel()

        if TutorialManager.shared.hasSeen(TutorialManager.horseRace) {
            startCountdown()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    // MARK: - Tutorial

    private func presentTutorial(autoTriggered: Bool) {
        tutorialUp = true
        let steps: [TutorialStep] = [
            .card(title: "HORSE RACE",
                  body:  "RACE YOUR RED HORSE TO THE FINISH. FIRST TO 12 SPACES WINS."),
            .card(title: "PICK YOUR HOLE",
                  body:  "BIG CLOSE HOLE = +1 SPACE.  MIDDLE = +2.  SMALL FAR HOLE = +3."),
            .card(title: "SWIPE THE RED BAG",
                  body:  "SWIPE UP FROM THE MOVING RED BAG TO THROW. AS SOON AS IT LANDS YOU CAN THROW AGAIN — SO CAN BLUE."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self = self else { return }
            self.tutorialUp = false
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.horseRace)
                self.startCountdown()
            }
        }
        addChild(overlay)
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownActive = true
        let gold  = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        let green = SKColor(red: 0.18, green: 0.90, blue: 0.40, alpha: 1)

        func beatLabel(text: String, color: SKColor) -> SKAction {
            return .run { [weak self] in
                guard let self else { return }
                let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
                lbl.text = text
                lbl.fontSize = min(64, self.size.width / 5)
                lbl.fontColor = color
                lbl.horizontalAlignmentMode = .center
                lbl.verticalAlignmentMode   = .center
                lbl.position  = .zero
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
            beatLabel(text: "3",     color: gold),
            .wait(forDuration: beat),
            beatLabel(text: "2",     color: gold),
            .wait(forDuration: beat),
            beatLabel(text: "1",     color: gold),
            .wait(forDuration: beat),
            beatLabel(text: "THROW!", color: green),
            .wait(forDuration: 0.55),
            .run { [weak self] in
                guard let self else { return }
                self.countdownActive = false
                self.turnIndicator?.isHidden = false
                // Reset the AI wind-up so it doesn't fire instantly when the
                // countdown clears.
                self.aiReadyTime = self.currentSceneTime + 0.3
            },
        ]))
    }

    private func preloadAssets() {
        let tex = SKTexture(imageNamed: "bag_16bit")
        tex.filteringMode = .nearest
        SKTexture.preload([tex]) { }
    }

    // MARK: - Layout

    private func computeLayout() {
        let W = size.width, H = size.height
        boardHalfW = W * 0.30
        boardHalfH = boardHalfW * 1.50
        boardY     = -H * 0.05
        throwLineY = -H * 0.42

        // Hole arrangement on the board's central axis. The board is rendered as
        // a top-down rectangle: lower-Y = closer to the player, higher-Y = farther.
        let bottomY = boardY - boardHalfH * 0.55   // closest → large
        let midY    = boardY                       // medium
        let topY    = boardY + boardHalfH * 0.55   // farthest → small
        holes = [
            Hole(center: CGPoint(x: 0, y: bottomY),
                 radius: boardHalfW * 0.32, spaces: 1),
            Hole(center: CGPoint(x: 0, y: midY),
                 radius: boardHalfW * 0.20, spaces: 2),
            Hole(center: CGPoint(x: 0, y: topY),
                 radius: boardHalfW * 0.12, spaces: 3),
        ]

        // Calibrate powerScale so a "natural" swipe lands near the medium hole.
        let distToMid    = abs(holes[1].center.y - throwLineY)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame   // ≈ 60
        let idealSwipe   = H * 0.34
        powerScale = distToMid / (flightFrames * idealSwipe)

        // Throw-line indicator oscillation
        targetRange = boardHalfW * 1.30
        targetSpeed = W * 0.65

        // Race lane sits just below the top ribbon
        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let ribbonBottomY = H / 2 - topInset - 48 - 2
        raceLeftX  = -W * 0.42
        raceRightX =  W * 0.42
        raceRedY   = ribbonBottomY - 26
        raceBlueY  = ribbonBottomY - 58
    }

    // MARK: - World

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

        // Throw line
        let throwLine = SKSpriteNode(
            color: SKColor(white: 1.0, alpha: 0.55),
            size: CGSize(width: boardHalfW * 1.6, height: 1))
        throwLine.position  = CGPoint(x: 0, y: throwLineY)
        throwLine.zPosition = -1
        gameWorldNode.addChild(throwLine)
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
                    tuft.position  = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                    tuft.zPosition = -199
                    gameWorldNode.addChild(tuft)
                }
                y += tileSize
            }
            x += tileSize
        }
    }

    // MARK: - Board

    private func setupBoard() {
        let container = SKNode()
        container.position  = CGPoint(x: 0, y: boardY)
        container.zPosition = 5
        gameWorldNode.addChild(container)

        let bw = boardHalfW * 2
        let bh = boardHalfH * 2

        // Drop shadow
        let shadowNode = SKSpriteNode(color: .black,
                                      size: CGSize(width: bw + 6, height: bh + 6))
        shadowNode.alpha    = 0.45
        shadowNode.position = CGPoint(x: 4, y: -6)
        shadowNode.zPosition = -1
        container.addChild(shadowNode)

        // Procedural wood board (avoids the baked single-hole texture)
        let surface = SKSpriteNode(texture: makeWoodBoardTexture(size: CGSize(width: bw, height: bh)),
                                   size: CGSize(width: bw, height: bh))
        surface.zPosition = 0
        container.addChild(surface)

        // Three holes + a "+N" label under each so the value reads at a glance.
        for hole in holes {
            let relY = hole.center.y - boardY
            let tex  = makePixelCircleTexture(
                radius:    hole.radius,
                fill:      UIColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 1),
                border:    UIColor(red: 0.25, green: 0.13, blue: 0.04, alpha: 1),
                pixelSize: 3)
            let holeNode = SKSpriteNode(texture: tex,
                                        size: CGSize(width: hole.radius * 2,
                                                     height: hole.radius * 2))
            holeNode.position  = CGPoint(x: hole.center.x, y: relY)
            holeNode.zPosition = 2
            container.addChild(holeNode)

            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text                    = "+\(hole.spaces)"
            lbl.fontSize                = 7
            lbl.fontColor               = SKColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 0.95)
            lbl.verticalAlignmentMode   = .center
            lbl.horizontalAlignmentMode = .center
            lbl.position  = CGPoint(x: hole.center.x + hole.radius + 12, y: relY)
            lbl.zPosition = 3
            container.addChild(lbl)
        }
    }

    private func makeWoodBoardTexture(size sz: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: sz, format: fmt).image { ctx in
            let c = ctx.cgContext
            // Base wood
            c.setFillColor(UIColor(red: 0.52, green: 0.33, blue: 0.18, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: sz))

            // Plank stripes
            c.setFillColor(UIColor(red: 0.42, green: 0.25, blue: 0.12, alpha: 1).cgColor)
            var y: CGFloat = 0
            while y < sz.height {
                c.fill(CGRect(x: 0, y: y, width: sz.width, height: 1))
                y += 14
            }

            // Random grain knots
            c.setFillColor(UIColor(red: 0.33, green: 0.18, blue: 0.07, alpha: 0.6).cgColor)
            for _ in 0..<22 {
                let kx = CGFloat.random(in: 0...sz.width)
                let ky = CGFloat.random(in: 0...sz.height)
                let kr = CGFloat.random(in: 1...3)
                c.fillEllipse(in: CGRect(x: kx - kr, y: ky - kr, width: kr * 2, height: kr * 2))
            }

            // Inner dark border
            c.setStrokeColor(UIColor(red: 0.20, green: 0.10, blue: 0.04, alpha: 1).cgColor)
            c.setLineWidth(3)
            c.stroke(CGRect(x: 1.5, y: 1.5, width: sz.width - 3, height: sz.height - 3))

            // Top edge highlight for a slight bevel
            c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
            c.fill(CGRect(x: 3, y: 3, width: sz.width - 6, height: 2))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makePixelCircleTexture(radius: CGFloat,
                                        fill: UIColor,
                                        border: UIColor,
                                        pixelSize: Int) -> SKTexture {
        let ps    = CGFloat(pixelSize)
        let cells = Int(ceil(radius * 2 / ps)) + 2
        let imgPx = cells * pixelSize
        let sz    = CGSize(width: CGFloat(imgPx), height: CGFloat(imgPx))
        let cx    = CGFloat(cells) / 2.0
        let cy    = CGFloat(cells) / 2.0
        let r     = radius / ps

        UIGraphicsBeginImageContextWithOptions(sz, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let c = UIGraphicsGetCurrentContext() else { return SKTexture() }
        for row in 0..<cells {
            for col in 0..<cells {
                let dx   = CGFloat(col) + 0.5 - cx
                let dy   = CGFloat(row) + 0.5 - cy
                let dist = sqrt(dx * dx + dy * dy)
                let rect = CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps,
                                  width: ps, height: ps)
                if dist <= r - 0.7 {
                    c.setFillColor(fill.cgColor);   c.fill(rect)
                } else if dist <= r + 0.3 {
                    c.setFillColor(border.cgColor); c.fill(rect)
                }
            }
        }
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - Race lane

    private func setupRaceLane() {
        // Backing strip behind both lanes
        let stripH: CGFloat = 70
        let stripCenterY = (raceRedY + raceBlueY) / 2
        let strip = SKSpriteNode(
            color: SKColor(red: 0.40, green: 0.28, blue: 0.16, alpha: 1),
            size: CGSize(width: size.width * 0.94, height: stripH))
        strip.position  = CGPoint(x: 0, y: stripCenterY)
        strip.zPosition = 480
        addChild(strip)

        // Mid-lane divider
        let divider = SKSpriteNode(
            color: SKColor(white: 0.0, alpha: 0.30),
            size: CGSize(width: size.width * 0.94, height: 1))
        divider.position  = CGPoint(x: 0, y: stripCenterY)
        divider.zPosition = 482
        addChild(divider)

        // Position tick marks (12 spaces ⇒ 13 ticks 0..12).
        for i in 0...totalSpaces {
            let frac  = CGFloat(i) / CGFloat(totalSpaces)
            let x = raceLeftX + (raceRightX - raceLeftX) * frac
            let isFinish = (i == totalSpaces)
            let tick = SKSpriteNode(
                color: isFinish
                    ? SKColor(red: 1.0, green: 0.95, blue: 0.55, alpha: 0.90)
                    : SKColor(white: 1.0, alpha: 0.18),
                size: CGSize(width: isFinish ? 2 : 1, height: stripH - 8))
            tick.position  = CGPoint(x: x, y: stripCenterY)
            tick.zPosition = 481
            addChild(tick)
        }

        // FINISH label above the right edge
        let finish = SKLabelNode(fontNamed: "PressStart2P-Regular")
        finish.text                    = "FINISH"
        finish.fontSize                = 5
        finish.fontColor               = SKColor(red: 1.0, green: 0.95, blue: 0.55, alpha: 1)
        finish.verticalAlignmentMode   = .bottom
        finish.horizontalAlignmentMode = .center
        finish.position  = CGPoint(x: raceRightX, y: stripCenterY + stripH / 2 + 2)
        finish.zPosition = 483
        addChild(finish)

        // Horses
        let redTex  = makeHorseTexture(
            color: UIColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1))
        let blueTex = makeHorseTexture(
            color: UIColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1))

        let horseW: CGFloat = 30, horseH: CGFloat = 20
        let red = SKSpriteNode(texture: redTex, size: CGSize(width: horseW, height: horseH))
        red.position  = CGPoint(x: raceLeftX, y: raceRedY)
        red.zPosition = 490
        addChild(red); redHorse = red

        let blue = SKSpriteNode(texture: blueTex, size: CGSize(width: horseW, height: horseH))
        blue.position  = CGPoint(x: raceLeftX, y: raceBlueY)
        blue.zPosition = 490
        addChild(blue); blueHorse = blue
    }

    /// 16-bit-ish horse silhouette rendered into a small texture.
    /// The shape is a right-facing pixel horse — body, head, neck, legs, tail.
    private func makeHorseTexture(color: UIColor) -> SKTexture {
        let sz = CGSize(width: 30, height: 20)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: sz, format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(color.cgColor)
            // Body (chunky rect)
            c.fill(CGRect(x: 4,  y: 6, width: 18, height: 8))
            // Neck
            c.fill(CGRect(x: 19, y: 4, width: 3, height: 6))
            // Head
            c.fill(CGRect(x: 21, y: 3, width: 6, height: 5))
            // Snout
            c.fill(CGRect(x: 26, y: 5, width: 2, height: 3))
            // Ear
            c.fill(CGRect(x: 22, y: 1, width: 2, height: 2))
            // Tail
            c.fill(CGRect(x: 1,  y: 6, width: 3, height: 4))
            // Legs
            c.fill(CGRect(x: 5,  y: 13, width: 3, height: 6))
            c.fill(CGRect(x: 10, y: 13, width: 3, height: 6))
            c.fill(CGRect(x: 15, y: 13, width: 3, height: 6))
            c.fill(CGRect(x: 19, y: 13, width: 3, height: 6))
            // Eye + mane highlight
            c.setFillColor(UIColor.black.cgColor)
            c.fill(CGRect(x: 24, y: 4, width: 1, height: 1))
            c.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            c.fill(CGRect(x: 17, y: 4, width: 3, height: 2))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func horseX(forSpaces spaces: Int) -> CGFloat {
        let frac = CGFloat(min(spaces, totalSpaces)) / CGFloat(totalSpaces)
        return raceLeftX + (raceRightX - raceLeftX) * frac
    }

    private func advance(owner: BagOwner, spaces: Int) {
        if owner == .player {
            playerSpaces = min(totalSpaces, playerSpaces + spaces)
            animateHorse(redHorse, toX: horseX(forSpaces: playerSpaces))
        } else {
            aiSpaces = min(totalSpaces, aiSpaces + spaces)
            animateHorse(blueHorse, toX: horseX(forSpaces: aiSpaces))
        }
        updateScoreLabel()

        if playerSpaces >= totalSpaces || aiSpaces >= totalSpaces {
            triggerGameOver(playerWon: playerSpaces >= totalSpaces)
        }
    }

    private func animateHorse(_ horse: SKSpriteNode?, toX targetX: CGFloat) {
        guard let h = horse else { return }
        h.removeAction(forKey: "trot")
        // Bobbing trot during the slide
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3, duration: 0.08),
            SKAction.moveBy(x: 0, y: -3, duration: 0.08),
        ])
        h.run(SKAction.repeatForever(bob), withKey: "trot")
        h.run(SKAction.sequence([
            SKAction.moveTo(x: targetX, duration: 0.50),
            SKAction.run { [weak h] in h?.removeAction(forKey: "trot") },
        ]))
    }

    // MARK: - UI / HUD

    private func setupUI() {
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1)
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
        let dsIronGray = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1)

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY   = size.height / 2 - totalTopH / 2

        let topBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: size.width, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: topBarY)
        topBar.zPosition = 500
        addChild(topBar)

        let topBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: size.width, height: 2))
        topBorder.position  = CGPoint(x: 0, y: topBarY - topH / 2 - topInset / 2)
        // Place border at the bottom edge of the ribbon (below the visible 48pt area).
        topBorder.position.y = size.height / 2 - topInset - topH + 1
        topBorder.zPosition = 501
        addChild(topBorder)

        let contentY = size.height / 2 - topInset - topH / 2

        // Zone A: pause icon
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size      = CGSize(width: 22, height: 22)
        pauseBtn.position  = CGPoint(x: -size.width / 2 + 22, y: contentY)
        pauseBtn.zPosition = 502
        pauseBtn.name      = "pauseBtn"
        addChild(pauseBtn)

        // Tutorial help button just right of pause
        let help = TutorialHelpButton.make()
        help.position  = CGPoint(x: -size.width / 2 + 52, y: contentY)
        help.zPosition = 502
        addChild(help)

        // Zone B: score
        let label = SKLabelNode(fontNamed: "PressStart2P-Regular")
        label.text                    = "RED 0  |  TOMMY 0"
        label.fontSize                = 10
        label.fontColor               = dsGold
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        label.position  = CGPoint(x: 0, y: contentY)
        label.zPosition = 502
        addChild(label)
        scoreLabel = label

        // Zone C: close
        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: size.width / 2 - 22, y: contentY)
        closeBtn.zPosition = 502
        closeBtn.name      = "closeButton"
        addChild(closeBtn)

        // Throw-line indicator: red bag oscillating left-right on the throw line.
        let indTex = SKTexture(imageNamed: "bag_16bit")
        indTex.filteringMode = .nearest
        let indicator = SKSpriteNode(texture: indTex, size: CGSize(width: 50, height: 50))
        indicator.color            = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        indicator.colorBlendFactor = 0.65
        indicator.position  = CGPoint(x: 0, y: throwLineY)
        indicator.zPosition = 30
        gameWorldNode.addChild(indicator)
        indicator.run(SKAction.repeatForever(.sequence([
            .scale(to: 1.18, duration: 0.55),
            .scale(to: 1.00, duration: 0.55),
        ])))
        turnIndicator = indicator

        // Iron corner bolts
        let ribbonTopY = size.height / 2 - topInset - 5
        let ribbonBotY = size.height / 2 - topInset - topH + 5
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: ribbonTopY), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: ribbonTopY), color: dsIronGray)
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: ribbonBotY), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: ribbonBotY), color: dsIronGray)
    }

    private func addIronBolt(at pt: CGPoint, color: SKColor) {
        let bolt = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
        bolt.position  = pt
        bolt.zPosition = 503
        addChild(bolt)
    }

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
        let overlay = SKSpriteNode(texture: SKTexture(image: img),
                                   size: CGSize(width: w, height: h))
        overlay.position  = .zero
        overlay.zPosition = 800
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    private func updateScoreLabel() {
        scoreLabel?.text = "RED \(playerSpaces)  |  \(opponentName) \(aiSpaces)"
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        currentSceneTime = currentTime
        // First update: seed AI's wind-up window so it doesn't fire instantly.
        if aiReadyTime == 0 { aiReadyTime = currentTime + 1.4 }

        guard !isPausedGame, !isGameOver, !tutorialUp, !countdownActive,
              !awaitingOpponentChoice else { return }
        let dt: CGFloat = 1.0 / 60.0

        // Oscillate the throw-line indicator whenever the player can throw.
        let playerCooldown = (lastPlayerBag != nil)
                          && !(lastPlayerBag!.isGrounded || lastPlayerBag!.hasScored)
        if let ind = turnIndicator {
            if playerCooldown {
                ind.isHidden = true
            } else {
                ind.isHidden = false
                updateTargetOscillation(dt: dt)
                ind.position.x = targetX
            }
        }

        for bag in activeBags {
            guard !bag.isGrounded || bag.isMoving else { continue }
            updateBagPhysics(bag, dt: dt)
        }

        resolveBagCollisions()

        // AI throw: whenever its previous bag has touched down and the
        // wind-up timer has elapsed.
        let aiCanThrow = (lastAIBag == nil || lastAIBag!.isGrounded || lastAIBag!.hasScored)
                       && currentTime >= aiReadyTime
        if aiCanThrow { performAIThrow() }
    }

    private func updateBagPhysics(_ bag: RaceBag, dt: CGFloat) {
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
                if !bag.hasLanded {
                    bag.hasLanded = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                }
                // Small bounce, then slide.
                if abs(bag.vz) > 0.5 {
                    bag.vz = abs(bag.vz) * 0.18
                } else {
                    bag.vz = 0
                    bag.isGrounded = true
                }
                bag.vx *= 0.92
                bag.vy *= 0.92
                bag.rotV *= 0.65

                // Score the first hole this bag falls into.
                if !bag.hasScored {
                    for hole in holes {
                        let d = hypot(bag.bx - hole.center.x, bag.by - hole.center.y)
                        if d <= hole.radius {
                            bag.hasScored = true
                            bag.isGrounded = true
                            bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            run(SKAction.playSoundFileNamed("hole_score.wav", waitForCompletion: false))
                            showHoleEffect(at: CGPoint(x: bag.bx, y: bag.by),
                                           color: bag.owner == .player
                                                ? SKColor(red: 1.0, green: 0.7, blue: 0.6, alpha: 1)
                                                : SKColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1))
                            // Sink the bag visually
                            bag.node.run(SKAction.sequence([
                                SKAction.group([
                                    SKAction.scale(to: 0.3, duration: 0.20),
                                    SKAction.fadeOut(withDuration: 0.20),
                                ]),
                                SKAction.hide(),
                            ]))
                            bag.shadow.run(SKAction.fadeOut(withDuration: 0.15))
                            if !bag.hasAwardedSpaces {
                                bag.hasAwardedSpaces = true
                                advance(owner: bag.owner, spaces: hole.spaces)
                            }
                            break
                        }
                    }
                }
            } else {
                // Lands off-board — dead stop and shrink for depth cue.
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

        // Friction stop on board surface
        if bag.isGrounded && abs(bag.vx) < 0.04 && abs(bag.vy) < 0.04 {
            bag.vx = 0; bag.vy = 0
        }

        // Render
        let visualY = bag.by + bag.bz * 0.50
        bag.node.position   = CGPoint(x: bag.bx, y: visualY)
        bag.shadow.position = CGPoint(x: bag.bx + bag.bz * 0.08, y: bag.by)

        let heightScale = 1.0 + bag.bz * 0.012
        bag.node.setScale(bag.baseScale * heightScale)
        bag.shadow.alpha = max(0.08, 0.35 - bag.bz * 0.005)
        bag.shadow.setScale(max(0.5, 1.0 - bag.bz * 0.005))
        bag.node.zPosition = 20 + bag.bz * 0.1 - bag.by * 0.02
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
    }

    private func checkIsOnBoard(_ bag: RaceBag) -> Bool {
        abs(bag.bx) <= boardHalfW * 0.95 &&
        bag.by >= boardY - boardHalfH * 0.95 &&
        bag.by <= boardY + boardHalfH * 0.95
    }

    // Elastic collision between bags so they can knock each other around.
    private func resolveBagCollisions() {
        let bagRadius:   CGFloat = 22
        let minDist:     CGFloat = bagRadius * 2
        let restitution: CGFloat = 0.68

        for i in 0..<activeBags.count {
            for j in (i + 1)..<activeBags.count {
                let a = activeBags[i]
                let b = activeBags[j]
                guard !a.hasScored && !b.hasScored else { continue }
                guard !a.hasAppliedGroundScale && !b.hasAppliedGroundScale else { continue }
                guard abs(a.bz - b.bz) < bagRadius else { continue }

                let dx = b.bx - a.bx
                let dy = b.by - a.by
                let distSq = dx * dx + dy * dy
                guard distSq < minDist * minDist, distSq > 0.01 else { continue }

                let dist = sqrt(distSq)
                let nx = dx / dist
                let ny = dy / dist

                let dvx = b.vx - a.vx
                let dvy = b.vy - a.vy
                let relVel = dvx * nx + dvy * ny
                guard relVel < 0 else { continue }

                let impulse = -(1.0 + restitution) * relVel * 0.5
                a.vx -= impulse * nx;  a.vy -= impulse * ny
                b.vx += impulse * nx;  b.vy += impulse * ny

                a.isGrounded = false
                b.isGrounded = false

                let correction = (minDist - dist) * 0.5
                a.bx -= nx * correction;  a.by -= ny * correction
                b.bx += nx * correction;  b.by += ny * correction
            }
        }
    }

    private func showHoleEffect(at pos: CGPoint, color: SKColor) {
        let flash = SKSpriteNode(color: color,
                                 size: CGSize(width: 24, height: 24))
        flash.position  = pos
        flash.zPosition = 50
        gameWorldNode.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.2, duration: 0.20),
                SKAction.fadeOut(withDuration: 0.30),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Throwing

    private func throwPlayerBag(startX: CGFloat, vx: CGFloat, vy: CGFloat) {
        let bag = RaceBag(owner: .player, startX: startX, startY: throwLineY)
        bag.vx = vx; bag.vy = vy; bag.vz = vzInitial
        let speed = sqrt(vx * vx + vy * vy)
        bag.rotV = (Bool.random() ? 1.0 : -1.0) * (0.04 + speed * 0.015)
        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)
        lastPlayerBag = bag
    }

    private func performAIThrow() {
        // Per-opponent hole-preference + accuracy profile.
        //   probLarge / probMedium / (1 - those) = how often they aim at each hole.
        //   accLarge / accMed / accSmall         = noise multiplier on hole.radius
        //                                          (lower = tighter aim = more accurate).
        let probLarge: Double, probMed: Double
        let accLarge: CGFloat, accMed: CGFloat, accSmall: CGFloat
        switch selectedOpponent {
        case .tommy:
            // Big-hole specialist: aims at +1 most of the time and lands it consistently.
            probLarge = 0.70; probMed = 0.20
            accLarge  = 0.95; accMed  = 1.55; accSmall = 1.85
        case .jen:
            // Mid-hole specialist: aims at +2 most of the time and lands it consistently.
            probLarge = 0.22; probMed = 0.60
            accLarge  = 1.55; accMed  = 0.95; accSmall = 1.70
        }

        // Catch-up: when meaningfully behind, occasionally take the next-up shot.
        let diff = playerSpaces - aiSpaces
        let catchUp = diff >= 5 && Double.random(in: 0..<1) < 0.40

        let hole: Hole
        let accMul: CGFloat
        if catchUp {
            // Reach for higher-value holes when chasing.
            if Double.random(in: 0..<1) < 0.65 {
                hole = holes[2]; accMul = accSmall
            } else {
                hole = holes[1]; accMul = accMed
            }
        } else {
            let roll = Double.random(in: 0..<1)
            if roll < probLarge {
                hole = holes[0]; accMul = accLarge
            } else if roll < probLarge + probMed {
                hole = holes[1]; accMul = accMed
            } else {
                hole = holes[2]; accMul = accSmall
            }
        }

        let noise = hole.radius * accMul
        let aimX = hole.center.x + CGFloat.random(in: -noise...noise)
        let aimY = hole.center.y + CGFloat.random(in: -noise * 0.6...noise * 0.6)

        let startX = CGFloat.random(in: -boardHalfW * 0.6...boardHalfW * 0.6)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame
        let vx = (aimX - startX) / flightFrames
        let vy = (aimY - throwLineY) / flightFrames

        let bag = RaceBag(owner: .ai, startX: startX, startY: throwLineY)
        bag.vx = vx; bag.vy = vy; bag.vz = vzInitial
        let speed = sqrt(vx * vx + vy * vy)
        bag.rotV = (Bool.random() ? 1.0 : -1.0) * (0.04 + speed * 0.015)
        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)
        lastAIBag = bag

        // Brief wind-up before the AI is allowed to throw again — keeps the pace
        // human-feeling rather than spamming the second the bag touches down.
        aiReadyTime = currentSceneTime + Double.random(in: 0.55...1.05)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Opponent picker consumes input until a card is chosen.
        if awaitingOpponentChoice {
            for n in nodes(at: loc) {
                var cur: SKNode? = n
                while let c = cur {
                    if c.name == "horseOpp_tommy" { selectOpponent(.tommy); return }
                    if c.name == "horseOpp_jen"   { selectOpponent(.jen);   return }
                    cur = c.parent
                }
            }
            return
        }

        // Tutorial overlay consumes all input — any tap advances it.
        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        // HUD help button re-presents the tutorial without resetting the game.
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        if isPausedGame {
            for n in nodes(at: loc) where n.name == "resumeBtn" {
                resumeGame(); return
            }
            return
        }
        if nodes(at: loc).contains(where: { $0.name == "pauseBtn" }) {
            pauseGame(); return
        }
        if confirmingQuit { handleButtonTap(at: loc); return }

        if isGameOver {
            handleButtonTap(at: loc); return
        }

        // Block throws during countdown / tutorial.
        if countdownActive || tutorialUp { return }

        // Swallow touches on HUD chrome so a throw can't begin there.
        if handleButtonTap(at: loc) { return }

        // Cooldown: only one in-flight player bag at a time.
        if let last = lastPlayerBag, !last.isGrounded, !last.hasScored {
            return
        }

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

        if isGameOver || isPausedGame || confirmingQuit {
            handleButtonTap(at: end)
            touchStart = nil
            return
        }

        if handleButtonTap(at: end) { touchStart = nil; return }

        if countdownActive || tutorialUp { touchStart = nil; return }

        guard let start = touchStart else { return }
        touchStart = nil

        // Minimum swipe length so an accidental tap doesn't drop a dud bag right at the line.
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) > 14 else { return }

        // Cooldown re-check (in case state changed between touchesBegan and touchesEnded).
        if let last = lastPlayerBag, !last.isGrounded, !last.hasScored { return }

        // Bag launches from wherever the oscillating indicator was at release —
        // identical mechanic to the cornhole mini-game.
        let launchX = turnIndicator?.position.x ?? 0
        throwPlayerBag(startX: launchX, vx: dx * powerScale, vy: dy * powerScale)
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
                case "playAgainBtn":
                    resetForReplay()
                    return true
                case "exitBtn":
                    dismissScene(playerWon: playerSpaces > aiSpaces)
                    return true
                default:
                    n = current.parent
                }
            }
        }
        return false
    }

    // MARK: - Game over

    private func triggerGameOver(playerWon: Bool) {
        guard !isGameOver else { return }
        isGameOver = true
        run(SKAction.playSoundFileNamed(playerWon ? "game_win.wav" : "game_lose.wav",
                                        waitForCompletion: false))
        run(SKAction.wait(forDuration: 0.6)) { [weak self] in
            self?.showGameOverPanel(playerWon: playerWon)
        }
    }

    private func showGameOverPanel(playerWon: Bool) {
        messageNode?.removeFromParent()
        let panel = GameResultModal.make(
            sceneSize: size,
            won: playerWon,
            title: playerWon ? "VICTORY!" : "DEFEAT",
            subtitle: "RED \(playerSpaces)  -  \(aiSpaces) \(opponentName)",
            detail: "FIRST TO \(totalSpaces)",
            hint: nil,
            rewards: [],
            buttons: [GameResultModal.Button(label: "PLAY AGAIN", name: "playAgainBtn", style: .primary),
                      GameResultModal.Button(label: "EXIT",       name: "exitBtn",      style: .danger)])
        addChild(panel)
        messageNode = panel
    }

    private func resetForReplay() {
        messageNode?.removeFromParent()
        messageNode = nil

        for bag in activeBags {
            bag.node.removeFromParent()
            bag.shadow.removeFromParent()
        }
        activeBags.removeAll()
        lastPlayerBag = nil
        lastAIBag     = nil
        playerSpaces  = 0
        aiSpaces      = 0
        isGameOver    = false

        redHorse?.position.x  = raceLeftX
        blueHorse?.position.x = raceLeftX
        updateScoreLabel()

        // Replay always re-runs the 3-2-1 countdown.
        turnIndicator?.isHidden = true
        aiReadyTime = 0
        startCountdown()
    }

    // MARK: - Pause

    private func pauseGame() {
        guard !isPausedGame, !isGameOver else { return }
        isPausedGame = true
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
        // Give the AI a brief moment so it doesn't fire instantly on resume.
        aiReadyTime = max(aiReadyTime, currentSceneTime + 0.6)
    }

    private func showPauseOverlay() {
        let W = size.width, H = size.height
        let ov = SKNode(); ov.zPosition = 5000
        pauseOverlayNode = ov; addChild(ov)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2, width: W, height: H))
        dim.fillColor = SKColor(white: 0, alpha: 0.65); dim.strokeColor = .clear
        ov.addChild(dim)

        let panelW: CGFloat = min(W - 48, 280), panelH: CGFloat = 160
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2,
                                             width: panelW, height: panelH),
                                cornerRadius: 10)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        panel.lineWidth   = 2
        ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 40)
        ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2,
                                                width: btnW, height: btnH),
                                   cornerRadius: 8)
        resumeBg.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
        resumeBg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        resumeBg.lineWidth   = 1.5
        resumeBg.position = CGPoint(x: 0, y: -16)
        resumeBg.name = "resumeBtn"
        ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text = "RESUME"; resumeLbl.fontSize = 11
        resumeLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        resumeLbl.horizontalAlignmentMode = .center; resumeLbl.verticalAlignmentMode = .center
        resumeLbl.position = CGPoint(x: 0, y: -1)
        resumeLbl.name = "resumeBtn"
        resumeBg.addChild(resumeLbl)
    }

    // MARK: - Quit confirm

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true

        let W = size.width
        let panelW: CGFloat = min(W - 48, 260), panelH: CGFloat = 150
        let panel = SKNode(); panel.zPosition = 4500
        confirmPanel = panel; addChild(panel)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -size.height / 2,
                                           width: W, height: size.height))
        dim.fillColor = SKColor(white: 0, alpha: 0.60); dim.strokeColor = .clear
        panel.addChild(dim)

        let body = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2,
                                            width: panelW, height: panelH),
                               cornerRadius: 8)
        body.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        body.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        body.lineWidth   = 2
        panel.addChild(body)

        let q = SKLabelNode(fontNamed: "PressStart2P-Regular")
        q.text = "QUIT THE RACE?"; q.fontSize = 10
        q.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        q.horizontalAlignmentMode = .center; q.verticalAlignmentMode = .center
        q.position = CGPoint(x: 0, y: 32)
        panel.addChild(q)

        let bw: CGFloat = 90, bh: CGFloat = 36

        let quit = SKShapeNode(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh),
                               cornerRadius: 6)
        quit.fillColor   = SKColor(red: 0.65, green: 0.18, blue: 0.18, alpha: 0.95)
        quit.strokeColor = SKColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1)
        quit.lineWidth   = 1.5
        quit.position    = CGPoint(x: -52, y: -22)
        quit.name        = "confirmQuitBtn"
        panel.addChild(quit)
        let qLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        qLbl.text = "QUIT"; qLbl.fontSize = 9; qLbl.fontColor = .white
        qLbl.horizontalAlignmentMode = .center; qLbl.verticalAlignmentMode = .center
        qLbl.name = "confirmQuitBtn"
        quit.addChild(qLbl)

        let cancel = SKShapeNode(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh),
                                 cornerRadius: 6)
        cancel.fillColor   = SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.95)
        cancel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        cancel.lineWidth   = 1.5
        cancel.position    = CGPoint(x: 52, y: -22)
        cancel.name        = "cancelQuitBtn"
        panel.addChild(cancel)
        let cLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        cLbl.text = "STAY"; cLbl.fontSize = 9
        cLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        cLbl.horizontalAlignmentMode = .center; cLbl.verticalAlignmentMode = .center
        cLbl.name = "cancelQuitBtn"
        cancel.addChild(cLbl)
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.removeFromParent()
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        SceneTransition.iris(in: view, to: prev)
    }
}
