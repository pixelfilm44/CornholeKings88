
import SpriteKit
import UIKit

// MARK: - WellFlingerScene
// "Well Flinger" — fling a beanbag into a brick well, steer through the shaft,
// and land it on the cornhole board at the bottom.
//
// States: launch → zoomIn → descent → landing → sinking → gameOver
// Scoring: 3 pts hole-in-one, 1 pt on board, 0 pts miss. 5 bags per round.
// Ported from the HTML5 "Well Flinger" canvas game.

final class WellFlingerScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Physics categories
    private static let bagCategory:    UInt32 = 1 << 0
    private static let boardCategory:  UInt32 = 1 << 1
    private static let holeCategory:   UInt32 = 1 << 2   // sensor inside the hole opening
    private static let groundCategory: UInt32 = 1 << 3   // sensor below board / off to the sides

    /// True while the bag is under SKPhysics control (approach phase onward).
    /// Manual position updates in updateBagVisual are skipped while this is on.
    private var physicsActive = false
    /// One-shot flag so contact callbacks score only once per bag.
    private var hasScored = false


    // MARK: - Public contract (standard mini-game pattern)
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?

    // MARK: - Layout
    private var W: CGFloat = 0
    private var H: CGFloat = 0

    // Convert virtual 320×480 (top-left origin, y-down) → SpriteKit (center origin, y-up)
    private func vs(_ vx: CGFloat, _ vy: CGFloat) -> CGPoint {
        CGPoint(x: (vx / 320 - 0.5) * W, y: (0.5 - vy / 480) * H)
    }
    private func vw(_ d: CGFloat) -> CGFloat { d / 320 * W }
    private func vh(_ d: CGFloat) -> CGFloat { d / 480 * H }

    // MARK: - Game phase
    private enum Phase { case launch, zoomIn, descent, landing, sinking, gameOver }
    private var phase: Phase = .launch

    // MARK: - Score state
    private var score        = 0
    private var bagsLeft     = 5
    private var highScore    = UserDefaults.standard.integer(forKey: "wellFlinger_high_v1")
    private var accurateHits = 0
    private var totalFlings  = 0

    // MARK: - Bag (virtual coords)
    private var bVX:  CGFloat = 160   // x  0–320
    private var bVY:  CGFloat = 420   // y  0–480
    private var bVelX: CGFloat = 0
    private var bVelY: CGFloat = 0
    private var bZ:   CGFloat = 0     // altitude above board floor (landing phase)
    private var bVZ:  CGFloat = 0     // altitude velocity
    private var bRot: CGFloat = 0     // rotation (radians)
    private var bRotV: CGFloat = 0    // rotation speed
    private var bSz:  CGFloat = 14    // size in virtual units

    // MARK: - Well (virtual, re-randomized per bag)
    private var wellVX: CGFloat = 160
    private var wellVY: CGFloat = 100
    private let wellR:  CGFloat = 48   // visual outer radius (was 36)
    private let wellIR: CGFloat = 30   // hit radius (was 26)

    // MARK: - Board (virtual, fixed below centre) — side-view sprite
    // bdW/bdH/hlX/hlR are *defaults* — `buildBoardNodes()` overwrites them to exactly
    // match the rendered sprite so hit-detection and visuals never drift apart.
    private let bdX: CGFloat = 160;  private let bdY: CGFloat = 290   // 290 → ~10 % below SK centre
    private var bdW: CGFloat = 200;  private var bdH: CGFloat = 100
    private var hlX: CGFloat = 120                  // recomputed in buildBoardNodes
    private let hlY: CGFloat = 290                  // centre line of the side-view board
    private var hlR: CGFloat = 18                   // recomputed in buildBoardNodes

    // MARK: - Descent state
    private var descentProg: CGFloat = 0
    private let descentTotal: CGFloat = 1200

    private struct WindZone { var depth: CGFloat; var dir: CGFloat; var force: CGFloat }
    private struct Cobweb   { var depth: CGFloat; var x: CGFloat; var radius: CGFloat; var cleared = false }
    private var winds:   [WindZone] = []
    private var cobwebs: [Cobweb]   = []

    // MARK: - Touch / steering
    // Launch: cornhole-style swipe (direction of swipe = direction of throw)
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?
    private var launchPowerScale: CGFloat = 0

    // Arc Z — SK-pixel units, same constants as CornholeMiniGameScene
    private var launchBZ:  CGFloat = 0   // height above "ground" during throw
    private var launchBVZ: CGFloat = 0   // vertical velocity of arc
    private var launchGrounded = false   // bag has landed on grass (missed well)
    private let launchGravity: CGFloat   = 0.50
    private let launchVZInitial: CGFloat = 15.0

    private var isSteering   = false
    private var steerRefX:   CGFloat = 0
    private var steerRefY:   CGFloat = 0
    private var tiltX: CGFloat = 0
    private var tiltY: CGFloat = 0

    // MARK: - Zoom transition
    private var zoomFrames = 0

    // MARK: - Game world (pixellate filter wraps all gameplay content)
    private var gameWorldNode: SKEffectNode!

    // MARK: - Nodes — grass / backgrounds
    private var grassBg:   SKSpriteNode!
    private var descentBg: SKSpriteNode!
    private var landingBg: SKSpriteNode!

    // MARK: - Nodes — well (launch phase)
    private var wellSprite: SKSpriteNode!

    // MARK: - Nodes — bag
    private var bagShadow: SKSpriteNode!
    private var bagSprite: SKSpriteNode!

    // MARK: - Nodes — launch hint
    private var hintLbl: SKLabelNode!

    // MARK: - Nodes — cornhole board (landing)
    private var boardContainer: SKNode!        // parent that slides in from below
    private var boardSprite:    SKSpriteNode!  // cornholeBoard_side texture
    private var glowBeam:       SKSpriteNode!  // yellow vertical guide beam from hole

    // MARK: - Nodes — descent brick walls (two tiles each side, scrolled)
    private var wL1: SKSpriteNode!;  private var wL2: SKSpriteNode!
    private var wR1: SKSpriteNode!;  private var wR2: SKSpriteNode!
    private var wallTileH: CGFloat = 0

    // MARK: - Nodes — descent HUD elements
    private var depthBarBg: SKShapeNode!
    private var depthCursor: SKSpriteNode!
    private var steerLbl:   SKLabelNode!

    // MARK: - Nodes — obstacle layer (winds / cobwebs, rebuilt per descent)
    private var obstacleLayer: SKNode!
    private var windNodePairs: [(line: SKShapeNode, label: SKLabelNode, zone: WindZone)] = []
    private var cobwebNodes:   [(shape: SKShapeNode, data: Cobweb)] = []

    // MARK: - Nodes — HUD ribbon
    private var scoreLbl: SKLabelNode!
    private var bagsLbl:  SKLabelNode!
    private var highLbl:  SKLabelNode!

    // MARK: - Nodes — toast
    private var toastNode: SKSpriteNode!
    private var toastLbl:  SKLabelNode!

    // MARK: - Nodes — sparks
    private var sparkLayer: SKNode!

    // MARK: - Nodes — CRT overlay
    private var crtNode: SKSpriteNode!

    private var hasSetup = false

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height

        if hasSetup { removeAllActions(); removeAllChildren() }
        hasSetup = true

        backgroundColor = SKColor(red: 0.078, green: 0.322, blue: 0.173, alpha: 1)

        // Physics world: heavy gravity so the bag accelerates noticeably as it falls,
        // selling the long drop from the well.  Precise collision detection on the bag
        // body prevents tunneling through the static board chunks at high velocity.
        physicsWorld.gravity         = CGVector(dx: 0, dy: -800.0)
        physicsWorld.contactDelegate = self

        buildAllNodes()

        if TutorialManager.shared.hasSeen(TutorialManager.wellFlinger) {
            startGame()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    // MARK: - Tutorial
    private func presentTutorial(autoTriggered: Bool) {
        let steps: [TutorialStep] = [
            .card(title: "WELL FLINGER",
                  body: "Drag the bag back and release to fling it into the well opening!"),
            .card(title: "STEER THE SHAFT",
                  body: "Drag your finger left and right to steer through wind gusts and sticky cobwebs."),
            .card(title: "LAND THE SHOT",
                  body: "Hit the HOLE for 3 pts. Land on the BOARD for 1 pt. Miss for 0. 5 bags per game!"),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            TutorialManager.shared.markSeen(TutorialManager.wellFlinger)
            if autoTriggered { self?.startGame() }
        }
        addChild(overlay)
    }

    // MARK: - Game start / reset
    private func startGame() {
        score = 0; bagsLeft = 5; accurateHits = 0; totalFlings = 0
        updateHUD()
        initLaunchPhase()
    }

    // MARK: - Node construction

    private func buildAllNodes() {
        computeLaunchPowerScale()

        // CIPixellate at scale 2 gives the chunky 16-bit look (same as CornholeMiniGameScene)
        gameWorldNode = SKEffectNode()
        if let filter = CIFilter(name: "CIPixellate") {
            filter.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = filter
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        addChild(gameWorldNode)

        sparkLayer    = SKNode(); sparkLayer.zPosition    = 60; gameWorldNode.addChild(sparkLayer)
        obstacleLayer = SKNode(); obstacleLayer.zPosition = 18; gameWorldNode.addChild(obstacleLayer)
        buildBackgrounds()
        buildWellNodes()
        buildBagNodes()
        buildTrajectoryNodes()
        buildDescentWalls()
        buildDescentDepthBar()
        buildBoardNodes()
        buildGroundSensor()
        buildHUD()
        buildToast()
        buildCRT()
    }

    /// Visible solid ground at the bottom of the play area.  The board sits ON this
    /// ground, and any bag whose X misses the board lands here (counts as a miss).
    /// Because the body is solid (collides with bag), the bag can NEVER fall past it.
    private var groundSprite: SKSpriteNode!
    private func buildGroundSensor() {
        let bottomH    = max(40, H * 0.08)
        let groundH: CGFloat = 90
        let groundTop = -H / 2 + bottomH + 80      // 80pt above the HUD bar top
        let centreY   = groundTop - groundH / 2

        // Visible dirt-coloured floor strip
        groundSprite = SKSpriteNode(color: SKColor(red: 0.32, green: 0.22, blue: 0.14, alpha: 1),
                                    size: CGSize(width: W, height: groundH))
        groundSprite.position  = CGPoint(x: 0, y: centreY)
        groundSprite.zPosition = 9                 // below board (z=10), above descent bg
        groundSprite.isHidden  = true              // shown when descent's approach phase starts
        addChild(groundSprite)

        // Solid physics body — bag CANNOT pass through this.
        let body = SKPhysicsBody(rectangleOf: CGSize(width: W * 4, height: groundH))
        body.isDynamic           = false
        body.categoryBitMask     = Self.groundCategory
        body.contactTestBitMask  = Self.bagCategory
        body.collisionBitMask    = Self.bagCategory   // SOLID — bag bounces/rests on it
        body.restitution         = 0.0
        body.friction            = 1.0
        groundSprite.physicsBody = body
        groundSprite.name        = "ground"
    }

    /// Scene-Y of the ground's top edge.  Used by `landingBoardCentreY` so the board
    /// rests exactly on top of the ground.
    private var groundTopY: CGFloat {
        let bottomH = max(40, H * 0.08)
        return -H / 2 + bottomH + 80
    }

    private func buildBackgrounds() {
        // Grass — matches CornholeMiniGameScene's outdoor daylight palette
        grassBg = SKSpriteNode(color: SKColor(red: 0.18, green: 0.38, blue: 0.13, alpha: 1),
                               size: CGSize(width: W * 2, height: H * 2))
        grassBg.position = .zero; grassBg.zPosition = -1; gameWorldNode.addChild(grassBg)
        addGrassPattern()

        let sunGlow = SKSpriteNode(color: SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 0.08),
                                   size: CGSize(width: W * 2, height: H * 2))
        sunGlow.position = .zero; sunGlow.zPosition = 0; gameWorldNode.addChild(sunGlow)

        descentBg = SKSpriteNode(color: SKColor(red: 0.059, green: 0.090, blue: 0.157, alpha: 1), size: size)
        descentBg.position = .zero; descentBg.zPosition = 0; descentBg.isHidden = true
        gameWorldNode.addChild(descentBg)

        landingBg = SKSpriteNode(color: SKColor(red: 0.043, green: 0.059, blue: 0.098, alpha: 1), size: size)
        landingBg.position = .zero; landingBg.zPosition = 0; landingBg.isHidden = true
        gameWorldNode.addChild(landingBg)
    }

    // Scatter random 4×4 pixel tufts — mirrors cornhole's addGrassPattern()
    private func addGrassPattern() {
        let tileSize: CGFloat = 4
        let palette: [SKColor] = [
            SKColor(red: 0.10, green: 0.25, blue: 0.08, alpha: 1),
            SKColor(red: 0.18, green: 0.38, blue: 0.14, alpha: 1),
            SKColor(red: 0.09, green: 0.22, blue: 0.07, alpha: 1),
        ]
        var x = -W
        while x < W {
            var y = -H
            while y < H {
                if Int.random(in: 0..<5) == 0 {
                    let tuft = SKSpriteNode(color: palette.randomElement()!,
                                           size: CGSize(width: tileSize, height: tileSize))
                    tuft.position  = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                    tuft.zPosition = 1
                    gameWorldNode.addChild(tuft)
                }
                y += tileSize
            }
            x += tileSize
        }
    }

    private func buildWellNodes() {
        let tex = makeWellTexture()
        let side = vw((wellR + 10) * 2)
        wellSprite = SKSpriteNode(texture: tex, size: CGSize(width: side, height: side))
        // Direct scene child (z=50) — bypasses SKEffectNode so isHidden is always reliable
        wellSprite.zPosition = 50
        addChild(wellSprite)
    }

    // Pixel-art stone well drawn with 8-pt blocks — grey, rough, not a smooth circle
    private func makeWellTexture() -> SKTexture {
        let pix: CGFloat  = 8          // block size (large = chunkier look)
        let outerR: CGFloat = 44
        let innerR: CGFloat = 26
        let side  = (outerR + pix * 2) * 2
        let cx = side / 2, cy = side / 2

        let stonePalette: [UIColor] = [
            UIColor(white: 0.30, alpha: 1),
            UIColor(white: 0.38, alpha: 1),
            UIColor(white: 0.22, alpha: 1),
            UIColor(white: 0.42, alpha: 1),
            UIColor(white: 0.17, alpha: 1),
        ]

        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            let c = ctx.cgContext
            var py: CGFloat = 0
            while py < side {
                var px: CGFloat = 0
                while px < side {
                    let dist = hypot(px + pix/2 - cx, py + pix/2 - cy)
                    let rect = CGRect(x: px, y: py, width: pix, height: pix)
                    if dist <= innerR {
                        c.setFillColor(UIColor(white: 0.06, alpha: 1).cgColor); c.fill(rect)
                    } else if dist <= innerR + pix * 1.5 {
                        c.setFillColor(UIColor(white: 0.14, alpha: 1).cgColor); c.fill(rect)
                    } else if dist <= outerR {
                        // XOR checkerboard index → rough stone texture
                        let ci = (Int(px / pix) ^ Int(py / pix)) % stonePalette.count
                        c.setFillColor(stonePalette[ci].cgColor); c.fill(rect)
                    } else if dist <= outerR + pix * 1.5 {
                        c.setFillColor(UIColor(white: 0.10, alpha: 1).cgColor); c.fill(rect)
                    }
                    px += pix
                }
                py += pix
            }
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return tex
    }

    private func buildBagNodes() {
        // Direct scene children (z=55/60) so the bag always renders above the well (z=50).
        // SKEffectNode composites its whole subtree at scene z=0, so anything inside it
        // sits behind direct scene nodes with z>0 regardless of intra-group z values.
        // bag_16bit has its own pixel-art texture so it doesn't need the CIPixellate filter.

        // Shadow — flat ellipse offset below the bag during landing arc
        bagShadow = SKSpriteNode(color: .black,
                                 size: CGSize(width: vw(16), height: vw(11)))
        bagShadow.alpha = 0.45; bagShadow.zPosition = 55; bagShadow.isHidden = true
        addChild(bagShadow)

        // 16-bit pixel bag — red player colour matching CornholeMiniGameScene
        let bagTex = SKTexture(imageNamed: "bag_16bit")
        bagTex.filteringMode = .nearest
        bagSprite = SKSpriteNode(texture: bagTex,
                                 size: CGSize(width: vw(bSz), height: vw(bSz)))
        bagSprite.color            = SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
        bagSprite.colorBlendFactor = 0.65
        bagSprite.zPosition        = 60
        addChild(bagSprite)

        // Physics body — 8-point beveled polygon that simulates the soft, yielding
        // edges of a fabric beanbag rather than a rigid rectangle.  The half-height
        // is kept to 25 % of the sprite so the bag visually plants into the wood on
        // landing instead of sitting perched on top of it.
        let descentBagSize = vw(24)
        let hw  = descentBagSize * 0.42   // half-width
        let hh  = descentBagSize * 0.25   // half-height (short → bag sinks into wood)
        let bev = descentBagSize * 0.10   // corner bevel — rounds the hard edges

        // 8-point beveled rectangle (corners cut diagonally)
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: -hw + bev, y:  hh))
        path.addLine(to: CGPoint(x:  hw - bev, y:  hh))
        path.addLine(to: CGPoint(x:  hw,       y:  hh - bev))
        path.addLine(to: CGPoint(x:  hw,       y: -hh + bev))
        path.addLine(to: CGPoint(x:  hw - bev, y: -hh))
        path.addLine(to: CGPoint(x: -hw + bev, y: -hh))
        path.addLine(to: CGPoint(x: -hw,       y: -hh + bev))
        path.addLine(to: CGPoint(x: -hw,       y:  hh - bev))
        path.closeSubpath()

        let body = SKPhysicsBody(polygonFrom: path)
        body.isDynamic                     = false
        body.affectedByGravity             = false
        body.allowsRotation                = true      // bag can tumble naturally on impact

        body.restitution                   = 0.12      // nearly dead bounce — fabric absorbs energy
        body.friction                      = 0.55      // grabs the wood and stops sliding quickly
        body.linearDamping                 = 0.6       // air resistance during free-fall
        body.angularDamping                = 0.9       // damps spin rapidly so bag settles fast

        body.usesPreciseCollisionDetection = true      // prevent tunneling at high velocity
        body.categoryBitMask               = Self.bagCategory
        body.collisionBitMask              = Self.boardCategory | Self.groundCategory
        body.contactTestBitMask            = Self.boardCategory | Self.holeCategory | Self.groundCategory
        bagSprite.physicsBody              = body
    }

    /// Common configuration for the two static board-surface bodies.
    private func configureStaticBoardBody(_ body: SKPhysicsBody?) {
        guard let body else { return }
        body.isDynamic           = false
        body.categoryBitMask     = Self.boardCategory
        body.contactTestBitMask  = Self.bagCategory
        body.collisionBitMask    = Self.bagCategory
        body.restitution         = 0.05   // almost no bounce — board acts like padded wood
        body.friction            = 0.55   // matches bag friction so the bag grips and settles
    }

    private func buildTrajectoryNodes() {
        hintLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        hintLbl.text = "SWIPE TO THROW"
        hintLbl.fontSize = vw(7); hintLbl.fontColor = .yellow
        hintLbl.horizontalAlignmentMode = .center
        // Direct scene child — same reason as wellSprite (reliable isHidden through SKEffectNode)
        hintLbl.zPosition = 50
        addChild(hintLbl)
    }

    private func computeLaunchPowerScale() {
        // Ballistic calibration (same as CornholeMiniGameScene):
        // vx/vy are constant during flight; only vz is affected by gravity.
        // A 35%-screen upward swipe should land the bag right at the well.
        let virtualYDist: CGFloat = 200   // bag y=300 → well y≈100
        let flightFrames: CGFloat = 2 * launchVZInitial / launchGravity   // 60 frames
        let targetVelY:   CGFloat = virtualYDist / flightFrames            // virtual units/frame
        let idealSwipe:   CGFloat = H * 0.35
        launchPowerScale = targetVelY / (idealSwipe * 480 / H)
    }

    private func buildDescentWalls() {
        let wallW  = vw(48)
        wallTileH  = H          // full screen height → 2 tiles always cover [-3H/2, H/2] ✓
        let texSz  = CGSize(width: wallW, height: wallTileH)
        let tex    = makeBrickTexture(size: texSz)

        func makeWall() -> SKSpriteNode {
            let n = SKSpriteNode(texture: tex, size: texSz)
            n.texture?.filteringMode = .nearest
            n.zPosition = 3; n.isHidden = true; return n
        }
        wL1 = makeWall(); wL2 = makeWall(); wR1 = makeWall(); wR2 = makeWall()
        [wL1, wL2, wR1, wR2].forEach { gameWorldNode.addChild($0) }
    }

    private func makeBrickTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let brickH: CGFloat = 16
            var row: CGFloat = 0
            while row < size.height {
                let even = Int(row / brickH) % 2 == 0
                c.setFillColor((even
                    ? UIColor(red: 0.498, green: 0.114, blue: 0.114, alpha: 1)
                    : UIColor(red: 0.600, green: 0.114, blue: 0.114, alpha: 1)).cgColor)
                c.fill(CGRect(x: 0, y: row, width: size.width, height: brickH - 2))
                c.setFillColor(UIColor(red: 0.722, green: 0.176, blue: 0.176, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: row, width: size.width, height: 2))
                row += brickH
            }
            // Inner edge shadow
            let space = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(white: 0, alpha: 0.82).cgColor,
                        UIColor(white: 0, alpha: 0.0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: space, colors: cols, locations: [0, 1.0]) {
                c.drawLinearGradient(grad,
                    start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
        }
        return SKTexture(image: img)
    }

    private func buildDescentDepthBar() {
        let barH = vh(120)
        let bRect = CGRect(x: -vw(4), y: -barH / 2, width: vw(8), height: barH)
        depthBarBg = SKShapeNode(rect: bRect)
        depthBarBg.fillColor   = .black.withAlphaComponent(0.65)
        depthBarBg.strokeColor = SKColor(white: 0.28, alpha: 1)
        depthBarBg.lineWidth   = 1; depthBarBg.zPosition = 22; depthBarBg.isHidden = true
        addChild(depthBarBg)

        depthCursor = SKSpriteNode(color: .yellow, size: CGSize(width: vw(16), height: vh(4)))
        depthCursor.zPosition = 23; depthCursor.isHidden = true
        addChild(depthCursor)

        steerLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        steerLbl.text = "DRAG TO STEER"; steerLbl.fontSize = vw(6)
        steerLbl.fontColor = SKColor(white: 0.58, alpha: 1)
        steerLbl.horizontalAlignmentMode = .center
        steerLbl.zPosition = 22; steerLbl.isHidden = true
        addChild(steerLbl)
    }

    private func buildBoardNodes() {
        // boardContainer is now a DIRECT SCENE CHILD (not inside gameWorldNode).
        // The CIPixellate filter doesn't apply to it, but that's fine — board_16bit is
        // already pixel art, and this puts the bag (also a direct child) and the board
        // in the same coordinate space so SK physics is reliable.
        boardContainer = SKNode()
        boardContainer.zPosition = 10
        boardContainer.isHidden  = true
        addChild(boardContainer)

        // Side-view cornhole board sprite — hole is part of the graphic on the left side.
        let (boardTex, contentAspect) = loadTrimmedBoardTexture()
        boardTex.filteringMode = .nearest

        let bw = W * 0.55                                              // board is 55 % of screen width
        let bh = bw * contentAspect                                    // height from trimmed art

        // Rewrite virtual board dimensions to match the actual rendered sprite
        bdW = bw * 320 / W
        bdH = bh * 480 / H

        // Hole on the left side of the side-view sprite — ~20 % in from left edge
        hlX = bdX - bdW / 2 + bdW * 0.20
        hlR = bdW * 0.08    // hole radius proportional to board width

        // Drop shadow (depth cue) — sized to match the actual sprite, slight offset
        let shadowNode = SKSpriteNode(color: .black,
                                      size: CGSize(width: bw, height: bh))
        shadowNode.alpha     = 0.35
        shadowNode.position  = CGPoint(x: 4, y: -5)
        shadowNode.zPosition = -1
        boardContainer.addChild(shadowNode)

        boardSprite = SKSpriteNode(texture: boardTex,
                                   size: CGSize(width: bw, height: bh))
        boardSprite.zPosition = 0
        boardContainer.addChild(boardSprite)

        // ── Physics: two solid chunks flanking the hole ──────────────────────
        // SK x is local to boardContainer (board centre = 0,0).  Hole opening
        // spans [holeLocalX - holeR_SK, holeLocalX + holeR_SK] in local x.
        let holeLocalX = vw(hlX - bdX)        // negative → left of centre
        let holeR_SK   = vw(hlR)

        let leftBodyLeft   = -bw / 2
        let leftBodyRight  = holeLocalX - holeR_SK
        let leftBodyWidth  = max(2, leftBodyRight - leftBodyLeft)
        let leftBodyCentre = (leftBodyLeft + leftBodyRight) / 2

        let rightBodyLeft  = holeLocalX + holeR_SK
        let rightBodyRight = bw / 2
        let rightBodyWidth = max(2, rightBodyRight - rightBodyLeft)
        let rightBodyCentre = (rightBodyLeft + rightBodyRight) / 2

        // Chunk bodies — 80% of board height, pushed down 10% so their TOP edge sits
        // well below any anti-aliased halo at the top of the trimmed PNG.
        let chunkHeight: CGFloat = bh * 0.80
        let chunkLocalY: CGFloat = -bh * 0.10

        let leftChunk = SKNode()
        leftChunk.position = CGPoint(x: leftBodyCentre, y: chunkLocalY)
        leftChunk.physicsBody = SKPhysicsBody(rectangleOf:
            CGSize(width: leftBodyWidth, height: chunkHeight))
        configureStaticBoardBody(leftChunk.physicsBody)
        boardContainer.addChild(leftChunk)

        let rightChunk = SKNode()
        rightChunk.position = CGPoint(x: rightBodyCentre, y: chunkLocalY)
        rightChunk.physicsBody = SKPhysicsBody(rectangleOf:
            CGSize(width: rightBodyWidth, height: chunkHeight))
        configureStaticBoardBody(rightChunk.physicsBody)
        boardContainer.addChild(rightChunk)

        // Hole sensor
        let holeSensor = SKNode()
        holeSensor.position = CGPoint(x: holeLocalX, y: bh * 0.25)
        let holeBody = SKPhysicsBody(rectangleOf: CGSize(width: holeR_SK * 2, height: bh * 0.30))
        holeBody.isDynamic           = false
        holeBody.categoryBitMask     = Self.holeCategory
        holeBody.contactTestBitMask  = Self.bagCategory
        holeBody.collisionBitMask    = 0       // sensor only — no physical push
        holeSensor.physicsBody       = holeBody
        boardContainer.addChild(holeSensor)

        // Hole position in the board's local space
        let holeLocalY = vh(bdY - hlY)

        // Yellow guide beam
        let beamW: CGFloat = vw(hlR * 2.2)
        let beamH: CGFloat = H * 1.4
        glowBeam = SKSpriteNode(texture: makeGlowBeamTexture(width: beamW, height: beamH),
                                size: CGSize(width: beamW, height: beamH))
        glowBeam.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        glowBeam.position    = CGPoint(x: holeLocalX, y: holeLocalY)
        glowBeam.zPosition   = 1
        glowBeam.blendMode   = .add
        boardContainer.addChild(glowBeam)

        glowBeam.alpha = 0.45
        glowBeam.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.70, duration: 0.65),
            .fadeAlpha(to: 0.30, duration: 0.65),
        ])))
    }

    /// Draws the cornhole board procedurally
    private func loadTrimmedBoardTexture() -> (SKTexture, CGFloat) {
        let dw: CGFloat = 320
        let dh: CGFloat = 160
        let aspect: CGFloat = dh / dw

        let surfTop:  CGFloat = dh * 0.20
        let surfBot:  CGFloat = dh * 0.70
        let legBot:   CGFloat = dh * 0.97
        let legW:     CGFloat = dw * 0.055
        let faceH:    CGFloat = surfBot - surfTop
        let topBandH: CGFloat = faceH * 0.80

        let holeR:  CGFloat = dw * 0.08
        let holeCX: CGFloat = dw * 0.20
        let holeCY: CGFloat = surfTop + topBandH * 0.50

        let woodDark   = UIColor(red: 0.42, green: 0.24, blue: 0.08, alpha: 1).cgColor
        let woodMid    = UIColor(red: 0.58, green: 0.36, blue: 0.14, alpha: 1).cgColor
        let woodLight  = UIColor(red: 0.70, green: 0.48, blue: 0.22, alpha: 1).cgColor
        let woodEdge   = UIColor(red: 0.28, green: 0.13, blue: 0.03, alpha: 1).cgColor
        let grainColor = UIColor(red: 0.38, green: 0.20, blue: 0.06, alpha: 0.28).cgColor
        let highlight  = UIColor(red: 0.85, green: 0.65, blue: 0.32, alpha: 0.55).cgColor

        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: dw, height: dh),
                                          format: fmt).image { ctx in
            let c = ctx.cgContext
            c.interpolationQuality = .none

            c.setFillColor(woodDark)
            c.fill(CGRect(x: dw * 0.04, y: surfBot, width: legW, height: legBot - surfBot))
            c.fill(CGRect(x: dw * 0.90, y: surfBot, width: legW, height: legBot - surfBot))

            let body = CGRect(x: 0, y: surfTop, width: dw, height: faceH)
            c.setFillColor(woodDark); c.fill(body)

            c.setFillColor(woodMid)
            c.fill(CGRect(x: 0, y: surfTop, width: dw, height: topBandH))

            c.setStrokeColor(grainColor); c.setLineWidth(1)
            for i in 1 ..< 8 {
                let y = surfTop + topBandH * CGFloat(i) / 8
                c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: dw, y: y))
            }
            c.strokePath()

            let faceTop = surfTop + topBandH
            c.setFillColor(woodLight)
            c.fill(CGRect(x: 0, y: faceTop, width: dw, height: faceH - topBandH))

            c.setStrokeColor(highlight); c.setLineWidth(2)
            c.move(to: CGPoint(x: 2,         y: surfTop + 1))
            c.addLine(to: CGPoint(x: dw - 2, y: surfTop + 1)); c.strokePath()

            c.setStrokeColor(woodEdge); c.setLineWidth(2); c.stroke(body)

            // Pixelated hole — drawn as a grid of 4-pt blocks matching the well texture style.
            // Each block is either hole-black, rim-dark-wood, or transparent (skip).
            let pix: CGFloat = 4
            var py = holeCY - holeR - pix * 2
            while py < holeCY + holeR + pix * 2 {
                var px = holeCX - holeR - pix * 2
                while px < holeCX + holeR + pix * 2 {
                    let dist = hypot(px + pix / 2 - holeCX, py + pix / 2 - holeCY)
                    let rect = CGRect(x: px, y: py, width: pix, height: pix)
                    if dist <= holeR {
                        c.setFillColor(UIColor.black.cgColor); c.fill(rect)
                    } else if dist <= holeR + pix * 1.8 {
                        c.setFillColor(woodEdge); c.fill(rect)
                    }
                    px += pix
                }
                py += pix
            }
        }

        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return (tex, aspect)
    }

    private func makeGlowBeamTexture(width: CGFloat, height: CGFloat) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                          format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            let verticalColors = [
                UIColor(red: 1.00, green: 0.93, blue: 0.40, alpha: 0.95).cgColor,
                UIColor(red: 1.00, green: 0.92, blue: 0.35, alpha: 0.55).cgColor,
                UIColor(red: 1.00, green: 0.90, blue: 0.30, alpha: 0.00).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: verticalColors,
                                  locations: [0, 0.35, 1.0]) {
                c.drawLinearGradient(g,
                    start: CGPoint(x: width / 2, y: height),
                    end:   CGPoint(x: width / 2, y: 0),
                    options: [])
            }

            let horizontalColors = [
                UIColor(white: 1, alpha: 0.00).cgColor,
                UIColor(white: 1, alpha: 0.55).cgColor,
                UIColor(white: 1, alpha: 0.00).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: horizontalColors,
                                  locations: [0, 0.5, 1.0]) {
                c.setBlendMode(.destinationIn)
                c.drawLinearGradient(g,
                    start: CGPoint(x: 0, y: height / 2),
                    end:   CGPoint(x: width, y: height / 2),
                    options: [])
                c.setBlendMode(.normal)
            }
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return tex
    }

    private func makePixelCircleTexture(radius: CGFloat, fill: UIColor, border: UIColor, pixelSize: Int) -> SKTexture {
        let ps    = CGFloat(pixelSize)
        let cells = Int(ceil(radius * 2 / ps)) + 2
        let imgPx = cells * pixelSize
        let imgSz = CGSize(width: CGFloat(imgPx), height: CGFloat(imgPx))
        let cx    = CGFloat(cells) / 2.0
        let cy    = CGFloat(cells) / 2.0
        let r     = radius / ps

        UIGraphicsBeginImageContextWithOptions(imgSz, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }

        for row in 0..<cells {
            for col in 0..<cells {
                let dist = hypot(CGFloat(col) + 0.5 - cx, CGFloat(row) + 0.5 - cy)
                let rect = CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps,
                                  width: ps, height: ps)
                if dist <= r {
                    ctx.setFillColor(fill.cgColor);   ctx.fill(rect)
                } else if dist <= r + 1.0 {
                    ctx.setFillColor(border.cgColor); ctx.fill(rect)
                }
            }
        }
        let tex = SKTexture(image: UIGraphicsGetImageFromCurrentImageContext()!)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - HUD
    private func buildHUD() {
        let font       = "PressStart2P-Regular"
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
        let dsIronGray = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1) // #595959

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH:    CGFloat  = 48
        let bottomH: CGFloat  = max(40, H * 0.08)
        let totalTopH = topH + topInset
        let topBarY   = H / 2 - topInset - topH / 2
        let botBarY   = -H / 2 + bottomH / 2

        let topBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: W, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: H / 2 - totalTopH / 2)
        topBar.zPosition = 500; addChild(topBar)

        let topBorder = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        topBorder.position  = CGPoint(x: 0, y: H / 2 - totalTopH)
        topBorder.zPosition = 501; addChild(topBorder)

        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size      = CGSize(width: 22, height: 22)
        pauseBtn.position  = CGPoint(x: -W / 2 + 22, y: topBarY)
        pauseBtn.zPosition = 502; pauseBtn.name = "pauseBtn"; addChild(pauseBtn)

        let helpBtn = TutorialHelpButton.make()
        helpBtn.position  = CGPoint(x: -W / 2 + 52, y: topBarY)
        helpBtn.zPosition = 502; addChild(helpBtn)

        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: W / 2 - 22, y: topBarY)
        closeBtn.zPosition = 502; closeBtn.name = "closeButton"; addChild(closeBtn)

        scoreLbl = SKLabelNode(fontNamed: font)
        scoreLbl.text = "0000"; scoreLbl.fontSize = vw(9); scoreLbl.fontColor = dsGold
        scoreLbl.horizontalAlignmentMode = .left; scoreLbl.verticalAlignmentMode = .center
        scoreLbl.position = CGPoint(x: -W / 2 + 80, y: topBarY); scoreLbl.zPosition = 502
        addChild(scoreLbl)

        bagsLbl = SKLabelNode(fontNamed: font)
        bagsLbl.text = "5/5"; bagsLbl.fontSize = vw(9)
        bagsLbl.fontColor = SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1)
        bagsLbl.horizontalAlignmentMode = .center; bagsLbl.verticalAlignmentMode = .center
        bagsLbl.position = CGPoint(x: 0, y: topBarY); bagsLbl.zPosition = 502
        addChild(bagsLbl)

        highLbl = SKLabelNode(fontNamed: font)
        highLbl.text = String(format: "%04d", highScore); highLbl.fontSize = vw(9)
        highLbl.fontColor = SKColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        highLbl.horizontalAlignmentMode = .right; highLbl.verticalAlignmentMode = .center
        highLbl.position = CGPoint(x: W / 2 - 44, y: topBarY); highLbl.zPosition = 502
        addChild(highLbl)

        func bolt(at pt: CGPoint) {
            let b = SKSpriteNode(color: dsIronGray, size: CGSize(width: 4, height: 4))
            b.position = pt; b.zPosition = 503; addChild(b)
        }
        bolt(at: CGPoint(x: -W/2 + 5, y: H/2 - topInset - 5))
        bolt(at: CGPoint(x:  W/2 - 5, y: H/2 - topInset - 5))
        bolt(at: CGPoint(x: -W/2 + 5, y: H/2 - totalTopH + 5))
        bolt(at: CGPoint(x:  W/2 - 5, y: H/2 - totalTopH + 5))

        let botBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: W, height: bottomH))
        botBar.position  = CGPoint(x: 0, y: botBarY)
        botBar.zPosition = 500; addChild(botBar)

        let botBorder = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        botBorder.position  = CGPoint(x: 0, y: botBarY + bottomH / 2)
        botBorder.zPosition = 501; addChild(botBorder)

        bolt(at: CGPoint(x: -W/2 + 5, y: botBarY + bottomH/2 - 5))
        bolt(at: CGPoint(x:  W/2 - 5, y: botBarY + bottomH/2 - 5))
    }

    private func updateHUD() {
        scoreLbl.text = String(format: "%04d", score)
        bagsLbl.text  = "\(bagsLeft)/5"
        highLbl.text  = String(format: "%04d", highScore)
    }

    // MARK: - Toast
    private func buildToast() {
        toastNode = SKSpriteNode(color: SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1),
                                  size: CGSize(width: vw(220), height: vh(28)))
        toastNode.zPosition = 90; toastNode.alpha = 0
        addChild(toastNode)

        toastLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        toastLbl.fontSize   = vw(6.5)
        toastLbl.fontColor  = SKColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        toastLbl.horizontalAlignmentMode = .center
        toastLbl.verticalAlignmentMode   = .center
        toastLbl.zPosition  = 1
        toastNode.addChild(toastLbl)
    }

    private func showToast(_ msg: String) {
        let topInset = view?.safeAreaInsets.top ?? 0
        toastNode.position = CGPoint(x: 0, y: H/2 - topInset - vh(90))
        toastLbl.text = msg
        toastNode.removeAllActions()
        toastNode.alpha = 1; toastNode.setScale(1)
        toastNode.run(.sequence([
            .wait(forDuration: 1.6),
            .group([
                .fadeOut(withDuration: 0.3),
                .scale(to: 0.8, duration: 0.3),
            ]),
        ]))
    }

    // MARK: - CRT overlay
    private func buildCRT() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0, alpha: 0.20).cgColor)
            var y: CGFloat = 0
            while y < size.height { c.fill(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let cols  = [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.16).cgColor,
                         UIColor(white: 0, alpha: 0.60).cgColor] as CFArray
            if let vg = CGGradient(colorsSpace: space, colors: cols, locations: [0, 0.55, 1.0]) {
                c.drawRadialGradient(vg,
                    startCenter: CGPoint(x: size.width/2, y: size.height/2), startRadius: 0,
                    endCenter:   CGPoint(x: size.width/2, y: size.height/2),
                    endRadius:   max(size.width, size.height) * 0.72, options: [])
            }
        }
        crtNode = SKSpriteNode(texture: SKTexture(image: img), size: size)
        crtNode.position = .zero; crtNode.zPosition = 800
        crtNode.isUserInteractionEnabled = false
        addChild(crtNode)
    }

    // MARK: - Phase init

    private func initLaunchPhase() {
        bVX = 160; bVY = 390
        bVelX = 0; bVelY = 0; bZ = 0; bVZ = 0
        bRot  = 0; bRotV = 0; bSz = 56
        launchBZ = 0; launchBVZ = 0; launchGrounded = false
        touchStart = nil; aimingLine?.removeFromParent(); aimingLine = nil
        isSteering = false; tiltX = 0; tiltY = 0

        wellVX = 160 + CGFloat.random(in: -30...30)
        wellVY = 100 + CGFloat.random(in: -15...15)

        physicsActive = false
        hasScored = false
        if let body = bagSprite.physicsBody {
            body.velocity        = .zero
            body.angularVelocity = 0
            body.isDynamic       = false
            body.affectedByGravity = false
        }

        bagSprite.removeAllActions()
        bagSprite.alpha = 1; bagSprite.setScale(1)

        wellSprite.position = vs(wellVX, wellVY)
        wellSprite.alpha    = 1

        applyPhaseVisibility(.launch)

        hintLbl.position = vs(bVX, bVY - 28)
        hintLbl.isHidden = false
    }

    private func initDescentPhase() {
        descentProg = 0
        bVX = 160; bVY = 240; bVelX = 0; bVelY = 0; bZ = 0
        bRot = 0; bSz = 24
        launchBZ = 0; launchBVZ = 0
        isSteering = false; tiltX = 0; tiltY = 0

        winds = []; cobwebs = []
        var d: CGFloat = 150
        while d < descentTotal - 350 {
            winds.append(WindZone(depth: d,
                                   dir:   Bool.random() ? 1 : -1,
                                   force: 1.5 + .random(in: 0...1.5)))
            d += 200
        }
        var dc: CGFloat = 250
        while dc < descentTotal - 350 {
            cobwebs.append(Cobweb(depth: dc,
                                   x: 60 + .random(in: 0...200),
                                   radius: 20 + .random(in: 0...12)))
            dc += 300
        }

        rebuildObstacleNodes()
        applyPhaseVisibility(.descent)
    }

    private var landingBoardCentreY: CGFloat {
        let bh = boardSprite?.size.height ?? 80
        return groundTopY + bh / 2
    }
    
    private var boardSlideStartY: CGFloat {
        -H / 2 - (boardSprite?.size.height ?? 100)
    }

    private func rebuildObstacleNodes() {
        obstacleLayer.removeAllChildren()
        windNodePairs = []
        cobwebNodes   = []

        for w in winds {
            let line = SKShapeNode()
            line.strokeColor = SKColor(red: 0.22, green: 0.75, blue: 0.95, alpha: 0.7)
            line.lineWidth = vw(2); obstacleLayer.addChild(line)

            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text = "WIND"; lbl.fontSize = vw(5.5)
            lbl.fontColor = SKColor(red: 0.22, green: 0.75, blue: 0.95, alpha: 1)
            lbl.horizontalAlignmentMode = .center
            obstacleLayer.addChild(lbl)

            windNodePairs.append((line: line, label: lbl, zone: w))
        }

        for cw in cobwebs {
            let shape = SKShapeNode()
            shape.strokeColor = SKColor(white: 1, alpha: 0.25)
            shape.lineWidth = vw(1.5)
            obstacleLayer.addChild(shape)
            cobwebNodes.append((shape: shape, data: cw))
        }
    }

    // MARK: - Phase visibility
    private func applyPhaseVisibility(_ p: Phase) {
        phase = p

        let isLaunch     = (p == .launch  || p == .zoomIn)
        let showShaft    = (p == .descent || p == .sinking)
        let showBoard    = (p == .descent || p == .sinking || p == .landing)

        grassBg.isHidden       = !isLaunch
        wellSprite.isHidden    = !isLaunch
        hintLbl.isHidden       = !isLaunch

        descentBg.isHidden     = !showShaft
        wL1.isHidden           = !showShaft
        wL2.isHidden           = !showShaft
        wR1.isHidden           = !showShaft
        wR2.isHidden           = !showShaft
        depthBarBg.isHidden    = !showShaft
        depthCursor.isHidden   = !showShaft
        steerLbl.isHidden      = !showShaft
        obstacleLayer.isHidden = !showShaft

        landingBg.isHidden = (p != .landing)
        if !showBoard {
            boardContainer.isHidden = true
            groundSprite?.isHidden  = true
        }
        bagShadow.isHidden = (p != .landing)
    }

    // MARK: - update

    private var lastTime: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        lastTime = (lastTime == 0) ? currentTime : lastTime
        lastTime = currentTime

        switch phase {
        case .launch:   updateLaunch(currentTime: currentTime)
        case .zoomIn:   updateZoomIn()
        case .descent:  updateDescent()
        case .sinking:  updateSinking()
        case .landing, .gameOver: break
        }

        if hasScored, let body = bagSprite.physicsBody, body.isDynamic {
            body.velocity        = .zero
            body.angularVelocity = 0
            body.isDynamic       = false
        }

        updateBagVisual()
    }

    // MARK: - Launch physics

    private func updateLaunch(currentTime: TimeInterval) {
        if bVelX == 0 && bVelY == 0 && !launchGrounded {
            let pulse = CGFloat(sin(currentTime * 5.0)) * vh(3)
            hintLbl.position = vs(bVX, bVY - 24 + pulse)
            hintLbl.isHidden = (touchStart != nil)
            return
        }

        if launchGrounded { return }

        launchBVZ -= launchGravity
        launchBZ  += launchBVZ
        bVX       += bVelX
        bVY       += bVelY
        bRot      += bRotV

        if launchBZ <= 0 {
            launchBZ = 0; launchBVZ = 0

            let dx = bVX - wellVX; let dy = bVY - wellVY
            if hypot(dx, dy) < wellIR {
                zoomFrames = 18
                spawnSparks(at: vs(wellVX, wellVY), color: .yellow, count: 20)
                playHoleEnter()
                applyPhaseVisibility(.zoomIn)
            } else {
                launchGrounded = true
                bVelX = 0; bVelY = 0; bRotV = 0
                bSz   = 30
                playMiss()
                flingEnded(pts: 0, msg: "MISSED WELL!")
            }
        }
    }

    private func updateZoomIn() {
        zoomFrames -= 1
        bRot += 0.15
        bSz  = max(8, bSz * 0.94)
        bVX  += (wellVX - bVX) * 0.1
        bVY  += (wellVY - bVY) * 0.1
        if zoomFrames <= 0 {
            initDescentPhase()
        }
    }

    private func updateDescent() {
        descentProg += 4.5

        bVX += tiltX * 3.5
        bVY += tiltY * 1.5
        bRot += 0.04

        if bVX < 52  { bVX = 52;  playBounce(); spawnSparks(at: vs(bVX, bVY), color: SKColor(red:0.7,green:0.3,blue:0.3,alpha:1), count: 4) }
        if bVX > 268 { bVX = 268; playBounce(); spawnSparks(at: vs(bVX, bVY), color: SKColor(red:0.7,green:0.3,blue:0.3,alpha:1), count: 4) }
        if bVY < 60  { bVY = 60 }
        if bVY > 360 { bVY = 360 }

        for w in winds {
            let wScreenVY = w.depth - descentProg + 240
            if abs(bVY - wScreenVY) < 30 {
                bVX += w.dir * w.force
                if Float.random(in: 0...1) < 0.04 { playWind() }
            }
        }

        for i in cobwebs.indices where !cobwebs[i].cleared {
            let cwVY = cobwebs[i].depth - descentProg + 240
            if hypot(bVX - cobwebs[i].x, bVY - cwVY) < cobwebs[i].radius {
                cobwebs[i].cleared = true
                playMiss()
                spawnSparks(at: vs(cobwebs[i].x, cwVY), color: .white, count: 10)
                showToast("STICKY COBWEB!")
                HapticsManager.shared.warningFeedback()
                tiltX = -tiltX * 0.5
            }
        }

        updateObstaclePositions()
        updateWallScroll()

        let barH  = vh(120)
        let ratio = min(descentProg / descentTotal, 1)
        depthBarBg.position  = CGPoint(x: W/2 - vw(26), y: 0)
        depthCursor.position = CGPoint(x: W/2 - vw(26), y: barH/2 - barH * ratio)
        steerLbl.position    = CGPoint(x: 0, y: -H/2 + vh(35))

        if descentProg >= descentTotal - 300 && !physicsActive {
            animateBoardSlideUp()
        }
    }

    private func updateSinking() {
        guard !hasScored else { return }
        descentProg += 4.5
        updateWallScroll()
        updateObstaclePositions()
    }

    private func animateBoardSlideUp() {
        if boardContainer.isHidden {
            boardContainer.isHidden = false
            boardContainer.position = CGPoint(x: 0, y: boardSlideStartY)
            groundSprite.isHidden   = false
        }

        let approachProg = (descentProg - (descentTotal - 300)) / 300
        let slideDuration: CGFloat = 0.70
        let slideProg     = min(1.0, approachProg / slideDuration)
        let eased = 1 - pow(1 - slideProg, 3)
        let startY = boardSlideStartY
        let endY   = landingBoardCentreY
        boardContainer.position = CGPoint(x: 0, y: startY + (endY - startY) * eased)

        if slideProg >= 1.0 {
            activatePhysicsLanding()
        }
    }

    // MARK: - Physics-driven landing

    private func activatePhysicsLanding() {
        physicsActive = true
        hasScored = false
        phase = .sinking
        isSteering = false; tiltX = 0; tiltY = 0

        boardContainer.position = CGPoint(x: 0, y: landingBoardCentreY)
        boardContainer.isHidden = false

        bagSprite.position = vs(bVX, bVY)
        if let body = bagSprite.physicsBody {
            body.isDynamic         = true
            body.affectedByGravity = true
            body.allowsRotation    = true
            // Random lateral drift + spin so each landing feels unique — like a fabric
            // bag tumbling out of the shaft rather than dropping on a fixed track.
            let randomSlide = CGFloat.random(in: -60...60)
            let randomSpin  = CGFloat.random(in: -3.0...3.0)
            // dy -550 matches the visual scroll momentum of the descent phase so
            // the bag never appears to brake when physics takes over
            body.velocity        = CGVector(dx: randomSlide, dy: -550)
            body.angularVelocity = randomSpin
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard physicsActive, !hasScored else { return }

        let cats = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard cats & Self.bagCategory != 0 else { return }

        if cats & Self.holeCategory != 0 {
            hasScored = true
            scorePhysics(.hole)
        } else if cats & Self.boardCategory != 0 {
            hasScored = true
            scorePhysics(.board)
        } else if cats & Self.groundCategory != 0 {
            hasScored = true
            scorePhysics(.miss)
        }
    }

    private enum LandingOutcome { case hole, board, miss }

    private func scorePhysics(_ outcome: LandingOutcome) {
        depthBarBg.isHidden    = true
        depthCursor.isHidden   = true
        obstacleLayer.isHidden = true
        steerLbl.isHidden      = true

        switch outcome {
        case .hole:
            playSound("hole_score.wav")
            playSound("hit.mp3")
            HapticsManager.shared.heavyImpact()
            HapticsManager.shared.successFeedback()
            spawnSparks(at: bagSprite.position, color: .yellow, count: 24)
            freezeBag()
            bagSprite.run(.sequence([
                .group([
                    .scale(to: 0.05, duration: 0.45),
                    .moveBy(x: 0, y: -vh(28), duration: 0.45),
                    .fadeOut(withDuration: 0.45),
                ]),
                .run { [weak self] in self?.flingEnded(pts: 3, msg: "3 PTS! HOLE-IN-ONE!") },
            ]))
        case .board:
            // Board hit — let SK physics bounce the bag naturally for 1.5 s, THEN freeze.
            playHitBoard()
            HapticsManager.shared.mediumImpact()
            spawnSparks(at: bagSprite.position, color: .orange, count: 12)
            
            run(.sequence([
                .wait(forDuration: 1.60), // Extra time for the high-speed skid to settle
                .run { [weak self] in
                    guard let self else { return }
                    // Freeze it ONLY after the bounce is done
                    self.freezeBag()
                    self.flingEnded(pts: 1, msg: "1 PT! ON THE BOARD!")
                }
            ]))
        case .miss:
            playMiss()
            HapticsManager.shared.lightImpact()
            spawnSparks(at: bagSprite.position, color: .gray, count: 8)
            freezeBag()
            flingEnded(pts: 0, msg: "0 PTS! MISSED BOARD!")
        }
    }

    private func freezeBag() {
        guard let body = bagSprite.physicsBody else { return }
        body.velocity        = .zero
        body.angularVelocity = 0
        body.isDynamic       = false
    }

    private func updateObstaclePositions() {
        for pair in windNodePairs {
            let wVY   = pair.zone.depth - descentProg + 240
            let skPt  = vs(160, wVY)
            let visible = wVY > 0 && wVY < 480

            pair.line.isHidden  = !visible
            pair.label.isHidden = !visible
            guard visible else { continue }

            let animOff = CGFloat(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1.0)) * vw(40)
            let linePath = CGMutablePath()
            if pair.zone.dir > 0 {
                linePath.move(to:    CGPoint(x: -W/2 + vw(48) + animOff, y: skPt.y))
                linePath.addLine(to: CGPoint(x:  W/2 - vw(48), y: skPt.y))
            } else {
                linePath.move(to:    CGPoint(x:  W/2 - vw(48) - animOff, y: skPt.y))
                linePath.addLine(to: CGPoint(x: -W/2 + vw(48), y: skPt.y))
            }
            pair.line.path = linePath
            pair.label.position = CGPoint(x: pair.zone.dir > 0 ? -W/2 + vw(90) : W/2 - vw(90),
                                           y: skPt.y + vh(10))
        }

        for i in cobwebNodes.indices {
            let cw   = cobwebNodes[i].data
            let cwVY = cw.depth - descentProg + 240
            let skPt = vs(cw.x, cwVY)
            let visible = cwVY > -60 && cwVY < 540 && !cobwebs[i].cleared

            cobwebNodes[i].shape.isHidden = !visible
            guard visible else { continue }

            let r = vw(cw.radius)
            let webPath = CGMutablePath()
            var ring: CGFloat = vw(5)
            while ring <= r {
                webPath.addEllipse(in: CGRect(x: skPt.x - ring, y: skPt.y - ring * 0.6,
                                               width: ring*2, height: ring*1.2))
                ring += vw(8)
            }
            for spoke in 0..<8 {
                let angle = CGFloat(spoke) * .pi / 4
                webPath.move(to:    skPt)
                webPath.addLine(to: CGPoint(x: skPt.x + cos(angle)*r, y: skPt.y + sin(angle)*r*0.6))
            }
            cobwebNodes[i].shape.path = webPath
        }
    }

    private func updateWallScroll() {
        let wallW = vw(48)
        let lx    = -W / 2 + wallW / 2
        let rx    =  W / 2 - wallW / 2

        let offset = descentProg.truncatingRemainder(dividingBy: wallTileH)
        let y0 = offset - wallTileH
        let y1 = offset

        wL1.position = CGPoint(x: lx, y: y0); wL1.xScale =  1
        wL2.position = CGPoint(x: lx, y: y1); wL2.xScale =  1
        wR1.position = CGPoint(x: rx, y: y0); wR1.xScale = -1
        wR2.position = CGPoint(x: rx, y: y1); wR2.xScale = -1
    }

    // MARK: - Fling result
    private func flingEnded(pts: Int, msg: String) {
        score += pts; totalFlings += 1
        if pts > 0 { accurateHits += 1 }
        bagsLeft -= 1
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "wellFlinger_high_v1")
        }
        updateHUD()
        showToast(msg)

        run(.sequence([
            .wait(forDuration: 1.8),
            .run { [weak self] in
                guard let self else { return }
                if self.bagsLeft > 0 {
                    self.bagSprite.alpha = 1; self.bagSprite.setScale(1)
                    self.initLaunchPhase()
                } else {
                    self.showGameOver()
                }
            },
        ]))
    }

    // MARK: - Game over panel
    private func showGameOver() {
        applyPhaseVisibility(.gameOver)
        let accuracy = totalFlings > 0 ? Int(Double(accurateHits) / Double(totalFlings) * 100) : 0

        let font = "PressStart2P-Regular"
        let panelW = W * 0.82; let panelH = H * 0.55
        let panel  = SKNode(); panel.zPosition = 80

        let bg = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: vw(12))
        bg.fillColor   = SKColor(red: 0.063, green: 0.024, blue: 0.012, alpha: 0.97)
        bg.strokeColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 0.6)
        bg.lineWidth   = 2; panel.addChild(bg)

        func lbl(_ txt: String, sz: CGFloat, color: SKColor, y: CGFloat) -> SKLabelNode {
            let l = SKLabelNode(fontNamed: font); l.text = txt; l.fontSize = sz
            l.fontColor = color; l.horizontalAlignmentMode = .center
            l.verticalAlignmentMode = .center; l.position = CGPoint(x: 0, y: y); return l
        }
        panel.addChild(lbl("GAME OVER",  sz: vw(16), color: .red,    y:  panelH * 0.32))
        panel.addChild(lbl("ALL BAGS FLUNG!", sz: vw(5.5), color: SKColor(white:0.55,alpha:1), y: panelH * 0.20))

        panel.addChild(lbl("SCORE", sz: vw(7), color: SKColor(white:0.55,alpha:1), y: panelH * 0.07))
        panel.addChild(lbl(String(format: "%04d", score), sz: vw(20), color: .yellow, y: -panelH * 0.07))

        panel.addChild(lbl("ACCURACY   \(accuracy)%", sz: vw(6),
                            color: SKColor(red:0.2,green:0.8,blue:0.9,alpha:1), y: -panelH * 0.22))
        panel.addChild(lbl("BEST   \(String(format: "%04d", highScore))", sz: vw(6),
                            color: SKColor(red:0.2,green:0.9,blue:0.4,alpha:1), y: -panelH * 0.32))

        let btnBg = SKShapeNode(rectOf: CGSize(width: panelW * 0.7, height: vh(44)), cornerRadius: vw(8))
        btnBg.fillColor   = SKColor(red: 0.0, green: 0.627, blue: 0.784, alpha: 1)
        btnBg.strokeColor = SKColor(red: 0.4, green: 0.85, blue: 1.0, alpha: 1)
        btnBg.lineWidth   = 3; btnBg.position = CGPoint(x: 0, y: -panelH * 0.44)
        btnBg.name        = "playAgain"; panel.addChild(btnBg)

        let btnLbl = SKLabelNode(fontNamed: font)
        btnLbl.text = "PLAY AGAIN"; btnLbl.fontSize = vw(9); btnLbl.fontColor = .black
        btnLbl.horizontalAlignmentMode = .center; btnLbl.verticalAlignmentMode = .center
        btnLbl.name = "playAgain"; btnBg.addChild(btnLbl)

        addChild(panel)
    }

    // MARK: - Bag visual update (called every frame)
    private func updateBagVisual() {
        guard phase != .gameOver else { return }

        if physicsActive { return }

        var skPos = vs(bVX, bVY)
        let altScale: CGFloat

        switch phase {
        case .launch, .zoomIn:
            altScale  = 1.0 + launchBZ * 0.012
            skPos.y  += launchBZ * 0.50
        default:
            altScale  = 1.0
        }

        let sideLen = vw(bSz) * altScale

        bagSprite.size      = CGSize(width: sideLen, height: sideLen)
        bagSprite.position  = skPos
        bagSprite.zRotation = bRot

        if phase == .landing && bZ > 0 {
            let off     = vw(bZ * 0.05)
            let opacity = max(0.1, CGFloat(0.5 - bZ * 0.002))
            bagShadow.size     = CGSize(width: sideLen, height: sideLen * 0.7)
            bagShadow.position = CGPoint(x: skPos.x + off, y: skPos.y - off * 0.5)
            bagShadow.alpha    = opacity
        }
    }

    // MARK: - Spark particles
    private func spawnSparks(at pos: CGPoint, color: SKColor, count: Int) {
        for _ in 0..<count {
            let s = SKShapeNode(rectOf: CGSize(width: vw(2), height: vw(2)))
            s.fillColor = color; s.strokeColor = .clear
            s.position = pos; s.zPosition = 55
            sparkLayer.addChild(s)
            let dvx = CGFloat.random(in: -vw(3)...vw(3))
            let dvy = CGFloat.random(in: -vh(3)...vh(3))
            s.run(.sequence([
                .group([
                    .moveBy(x: dvx * 5, y: dvy * 5, duration: 0.4),
                    .fadeOut(withDuration: 0.4),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        if let overlay = TutorialOverlay.active(in: self) { overlay.advance(); return }
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        if nodes(at: loc).contains(where: { $0.name == "pauseBtn"    }) { return }
        if nodes(at: loc).contains(where: { $0.name == "closeButton" }) { dismiss(); return }

        if phase == .gameOver {
            if nodes(at: loc).contains(where: { $0.name == "playAgain" }) {
                removeAllActions()
                bagSprite.removeAllActions()
                children.filter { $0.zPosition == 80 }.forEach { $0.removeFromParent() }
                startGame()
            }
            return
        }

        if phase == .launch {
            touchStart = loc
            let line = SKShapeNode()
            line.strokeColor = SKColor(white: 1, alpha: 0.45)
            line.lineWidth = 1; line.zPosition = 400
            addChild(line)
            aimingLine = line
        }

        if phase == .descent || phase == .landing {
            isSteering = true; steerRefX = loc.x; steerRefY = loc.y
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        if phase == .launch, let start = touchStart {
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: loc)
            aimingLine?.path = path
            hintLbl.isHidden = true
        }

        if (phase == .descent || phase == .landing) && isSteering {
            let dx = loc.x - steerRefX
            let dy = loc.y - steerRefY
            tiltX = max(-1, min(1,  dx / vw(45)))
            tiltY = max(-1, min(1, -dy / vh(45)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        if phase == .launch, let start = touchStart {
            touchStart = nil
            aimingLine?.removeFromParent(); aimingLine = nil
            let dx = loc.x - start.x
            let dy = loc.y - start.y
            if hypot(dx, dy) > 10 {
                bVelX    =  dx * (320 / W) * launchPowerScale
                bVelY    = -dy * (480 / H) * launchPowerScale
                bRotV    = CGFloat.random(in: 0.1...0.3)
                launchBVZ = launchVZInitial
                spawnSparks(at: vs(bVX, bVY), color: .white, count: 12)
                playLaunch()
                HapticsManager.shared.lightImpact()
            }
            hintLbl.isHidden = false
        }

        if phase == .descent || phase == .landing {
            isSteering = false; tiltX = 0; tiltY = 0
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Helpers

    private func dismiss() {
        onComplete?(false)
        if let prev = previousScene {
            prev.isPaused = false
            let t = SKTransition.push(with: .down, duration: 0.35)
            t.pausesOutgoingScene = false
            view?.presentScene(prev, transition: t)
        }
    }

    // MARK: - Audio
    private func playSound(_ name: String) {
        run(.playSoundFileNamed(name, waitForCompletion: false))
    }

    private func playLaunch()    { playSound("hit.mp3") }
    private func playHoleEnter() { playSound("hole_score.wav") }
    private func playHoleScore() { playSound("hole_score.wav") }
    private func playHitBoard()  { playSound("hit.mp3") }
    private func playBounce()    { playSound("hit.mp3") }
    private func playMiss()      { playSound("round_end.wav") }
    private func playWind()      { /* no suitable file — skip */ }
}


