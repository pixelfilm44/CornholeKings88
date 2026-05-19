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
    private var closeUIButton: UIButton? = nil  // unused; SK close button replaces UIKit
    /// Honey bags from inventory injected by GameScene before presenting.
    var availableHoneyBags: Int = 0
    /// How many honey bags the player actually used this match (consumed from inventory).
    private(set) var honeyBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a honey bag on the next throw.
    private var honeyBagSelected = false
    /// Bomb bags from inventory injected by GameScene before presenting.
    var availableBombBags: Int = 0
    /// How many bomb bags the player actually used this match (consumed from inventory).
    private(set) var bombBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a bomb bag on the next throw.
    private var bombBagSelected = false
    /// Bomb bags earned this match (awarded on Billy win); read by GameScene after onComplete.
    private(set) var bombBagsEarned: Int = 0
    /// Magic bags from inventory injected by GameScene before presenting.
    var availableMagicBags: Int = 0
    /// How many magic bags the player actually used this match (consumed from inventory).
    private(set) var magicBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a magic bag on the next throw.
    private var magicBagSelected = false
    /// Magic bags earned this match (awarded on Tree Spirit win); read by GameScene after onComplete.
    private(set) var magicBagsEarned: Int = 0
    /// Fire bags from inventory injected by GameScene before presenting.
    var availableFireBags: Int = 0
    /// How many fire bags the player actually used this match (consumed from inventory).
    private(set) var fireBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a fire bag on the next throw.
    private var fireBagSelected = false
    /// Fire bags earned this match; read by GameScene after onComplete.
    private(set) var fireBagsEarned: Int = 0
    /// Golden bags from inventory injected by GameScene before presenting.
    var availableGoldenBags: Int = 0
    /// How many golden bags the player actually used this match (consumed from inventory).
    private(set) var goldenBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a golden bag on the next throw.
    private var goldenBagSelected = false

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
        /// Honey bags (won from BeeHive Battle) stick to the board — immune to wind and bag collisions.
        var isHoney = false
        /// Bomb bags destroy opponent bags on the board or in the hole on landing.
        var isBomb = false
        /// Prevents the bomb explosion from firing more than once.
        var hasBombed = false
        /// Magic bags destroy the specific opponent bag they physically collide with on the board;
        /// scoring in the hole destroys all opponent bags already in the hole this round.
        var isMagic = false
        /// Fire bags burn all board bags when they land (thrower keeps 1 pt); burn all hole bags when scored.
        var isFire = false
        /// Prevents the fire effect from triggering more than once per bag.
        var hasTriggeredFire = false
        /// Golden bags score 2 pts on board and 6 pts in hole. Fully immune to all magic bag effects.
        var isGolden = false
        /// Bags marked destroyed are removed from scoring but kept in activeBags until the round ends.
        var isDestroyed = false

        let node: SKSpriteNode
        let shadow: SKSpriteNode

        init(owner: BagOwner, startX: CGFloat, startY: CGFloat,
             isHoney: Bool = false, isBomb: Bool = false, isMagic: Bool = false,
             isFire: Bool = false, isGolden: Bool = false) {
            self.owner    = owner
            self.bx = startX; self.by = startY; self.bz = 3
            self.vx = 0; self.vy = 0; self.vz = 0
            self.isHoney  = isHoney
            self.isBomb   = isBomb
            self.isMagic  = isMagic
            self.isFire   = isFire
            self.isGolden = isGolden

            let goldenColor = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
            let playerColor: SKColor
            if isGolden {
                playerColor = goldenColor
            } else if isBomb {
                playerColor = SKColor(red: 0.08, green: 0.06, blue: 0.06, alpha: 1)
            } else if isMagic {
                playerColor = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1)
            } else if isFire {
                playerColor = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
            } else if isHoney {
                playerColor = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
            } else {
                playerColor = SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
            }
            let aiColor: SKColor
            if isGolden {
                aiColor = goldenColor
            } else if isBomb {
                aiColor = SKColor(red: 0.12, green: 0.04, blue: 0.18, alpha: 1)
            } else if isMagic {
                aiColor = SKColor(red: 0.18, green: 0.90, blue: 0.42, alpha: 1)
            } else if isFire {
                aiColor = SKColor(red: 0.90, green: 0.22, blue: 0.02, alpha: 1)
            } else {
                aiColor = SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1)
            }

            let bagTex = SKTexture(imageNamed: "bag_16bit")
            bagTex.filteringMode = .nearest
            node = SKSpriteNode(texture: bagTex, size: CGSize(width: 50, height: 50))
            node.color            = owner == .player ? playerColor : aiColor
            node.colorBlendFactor = (isBomb || isMagic || isFire || isGolden) ? 0.88 : 0.65
            node.zPosition        = 20

            // Skull marker on bomb bags
            if isBomb {
                let skull = SKLabelNode(text: "☠")
                skull.fontSize                = 14
                skull.verticalAlignmentMode   = .center
                skull.horizontalAlignmentMode = .center
                skull.position  = .zero
                skull.zPosition = 1
                node.addChild(skull)
            }
            // Sparkle marker on magic bags
            if isMagic {
                let sparkle = SKLabelNode(text: "✦")
                sparkle.fontSize                = 14
                sparkle.fontColor               = SKColor(red: 0.90, green: 1.0, blue: 0.70, alpha: 1)
                sparkle.verticalAlignmentMode   = .center
                sparkle.horizontalAlignmentMode = .center
                sparkle.position  = .zero
                sparkle.zPosition = 1
                node.addChild(sparkle)
                // Gentle pulse so magic bags are obvious in flight
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.65, duration: 0.35),
                    SKAction.fadeAlpha(to: 1.00, duration: 0.35),
                ])))
            }
            // Flame marker on fire bags
            if isFire {
                let flame = SKLabelNode(text: "🔥")
                flame.fontSize                = 13
                flame.verticalAlignmentMode   = .center
                flame.horizontalAlignmentMode = .center
                flame.position  = .zero
                flame.zPosition = 1
                node.addChild(flame)
                // Flicker so fire bags are obvious in flight
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.70, duration: 0.18),
                    SKAction.fadeAlpha(to: 1.00, duration: 0.18),
                ])))
            }
            // Star marker on golden bags
            if isGolden {
                let star = SKLabelNode(text: "★")
                star.fontSize                = 15
                star.fontColor               = SKColor(white: 1.0, alpha: 0.90)
                star.verticalAlignmentMode   = .center
                star.horizontalAlignmentMode = .center
                star.position  = .zero
                star.zPosition = 1
                node.addChild(star)
                // Shimmer pulse so golden bags stand out clearly
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.colorize(with: SKColor(red: 1.0, green: 1.0, blue: 0.6, alpha: 1),
                                      colorBlendFactor: 0.50, duration: 0.30),
                    SKAction.colorize(withColorBlendFactor: 0.88, duration: 0.30),
                ])))
            }

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
    private var crowY:      CGFloat = 0

    // MARK: - Physics constants
    private let gravityPerFrame: CGFloat = 0.50
    private let vzInitial:       CGFloat = 15.0

    // MARK: - Game state
    private var gameState: State = .playerTurn
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var activeBags: [MiniGameBag] = []
    private var playerBagsThrown = 0
    private var aiBagsThrown     = 0
    private let bagsPerPlayer    = 4
    private var winScore         = 11
    private var playerScore      = 0
    private var aiScore          = 0
    private var lastThrower: BagOwner = .ai
    private var hasCalculatedScore = false

    // Fire bag round state — reset each round
    private var boardOnFire = false   // board burns subsequent bags that land on it
    private var holeFire    = false   // subsequent cornholes this round are destroyed
    private var fireBoardOverlay: SKSpriteNode?

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

    // Thunderstorm scenario — mutually exclusive with rain; rolled once per game
    private var stormActive      = false
    private var stormStartRound  = -1
    private var stormEndRound    = Int.max
    private var stormDarkOverlay: SKSpriteNode?
    private var stormParticleNode: SKNode?
    private var stormFlashOverlay: SKSpriteNode?
    private var stormAudioNode:   SKAudioNode?

    // Tom's fart ability — 50% chance per round; green fog + faster/wobbling indicator
    private var tomFartActive    = false
    private var tomFartOverlay:  SKNode?
    private var fartBaseSpeed:   CGFloat = 0  // saved targetSpeed before doubling
    private var fartWobbleTimer: CGFloat = 0

    // Gopher — only one alive at a time; chases the throw-line bag and steals it
    private var activeGopher: GopherNode?
    private let gopherSpawnChance: Double = 0.15   // 15% per turn
    // Pre-committed AI start position so the gopher can race toward it.
    // Set when the AI's turn begins; consumed by aiThrow().
    private var pendingAIStartX: CGFloat = 0

    // Crow — occasionally flies through the bag-flight corridor below the board
    private var crowNode: SKNode?
    private var crowFlyingRight = true

    // Opponent selection
    enum AIOpponent { case tom, jenny, billy, spirit }
    /// Set before presenting to skip the picker and start with a specific opponent.
    var preSelectedOpponent: AIOpponent? = nil
    private var selectedOpponent: AIOpponent = .tom
    private var opponentPortrait: SKSpriteNode?
    private var opponentName: String {
        switch selectedOpponent {
        case .tom:    return "TOM"
        case .jenny:  return "JENNY"
        case .billy:  return "BILLY"
        case .spirit: return "SPIRIT"
        }
    }

    // Billy the Bully — adaptive difficulty state
    private var billyNoiseFactor: CGFloat  = 2.5  // lower = harder; adapts each round
    private var billyBombBagsRemaining: Int = 0   // bomb bags Billy can throw this match

    // Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // Quit-confirm state (tutorial state is owned by TutorialOverlay itself)
    private var confirmingQuit   = false
    private var confirmPanel:  SKNode?

    // MARK: - Node references
    private var gameWorldNode: SKEffectNode!
    private var turnIndicator: SKSpriteNode?
    private var playerScoreLabel: SKLabelNode?
    private var aiScoreLabel:     SKLabelNode?
    private var windLabel:        SKLabelNode?
    private var messageNode: SKNode?
    private var satchelButton: SKNode?
    private var satchelPanel: SKNode?
    private var satchelOpen = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        preloadAssets()
        computeLayout()
        setupGameWorld()
        setupBoard()
        setupUI()
        // Picker → tutorial → startRound
        showOpponentPicker()
    }

    override func willMove(from view: SKView) { }

    private func preloadAssets() {
        // Force textures into GPU memory so the first bag throw doesn't stutter
        let textures = ["bag_16bit", "board_16bit"].map { name -> SKTexture in
            let t = SKTexture(imageNamed: name)
            t.filteringMode = .nearest
            return t
        }
        SKTexture.preload(textures) { }

        // Warm up AVAudioEngine (shared with playSoundFileNamed) by playing each
        // sound once at volume 0. Guard against missing files — SKAudioNode crashes
        // hard on a missing file while playSoundFileNamed silently no-ops.
        let sounds = ["hit.mp3",      "hole_score.wav", "round_end.wav",
                      "rain_start.wav", "gopher_pop.wav", "gopher_steal.wav",
                      "game_win.wav",  "game_lose.wav",  "storm.mp3",
                      "fart.wav"]   // Tom's toot — asset optional; skipped if absent
        sounds.forEach { warmUpSound($0) }
    }

    private func warmUpSound(_ filename: String) {
        let base = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        guard Bundle.main.url(forResource: base, withExtension: ext) != nil else { return }
        let audio = SKAudioNode(fileNamed: filename)
        audio.autoplayLooped = false
        audio.isPositional   = false
        addChild(audio)
        audio.run(SKAction.sequence([
            SKAction.changeVolume(to: 0, duration: 0),
            SKAction.play(),
            SKAction.wait(forDuration: 0.05),
            SKAction.run { [weak audio] in audio?.removeFromParent() },
        ]))
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
        fartBaseSpeed = targetSpeed

        // powerScale chosen so a 38% screen-height swipe lands near the hole
        let distToHole   = abs(holeCenter.y - throwLineY)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 100 frames
        let idealSwipe   = size.height * 0.38
        powerScale = distToHole / (flightFrames * idealSwipe)

        // Crow intercept corridor: 60% of the way from throw line to board's lower edge
        crowY = throwLineY + (boardY - boardHalfH - throwLineY) * 0.60
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

        // Grass background — slightly brightened for outdoor daylight feel
        let bg = SKSpriteNode(color: SKColor(red: 0.18, green: 0.38, blue: 0.13, alpha: 1),
                              size: CGSize(width: size.width * 2, height: size.height * 2))
        bg.zPosition = -200
        gameWorldNode.addChild(bg)

        // Warm sunlight wash — subtle yellow-gold tint. Added to scene (not gameWorldNode)
        // to avoid SKEffectNode render-bounds expansion.
        let sunGlow = SKSpriteNode(color: SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 0.11),
                                   size: CGSize(width: size.width * 2, height: size.height * 2))
        sunGlow.zPosition = 60   // above gameplay, below chrome (500)
        addChild(sunGlow)

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
        boardContainer.setScale(0.90)   // visual-only shrink; hit zone uses unscaled values
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
        // Bit-Wood Brawler design-system colors
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
        let dsIronGray = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1) // #595959

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat    = 48
        let bottomH: CGFloat = max(40, size.height * 0.08)
        // Panel sits immediately below the safe-area inset (Dynamic Island / notch)
        let panelTopY = size.height / 2 - topInset
        let topBarY   = panelTopY - topH / 2
        let botBarY   = -size.height / 2 + bottomH / 2

        // ── Top HUD ribbon ────────────────────────────────────────────────
        // Extend the background up through the safe-area inset so the notch stays dark
        let totalTopH = topH + topInset
        let topBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: size.width, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: size.height / 2 - totalTopH / 2)
        topBar.zPosition = 500
        addChild(topBar)

        // 2px gold bottom border at the bottom edge of the visible 48pt ribbon
        let topBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: size.width, height: 2))
        topBorder.position  = CGPoint(x: 0, y: topBarY - topH / 2)
        topBorder.zPosition = 501
        addChild(topBorder)

        // Zone A (left): pause icon
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size     = CGSize(width: 22, height: 22)
        pauseBtn.position = CGPoint(x: -size.width / 2 + 22, y: topBarY)
        pauseBtn.zPosition = 502
        pauseBtn.name     = "pauseBtn"
        addChild(pauseBtn)

        // Tutorial help button just right of pause
        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -size.width / 2 + 52, y: topBarY)
        addChild(help)

        // Zone B (center): combined score label
        let scoreLabel = makeLabel(text: "YOU: 0 | OPP: 0", size: 9, color: dsGold)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.position  = CGPoint(x: 0, y: topBarY)
        scoreLabel.zPosition = 502
        addChild(scoreLabel)
        playerScoreLabel = scoreLabel

        // Zone C (right): SK close button using closeIcon image
        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: size.width / 2 - 22, y: topBarY)
        closeBtn.zPosition = 502
        closeBtn.name      = "closeButton"
        addChild(closeBtn)

        // Iron bolts — corners of the visible 48pt ribbon
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: topBarY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: topBarY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: topBarY - topH / 2 + 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: topBarY - topH / 2 + 5), color: dsIronGray)

        // ── Bottom bar ────────────────────────────────────────────────────
        let botBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: size.width, height: bottomH))
        botBar.position  = CGPoint(x: 0, y: botBarY)
        botBar.zPosition = 500
        addChild(botBar)

        // 2px gold top border
        let botBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: size.width, height: 2))
        botBorder.position  = CGPoint(x: 0, y: botBarY + bottomH / 2)
        botBorder.zPosition = 501
        addChild(botBorder)

        // Weather / wind — centered, gold
        let wLabel = makeLabel(text: "CALM", size: 9, color: dsGold)
        wLabel.horizontalAlignmentMode = .center
        wLabel.position  = CGPoint(x: 0, y: botBarY)
        wLabel.zPosition = 502
        addChild(wLabel)
        windLabel = wLabel

        // Round bag counters — left and right
        let rndPLabel = makeLabel(text: "", size: 9,
                                  color: SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1))
        rndPLabel.horizontalAlignmentMode = .left
        rndPLabel.position  = CGPoint(x: -size.width / 2 + 14, y: botBarY)
        rndPLabel.zPosition = 502
        rndPLabel.name = "rndPlayerLabel"
        addChild(rndPLabel)

        let rndALabel = makeLabel(text: "", size: 9,
                                  color: SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        rndALabel.horizontalAlignmentMode = .right
        rndALabel.position  = CGPoint(x: size.width / 2 - 8, y: botBarY)
        rndALabel.zPosition = 502
        rndALabel.name = "rndAILabel"
        addChild(rndALabel)

        // Iron bolts — bottom corners
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: botBarY + bottomH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: botBarY + bottomH / 2 - 5), color: dsIronGray)

        // ── Turn indicator ─────────────────────────────────────────────────
        let indTex = SKTexture(imageNamed: "bag_16bit")
        indTex.filteringMode = .nearest
        let indicator = SKSpriteNode(texture: indTex, size: CGSize(width: 50, height: 50))
        indicator.color            = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        indicator.colorBlendFactor = 0.65
        indicator.position  = CGPoint(x: 0, y: throwLineY)
        indicator.zPosition = 30
        gameWorldNode.addChild(indicator)
        turnIndicator = indicator

        indicator.run(SKAction.repeatForever(.sequence([
            .scale(to: 1.18, duration: 0.55),
            .scale(to: 1.00, duration: 0.55),
        ])))

        setupSatchelButton()
        addCrtOverlay()
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
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: w, height: h))
        overlay.position  = .zero
        overlay.zPosition = 800
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
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
        lbl.fontSize = 10
        lbl.fontColor = fg
        lbl.text = label
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.zPosition = 1
        n.addChild(lbl)
        return n
    }

    // MARK: - Satchel

    /// Returns the special bag types the player currently has available for cornhole.
    private var satchelItems: [(type: ItemType, count: Int)] {
        [(type: .honeyBag,  count: availableHoneyBags),
         (type: .bombBag,   count: availableBombBags),
         (type: .magicBag,  count: availableMagicBags),
         (type: .fireBag,   count: availableFireBags),
         (type: .goldenBag, count: availableGoldenBags)]
            .filter { $0.count > 0 }
    }

    private func isItemSelected(_ type: ItemType) -> Bool {
        switch type {
        case .honeyBag:  return honeyBagSelected
        case .bombBag:   return bombBagSelected
        case .magicBag:  return magicBagSelected
        case .fireBag:   return fireBagSelected
        case .goldenBag: return goldenBagSelected
        default:         return false
        }
    }

    /// Pixel-art satchel icon button in the lower-right corner above the bottom chrome.
    /// Visible whenever the player carries at least one special bag.
    private func setupSatchelButton() {
        let bottomH: CGFloat = max(40, size.height * 0.08)
        let iconW: CGFloat = 38, iconH: CGFloat = 36

        let btn = SKNode()
        btn.name      = "satchelButton"
        btn.position  = CGPoint(x: size.width / 2 - iconW / 2 - 8,
                                y: -size.height / 2 + bottomH + iconH / 2 + 6)
        btn.zPosition = 600

        // Pouch body
        let body = SKSpriteNode(color: SKColor(red: 0.28, green: 0.15, blue: 0.05, alpha: 0.95),
                                size: CGSize(width: iconW, height: iconH))
        body.zPosition = 0
        btn.addChild(body)

        // Flap (upper portion, slightly lighter)
        let flap = SKSpriteNode(color: SKColor(red: 0.44, green: 0.25, blue: 0.08, alpha: 1.0),
                                size: CGSize(width: iconW, height: iconH * 0.38))
        flap.position = CGPoint(x: 0, y: iconH * 0.31)
        flap.zPosition = 1
        btn.addChild(flap)

        // Clasp — gold square centred on the flap
        let clasp = SKSpriteNode(color: SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0),
                                 size: CGSize(width: 8, height: 6))
        clasp.position = CGPoint(x: 0, y: iconH * 0.31)
        clasp.zPosition = 2
        btn.addChild(clasp)

        // Item-count badge at the bottom of the body
        let countTotal = satchelItems.reduce(0) { $0 + $1.count }
        let badge = SKLabelNode(fontNamed: "PressStart2P-Regular")
        badge.name                   = "satchelCountBadge"
        badge.fontSize               = 7
        badge.fontColor              = SKColor(white: 0.90, alpha: 1)
        badge.text                   = "×\(countTotal)"
        badge.verticalAlignmentMode  = .center
        badge.horizontalAlignmentMode = .center
        badge.position               = CGPoint(x: 0, y: -iconH * 0.28)
        badge.zPosition              = 3
        btn.addChild(badge)

        // Selected-item indicator dot (hidden until something is armed)
        let dot = SKSpriteNode(color: .clear, size: CGSize(width: 8, height: 8))
        dot.name      = "satchelSelectedDot"
        dot.position  = CGPoint(x: iconW / 2 - 5, y: -iconH / 2 + 5)
        dot.zPosition = 4
        btn.addChild(dot)

        btn.isHidden = satchelItems.isEmpty
        addChild(btn)
        satchelButton = btn
    }

    /// Syncs the satchel button appearance with current selection / count state.
    private func updateSatchelButton() {
        guard let btn = satchelButton else { return }

        if satchelItems.isEmpty {
            honeyBagSelected  = false
            bombBagSelected   = false
            magicBagSelected  = false
            fireBagSelected   = false
            goldenBagSelected = false
            closeSatchelPanel()
            btn.isHidden = true
            return
        }
        btn.isHidden = false

        // Update count badge
        let countTotal = satchelItems.reduce(0) { $0 + $1.count }
        (btn.childNode(withName: "satchelCountBadge") as? SKLabelNode)?.text = "×\(countTotal)"

        // Selected indicator dot: coloured when something is armed, clear otherwise
        let dot = btn.childNode(withName: "satchelSelectedDot") as? SKSpriteNode
        if honeyBagSelected {
            dot?.color = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0)  // amber
        } else if bombBagSelected {
            dot?.color = SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1.0)  // red
        } else if magicBagSelected {
            dot?.color = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1.0)  // green
        } else if fireBagSelected {
            dot?.color = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1.0)  // orange-red
        } else if goldenBagSelected {
            dot?.color = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1.0)  // bright gold
        } else {
            dot?.color = .clear
        }
    }

    /// Opens a panel anchored to the right side; slides up from below and stays open
    /// until the user taps the X button. Tapping a bag arms it as the active bag type.
    private func openSatchelPanel() {
        closeSatchelPanel()
        guard !satchelItems.isEmpty else { return }
        satchelOpen = true

        let rowH: CGFloat    = 44
        let panelW: CGFloat  = min(size.width * 0.52, 190)
        let titleH: CGFloat  = 32
        let padding: CGFloat = 10
        let panelH           = titleH + rowH * CGFloat(satchelItems.count) + padding * 2

        // Anchor just above the satchel button in the bottom-right corner.
        let bottomH: CGFloat = max(40, size.height * 0.08)
        let iconH:   CGFloat = 36
        let btnTopY  = -size.height / 2 + bottomH + iconH + 6   // top edge of satchel button
        let finalY   = btnTopY + 6 + panelH / 2                 // panel sits 6 pt above button
        let startY   = finalY - 12                              // rises 12 pt on open
        let panelX   = size.width / 2 - panelW / 2 - 8         // right-aligned

        let panel = SKNode()
        panel.name      = "satchelPanel"
        panel.position  = CGPoint(x: panelX, y: startY)
        panel.zPosition = 650
        addChild(panel)
        satchelPanel = panel

        // Dark backing — named so stray taps on it are swallowed
        let bg = SKSpriteNode(color: SKColor(red: 0.06, green: 0.03, blue: 0.01, alpha: 0.97),
                              size: CGSize(width: panelW, height: panelH))
        bg.name      = "satchelPanelBg"
        bg.zPosition = 0
        panel.addChild(bg)

        // Gold border
        let border = SKShapeNode(rectOf: CGSize(width: panelW + 2, height: panelH + 2),
                                 cornerRadius: 3)
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 2
        border.zPosition   = 1
        panel.addChild(border)

        let fs = max(7, size.width * 0.038)
        let titleY = panelH / 2 - padding - titleH / 2

        // Title label (left-of-centre to leave room for X)
        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.fontSize                = fs * 0.68
        title.fontColor               = SKColor(red: 0.95, green: 0.75, blue: 0.38, alpha: 1)
        title.text                    = "BAGS"
        title.verticalAlignmentMode   = .center
        title.horizontalAlignmentMode = .left
        title.position  = CGPoint(x: -panelW / 2 + 10, y: titleY)
        title.zPosition = 2
        panel.addChild(title)

        // X close button — top-right of title bar
        let xBtn = SKNode()
        xBtn.name      = "satchelCloseBtn"
        xBtn.position  = CGPoint(x: panelW / 2 - 16, y: titleY)
        xBtn.zPosition = 3
        panel.addChild(xBtn)

        let xBg = SKSpriteNode(color: SKColor(red: 0.28, green: 0.08, blue: 0.04, alpha: 0.85),
                               size: CGSize(width: 22, height: 22))
        xBg.zPosition = 0
        xBtn.addChild(xBg)

        let xPath = CGMutablePath()
        let xi: CGFloat = 5
        xPath.move(to: CGPoint(x: -xi, y: -xi)); xPath.addLine(to: CGPoint(x: xi, y:  xi))
        xPath.move(to: CGPoint(x:  xi, y: -xi)); xPath.addLine(to: CGPoint(x: -xi, y: xi))
        let xShape = SKShapeNode(path: xPath)
        xShape.strokeColor = SKColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1)
        xShape.lineWidth   = 2
        xShape.lineCap     = .round
        xShape.zPosition   = 1
        xBtn.addChild(xShape)

        // Divider below title
        let divider = SKSpriteNode(color: SKColor(red: 0.50, green: 0.35, blue: 0.15, alpha: 0.55),
                                   size: CGSize(width: panelW - 12, height: 1))
        divider.position  = CGPoint(x: 0, y: panelH / 2 - padding - titleH)
        divider.zPosition = 2
        panel.addChild(divider)

        // One row per item
        let rowsTop = panelH / 2 - padding - titleH - rowH / 2
        for (idx, item) in satchelItems.enumerated() {
            let rowY = rowsTop - rowH * CGFloat(idx)
            let row  = SKNode()
            row.name      = "satchelItem_\(item.type.rawValue)"
            row.position  = CGPoint(x: 0, y: rowY)
            row.zPosition = 2
            panel.addChild(row)

            let isSelected = isItemSelected(item.type)
            let selColor: SKColor
            let checkColor: SKColor
            switch item.type {
            case .bombBag:
                selColor   = SKColor(red: 0.28, green: 0.04, blue: 0.04, alpha: 0.90)
                checkColor = SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1)
            case .magicBag:
                selColor   = SKColor(red: 0.04, green: 0.28, blue: 0.10, alpha: 0.90)
                checkColor = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1)
            case .fireBag:
                selColor   = SKColor(red: 0.28, green: 0.06, blue: 0.01, alpha: 0.90)
                checkColor = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
            default:
                selColor   = SKColor(red: 0.28, green: 0.18, blue: 0.04, alpha: 0.90)
                checkColor = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
            }
            let rowBg = SKSpriteNode(
                color: isSelected ? selColor : SKColor(white: 1, alpha: 0.04),
                size: CGSize(width: panelW - 8, height: rowH - 6))
            rowBg.name      = "satchelRowBg_\(item.type.rawValue)"
            rowBg.zPosition = 0
            row.addChild(rowBg)

            // Selection circle
            let check = SKShapeNode(circleOfRadius: 6)
            check.name        = "satchelCheck_\(item.type.rawValue)"
            check.strokeColor = isSelected ? checkColor : SKColor(white: 0.45, alpha: 1)
            check.fillColor   = isSelected ? checkColor.withAlphaComponent(0.30) : .clear
            check.lineWidth   = 1.5
            check.position    = CGPoint(x: -panelW / 2 + 16, y: 0)
            check.zPosition   = 1
            row.addChild(check)

            // Coloured bag icon
            let icon = SKSpriteNode(color: item.type.color, size: CGSize(width: 11, height: 11))
            icon.position  = CGPoint(x: -panelW / 2 + 34, y: 0)
            icon.zPosition = 1
            row.addChild(icon)

            // Name + count
            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.name                    = "satchelLbl_\(item.type.rawValue)"
            lbl.fontSize                = fs * 0.60
            lbl.fontColor               = isSelected ? SKColor(white: 1.0, alpha: 1) : SKColor(white: 0.80, alpha: 1)
            lbl.text                    = "\(item.type.displayName) ×\(item.count)"
            lbl.verticalAlignmentMode   = .center
            lbl.horizontalAlignmentMode = .left
            lbl.position                = CGPoint(x: -panelW / 2 + 48, y: 0)
            lbl.zPosition               = 1
            row.addChild(lbl)
        }

        // Pop up from just below its resting position
        panel.alpha = 0
        let rise = SKAction.move(to: CGPoint(x: panelX, y: finalY), duration: 0.15)
        rise.timingMode = .easeOut
        panel.run(SKAction.group([.fadeIn(withDuration: 0.15), rise]))
    }

    /// Fades the panel out with a short drop then removes it.
    private func closeSatchelPanel() {
        satchelOpen = false

        if let panel = satchelPanel {
            satchelPanel = nil
            let drop = SKAction.moveBy(x: 0, y: -8, duration: 0.12)
            drop.timingMode = .easeIn
            panel.run(SKAction.sequence([
                SKAction.group([drop, .fadeOut(withDuration: 0.12)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Updates row visuals and counts in-place to reflect the current selection and inventory state.
    private func refreshSatchelPanelRows() {
        guard let panel = satchelPanel else { return }
        let allItems: [(type: ItemType, count: Int)] = [
            (.honeyBag,  availableHoneyBags),
            (.bombBag,   availableBombBags),
            (.magicBag,  availableMagicBags),
            (.fireBag,   availableFireBags),
            (.goldenBag, availableGoldenBags),
        ]
        for item in allItems {
            let isSelected = isItemSelected(item.type)
            let key = item.type.rawValue
            let checkColor: SKColor
            let selBg: SKColor
            switch item.type {
            case .bombBag:
                checkColor = SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.04, blue: 0.04, alpha: 0.90)
            case .magicBag:
                checkColor = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1)
                selBg      = SKColor(red: 0.04, green: 0.28, blue: 0.10, alpha: 0.90)
            case .fireBag:
                checkColor = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.06, blue: 0.01, alpha: 0.90)
            case .goldenBag:
                checkColor = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.22, blue: 0.01, alpha: 0.90)
            default:
                checkColor = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.18, blue: 0.04, alpha: 0.90)
            }

            if let rowBg = panel.childNode(withName: "//satchelRowBg_\(key)") as? SKSpriteNode {
                rowBg.color = isSelected ? selBg : SKColor(white: 1, alpha: 0.04)
            }
            if let check = panel.childNode(withName: "//satchelCheck_\(key)") as? SKShapeNode {
                check.strokeColor = isSelected ? checkColor : SKColor(white: 0.45, alpha: 1)
                check.fillColor   = isSelected ? checkColor.withAlphaComponent(0.30) : .clear
            }
            if let lbl = panel.childNode(withName: "//satchelLbl_\(key)") as? SKLabelNode {
                lbl.fontColor = isSelected ? SKColor(white: 1.0, alpha: 1) : SKColor(white: 0.80, alpha: 1)
                lbl.text = "\(item.type.displayName) ×\(item.count)"
            }
        }
    }

    /// Arms or disarms a special bag type. Count decrements immediately on arm; refunds on disarm.
    /// Only one type can be armed at a time — arming a new type disarms the previous one.
    private func selectSatchelItem(_ type: ItemType) {
        switch type {
        case .honeyBag:
            if honeyBagSelected {
                honeyBagSelected = false
                availableHoneyBags += 1
            } else if availableHoneyBags > 0 {
                if bombBagSelected   { bombBagSelected   = false; availableBombBags   += 1 }
                if magicBagSelected  { magicBagSelected  = false; availableMagicBags  += 1 }
                if fireBagSelected   { fireBagSelected   = false; availableFireBags   += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                honeyBagSelected = true
                availableHoneyBags -= 1
            }
        case .bombBag:
            if bombBagSelected {
                bombBagSelected = false
                availableBombBags += 1
            } else if availableBombBags > 0 {
                if honeyBagSelected  { honeyBagSelected  = false; availableHoneyBags  += 1 }
                if magicBagSelected  { magicBagSelected  = false; availableMagicBags  += 1 }
                if fireBagSelected   { fireBagSelected   = false; availableFireBags   += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                bombBagSelected = true
                availableBombBags -= 1
            }
        case .magicBag:
            if magicBagSelected {
                magicBagSelected = false
                availableMagicBags += 1
            } else if availableMagicBags > 0 {
                if honeyBagSelected  { honeyBagSelected  = false; availableHoneyBags  += 1 }
                if bombBagSelected   { bombBagSelected   = false; availableBombBags   += 1 }
                if fireBagSelected   { fireBagSelected   = false; availableFireBags   += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                magicBagSelected = true
                availableMagicBags -= 1
            }
        case .fireBag:
            if fireBagSelected {
                fireBagSelected = false
                availableFireBags += 1
            } else if availableFireBags > 0 {
                if honeyBagSelected  { honeyBagSelected  = false; availableHoneyBags  += 1 }
                if bombBagSelected   { bombBagSelected   = false; availableBombBags   += 1 }
                if magicBagSelected  { magicBagSelected  = false; availableMagicBags  += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                fireBagSelected = true
                availableFireBags -= 1
            }
        case .goldenBag:
            if goldenBagSelected {
                goldenBagSelected = false
                availableGoldenBags += 1
            } else if availableGoldenBags > 0 {
                if honeyBagSelected { honeyBagSelected = false; availableHoneyBags += 1 }
                if bombBagSelected  { bombBagSelected  = false; availableBombBags  += 1 }
                if magicBagSelected { magicBagSelected = false; availableMagicBags += 1 }
                if fireBagSelected  { fireBagSelected  = false; availableFireBags  += 1 }
                goldenBagSelected = true
                availableGoldenBags -= 1
            }
        default:
            break
        }
        updateSatchelButton()
        updateTurnIndicator()
        refreshSatchelPanelRows()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toggleHoneyBagSelection() {
        honeyBagSelected.toggle()
        updateSatchelButton()
        updateTurnIndicator()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Game Flow

    private func startRound() {
        roundNumber += 1

        // Tom's fart — deactivate any lingering effect first, then re-roll
        if tomFartActive { deactivateTomFart() }
        if selectedOpponent == .tom && Bool.random() { activateTomFart() }

        // Toggle rain on/off for this round
        let shouldRain = rainStartRound >= 0 && roundNumber >= rainStartRound && roundNumber < rainEndRound
        if shouldRain && !rainActive  { activateRain() }
        if !shouldRain && rainActive  { deactivateRain() }

        // Toggle storm on/off for this round
        let shouldStorm = stormStartRound >= 0 && roundNumber >= stormStartRound && roundNumber < stormEndRound
        if shouldStorm && !stormActive  { activateStorm() }
        if !shouldStorm && stormActive  { deactivateStorm() }

        // Storm brings stronger, more consistent wind
        if stormActive {
            let dir: CGFloat = Bool.random() ? 1 : -1
            wind = CGVector(dx: CGFloat.random(in: 3.5...5.5) * dir, dy: 0)
        } else {
            wind = CGVector(dx: CGFloat.random(in: -2.0...2.0), dy: 0)
        }
        updateWindLabel()

        playerBagsThrown    = 0
        aiBagsThrown        = 0
        hasCalculatedScore  = false
        honeyBagSelected    = false
        bombBagSelected     = false
        magicBagSelected    = false
        fireBagSelected     = false
        boardOnFire         = false
        holeFire            = false
        fireBoardOverlay?.removeFromParent()
        fireBoardOverlay    = nil
        gameWorldNode.childNode(withName: "fireBoardLabel")?.removeFromParent()
        gameWorldNode.childNode(withName: "fireBoardEmitter")?.removeFromParent()
        updateSatchelButton()
        refreshSatchelPanelRows()

        for bag in activeBags {
            bag.node.removeFromParent()
            bag.shadow.removeFromParent()
        }
        activeBags.removeAll()

        clearGopher()

        crowNode?.removeFromParent()
        crowNode = nil
        removeAction(forKey: "crowSchedule")

        messageNode?.removeFromParent()
        messageNode = nil

        gameState = .playerTurn
        lastThrower = .ai
        targetX = 0
        turnIndicator?.isHidden = false

        updateScoreLabels()
        updateTurnIndicator()
        updateRoundLabels()

        // First throw of the round is the player's — give the gopher a chance.
        maybeStartGopher(for: .player)
        scheduleCrow()
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
            // Pre-commit AI start X so the gopher has a fixed target to chase.
            pendingAIStartX = CGFloat.random(in: -targetRange * 0.55...targetRange * 0.55)
            updateTurnIndicator()
            turnIndicator?.position.x = pendingAIStartX

            maybeStartGopher(for: .ai)
            // Give the gopher a longer wind-up so it has a real chance to win the race.
            let delay: TimeInterval = activeGopher == nil
                ? 0.50
                : TimeInterval.random(in: 1.0...1.8)
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in self?.aiThrow() },
            ]), withKey: "pendingAIThrow")
        } else {
            gameState = .playerTurn
            targetX = 0
            turnIndicator?.position.x = 0
            turnIndicator?.isHidden = false
            updateTurnIndicator()

            maybeStartGopher(for: .player)
        }
    }

    private func calculateRoundScore() {
        guard !hasCalculatedScore else { return }
        hasCalculatedScore = true

        var roundPlayer = 0
        var roundAI     = 0

        for bag in activeBags {
            guard !bag.isDestroyed else { continue }
            let isInHole  = bag.hasScored
            let isOnBoard = !isInHole && checkIsOnBoard(bag)
            let pts: Int
            if isInHole        { pts = bag.isGolden ? 6 : 3 }
            else if isOnBoard  { pts = bag.isGolden ? 2 : 1 }
            else               { pts = 0 }
            if bag.owner == .player { roundPlayer += pts }
            else                    { roundAI     += pts }
        }

        let net = roundPlayer - roundAI
        if net > 0 { playerScore += net }
        else if net < 0 { aiScore += abs(net) }

        // Billy adapts: tighten on player round wins, ease slightly on AI wins
        if selectedOpponent == .billy {
            if net > 0 {
                billyNoiseFactor = max(1.4, billyNoiseFactor - 0.12)
            } else if net < 0 {
                billyNoiseFactor = min(3.8, billyNoiseFactor + 0.15)
            }
        }

        updateScoreLabels()

        if playerScore >= winScore || aiScore >= winScore {
            gameState = .gameOver
            removeAction(forKey: "crowSchedule")
            crowNode?.removeFromParent()
            crowNode = nil
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
        guard !isPausedGame else { return }
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

        updateGopher(dt: dt)
        checkCrowCollisions()

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
                guard !a.isDestroyed && !b.isDestroyed else { continue }

                // Bags that fell off the board are locked in place — skip
                guard !a.hasAppliedGroundScale && !b.hasAppliedGroundScale else { continue }

                // Honey bags are sticky — they don't move when other bags hit them
                guard !a.isHoney && !b.isHoney else { continue }

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

                // Magic bag hits opponent bag — destroy the opponent bag, magic bag continues.
                // Golden bags are fully immune to magic bag effects.
                let aMagicVsB = a.isMagic && b.owner != a.owner && !b.isGolden
                let bMagicVsA = b.isMagic && a.owner != b.owner && !a.isGolden
                if aMagicVsB || bMagicVsA {
                    if aMagicVsB { destroyBag(b); showMagicPoof(at: CGPoint(x: b.bx, y: b.by)) }
                    if bMagicVsA { destroyBag(a); showMagicPoof(at: CGPoint(x: a.bx, y: a.by)) }
                    continue
                }

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
        // During a fart round, add a jitter wobble so the indicator shakes unpredictably.
        var displayX = targetX
        if tomFartActive {
            fartWobbleTimer += dt
            displayX += sin(fartWobbleTimer * 14.0) * targetRange * 0.08
                      + CGFloat.random(in: -targetRange * 0.04...targetRange * 0.04)
        }
        turnIndicator?.position.x = displayX
    }

    private func updateBagPhysics(_ bag: MiniGameBag, dt: CGFloat) {
        // Airborne wind push — honey bags are immune (they're sticky)
        if bag.bz > 0, !bag.isHoney {
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
                    run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                }

                // Non-fire bags landing on a burning board are immediately destroyed
                if boardOnFire && !bag.isFire && !bag.isDestroyed {
                    destroyBag(bag)
                }

                if bag.isHoney {
                    // Honey bags stick on contact — no bounce, no slide, rain-immune
                    bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                    bag.isGrounded = true
                } else {
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
                }

                // Hole detection
                let dist = hypot(bag.bx - holeCenter.x, bag.by - holeCenter.y)
                if dist <= holeRadius && !bag.hasScored {
                    bag.hasScored  = true
                    CornholeStatsManager.shared.recordCornhole()
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
                    // Bomb in hole: destroy opponent bags already scored in the hole
                    if bag.isBomb && !bag.hasBombed {
                        bag.hasBombed = true
                        triggerBombHole(by: bag.owner)
                    }
                    // Magic bag in hole: destroy opponent bags already scored in the hole
                    if bag.isMagic {
                        triggerMagicHole(by: bag.owner)
                    }
                    // Fire bag in hole: burn all other cornholes this round (3 pts kept by thrower)
                    if bag.isFire && !bag.hasTriggeredFire {
                        bag.hasTriggeredFire = true
                        triggerFireHole(by: bag.owner)
                    }
                    // Non-fire bag scoring in a hole-fire round is destroyed immediately
                    if holeFire && !bag.isFire && !bag.isDestroyed {
                        destroyBag(bag)
                    }
                } else if bag.isBomb && !bag.hasBombed && bag.isGrounded && checkIsOnBoard(bag) {
                    // Bomb rests on board surface: destroy opponent bags on the board
                    bag.hasBombed = true
                    triggerBombBoard(at: CGPoint(x: bag.bx, y: bag.by), by: bag.owner)
                } else if bag.isFire && !bag.hasTriggeredFire && bag.isGrounded && checkIsOnBoard(bag) {
                    // Fire bag rests on board: burn all other board bags this round
                    bag.hasTriggeredFire = true
                    triggerFireBoard(at: CGPoint(x: bag.bx, y: bag.by), by: bag.owner)
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
        // Use 95% of board dimensions to match the visually scaled boardContainer
        abs(bag.bx) <= boardHalfW * 0.95 &&
        bag.by >= boardY - boardHalfH * 0.95 &&
        bag.by <= boardY + boardHalfH * 0.95
    }

    // MARK: - Bomb Bag

    /// Bomb lands on board surface: destroys all opponent bags resting on the board.
    private func triggerBombBoard(at pos: CGPoint, by owner: BagOwner) {
        let opponent: BagOwner = owner == .player ? .ai : .player
        var destroyed = 0
        for bag in activeBags where bag.owner == opponent && !bag.isDestroyed
                                  && bag.isGrounded && !bag.hasScored && checkIsOnBoard(bag) {
            destroyBag(bag)
            destroyed += 1
        }
        showBombExplosion(at: pos, label: destroyed > 0 ? "BOOM! \(destroyed) BAG\(destroyed == 1 ? "" : "S") GONE!" : "BOOM!")
    }

    /// Bomb scores in hole: destroys all opponent bags already scored in the hole.
    private func triggerBombHole(by owner: BagOwner) {
        let opponent: BagOwner = owner == .player ? .ai : .player
        var destroyed = 0
        for bag in activeBags where bag.owner == opponent && !bag.isDestroyed && bag.hasScored {
            destroyBag(bag)
            destroyed += 1
        }
        showBombExplosion(at: CGPoint(x: holeCenter.x, y: holeCenter.y),
                          label: destroyed > 0 ? "BOOM! \(destroyed) HOLE BAG\(destroyed == 1 ? "" : "S") GONE!" : "BOOM!")
    }

    private func destroyBag(_ bag: MiniGameBag) {
        bag.isDestroyed = true
        bag.vx = 0; bag.vy = 0; bag.vz = 0
        let pop = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.1, duration: 0.22),
                SKAction.fadeOut(withDuration: 0.22),
            ]),
            SKAction.removeFromParent(),
        ])
        bag.node.run(pop)
        bag.shadow.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.15),
            SKAction.removeFromParent(),
        ]))
    }

    private func showBombExplosion(at pos: CGPoint, label: String) {
        // Pixel particle burst
        let container = SKNode()
        container.position  = pos
        container.zPosition = 300
        addChild(container)

        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.40, blue: 0.10, alpha: 1),
            SKColor(red: 1.0, green: 0.80, blue: 0.10, alpha: 1),
            SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
        ]
        for _ in 0..<10 {
            let p = SKSpriteNode(color: colors.randomElement()!,
                                 size: CGSize(width: 5, height: 5))
            p.position = .zero
            container.addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 35...80)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: 0.38),
                    SKAction.fadeOut(withDuration: 0.38),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.45),
            SKAction.removeFromParent(),
        ]))

        // BOOM label
        let boom = makeLabel(text: label,
                             size: max(6, size.width * 0.048),
                             color: SKColor(red: 1.0, green: 0.35, blue: 0.10, alpha: 1))
        boom.position  = CGPoint(x: pos.x, y: pos.y + 22)
        boom.zPosition = 800
        boom.alpha     = 0
        boom.setScale(0.6)
        addChild(boom)
        boom.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.16),
                SKAction.fadeIn(withDuration: 0.16),
            ]),
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Magic Bag

    /// Magic bag scores in hole: destroys all opponent bags already in the hole this round.
    /// Golden bags in the hole are immune and cannot be removed by this effect.
    private func triggerMagicHole(by owner: BagOwner) {
        let opponent: BagOwner = owner == .player ? .ai : .player
        var destroyed = 0
        for bag in activeBags where bag.owner == opponent && !bag.isDestroyed && bag.hasScored && !bag.isGolden {
            destroyBag(bag)
            destroyed += 1
        }
        if destroyed > 0 {
            showMagicPoof(at: CGPoint(x: holeCenter.x, y: holeCenter.y))
            let lbl = makeLabel(
                text: "MAGIC! \(destroyed) CORNHOLE\(destroyed == 1 ? "" : "S") STOLEN!",
                size: max(6, size.width * 0.044),
                color: SKColor(red: 0.12, green: 0.92, blue: 0.42, alpha: 1))
            lbl.position  = CGPoint(x: 0, y: size.height * 0.14)
            lbl.zPosition = 800
            lbl.alpha     = 0
            addChild(lbl)
            lbl.run(SKAction.sequence([
                SKAction.fadeIn(withDuration: 0.18),
                SKAction.wait(forDuration: 1.2),
                SKAction.fadeOut(withDuration: 0.28),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Sparkle-poof visual when a magic bag destroys an opponent bag on contact.
    private func showMagicPoof(at pos: CGPoint) {
        let container = SKNode()
        container.position  = pos
        container.zPosition = 300
        addChild(container)

        let colors: [SKColor] = [
            SKColor(red: 0.12, green: 0.90, blue: 0.40, alpha: 1),
            SKColor(red: 0.60, green: 1.00, blue: 0.60, alpha: 1),
            SKColor(red: 1.00, green: 1.00, blue: 0.80, alpha: 1),
        ]
        for _ in 0..<8 {
            let p = SKSpriteNode(color: colors.randomElement()!,
                                 size: CGSize(width: 4, height: 4))
            p.position = .zero
            container.addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 25...55)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: 0.32),
                    SKAction.fadeOut(withDuration: 0.32),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.40),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Fire Bag

    /// Fire bag lands on board: this bag scores 1 pt; all other board bags this round are destroyed.
    private func triggerFireBoard(at pos: CGPoint, by owner: BagOwner) {
        boardOnFire = true
        showFireBoardOverlay()
        var destroyed = 0
        for bag in activeBags where !bag.isFire && !bag.isDestroyed
                                  && bag.isGrounded && !bag.hasScored && checkIsOnBoard(bag) {
            destroyBag(bag)
            destroyed += 1
        }
        showFireEffect(at: pos)
        let msg = destroyed > 0
            ? "FIRE! \(destroyed) BAG\(destroyed == 1 ? "" : "S") BURNED!"
            : "FIRE! BOARD ABLAZE!"
        showFireMessage(msg, at: CGPoint(x: 0, y: size.height * 0.14))
    }

    /// Fire bag scores in hole: this bag keeps its 3 pts; all other cornholes this round are destroyed.
    private func triggerFireHole(by owner: BagOwner) {
        holeFire = true
        var destroyed = 0
        for bag in activeBags where !bag.isFire && !bag.isDestroyed && bag.hasScored {
            destroyBag(bag)
            destroyed += 1
        }
        showFireEffect(at: CGPoint(x: holeCenter.x, y: holeCenter.y))
        let msg = destroyed > 0
            ? "FIRE! \(destroyed) CORNHOLE\(destroyed == 1 ? "" : "S") BURNED!"
            : "FIRE! HOLE ABLAZE!"
        showFireMessage(msg, at: CGPoint(x: 0, y: size.height * 0.14))
    }

    /// Orange-red particle burst — used for both board and hole fire triggers.
    private func showFireEffect(at pos: CGPoint) {
        let container = SKNode()
        container.position  = pos
        container.zPosition = 300
        addChild(container)

        let colors: [SKColor] = [
            SKColor(red: 1.0,  green: 0.90, blue: 0.10, alpha: 1),   // yellow
            SKColor(red: 1.0,  green: 0.45, blue: 0.05, alpha: 1),   // orange
            SKColor(red: 0.95, green: 0.15, blue: 0.05, alpha: 1),   // red
        ]
        for _ in 0..<14 {
            let p = SKSpriteNode(color: colors.randomElement()!,
                                 size: CGSize(width: CGFloat.random(in: 4...7),
                                              height: CGFloat.random(in: 4...7)))
            p.position = .zero
            container.addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 40...90)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: 0.42),
                    SKAction.fadeOut(withDuration: 0.42),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.50),
            SKAction.removeFromParent(),
        ]))
    }

    /// Floating orange-red message label.
    private func showFireMessage(_ text: String, at pos: CGPoint) {
        let lbl = makeLabel(text: text,
                            size: max(6, size.width * 0.046),
                            color: SKColor(red: 1.0, green: 0.38, blue: 0.05, alpha: 1))
        lbl.position  = pos
        lbl.zPosition = 800
        lbl.alpha     = 0
        lbl.setScale(0.6)
        addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.16),
                SKAction.fadeIn(withDuration: 0.16),
            ]),
            SKAction.wait(forDuration: 1.1),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    /// Semi-transparent fire overlay drawn over the board while it's ablaze.
    private func showFireBoardOverlay() {
        guard fireBoardOverlay == nil else { return }

        // Base red-orange wash over the entire board
        let overlay = SKSpriteNode(color: SKColor(red: 1.0, green: 0.22, blue: 0.01, alpha: 0.55),
                                   size: CGSize(width: boardHalfW * 2, height: boardHalfH * 2))
        overlay.name      = "fireBoardOverlay"
        overlay.position  = CGPoint(x: 0, y: boardY)
        overlay.zPosition = 19
        overlay.alpha     = 0
        gameWorldNode.addChild(overlay)
        fireBoardOverlay  = overlay

        overlay.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.20),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.32, duration: 0.22),
                SKAction.fadeAlpha(to: 0.62, duration: 0.22),
            ])),
        ]))

        // Continuous ember particles rising from the board surface
        let emitter = SKNode()
        emitter.name      = "fireBoardEmitter"
        emitter.position  = CGPoint(x: 0, y: boardY - boardHalfH)
        emitter.zPosition = 21
        gameWorldNode.addChild(emitter)

        let emberColors: [SKColor] = [
            SKColor(red: 1.0,  green: 0.88, blue: 0.10, alpha: 1),
            SKColor(red: 1.0,  green: 0.45, blue: 0.05, alpha: 1),
            SKColor(red: 0.95, green: 0.12, blue: 0.02, alpha: 1),
        ]
        let spawnEmbers = SKAction.repeatForever(SKAction.sequence([
            SKAction.run { [weak self, weak emitter] in
                guard let self, let emitter else { return }
                for _ in 0..<3 {
                    let p = SKSpriteNode(
                        color: emberColors.randomElement()!,
                        size: CGSize(width: CGFloat.random(in: 3...6),
                                     height: CGFloat.random(in: 3...6)))
                    p.position = CGPoint(x: CGFloat.random(in: -self.boardHalfW...self.boardHalfW),
                                         y: 0)
                    p.zPosition = 1
                    p.alpha = 0
                    emitter.addChild(p)
                    let rise  = CGFloat.random(in: 28...70)
                    let drift = CGFloat.random(in: -18...18)
                    p.run(SKAction.sequence([
                        SKAction.group([
                            SKAction.fadeIn(withDuration: 0.08),
                            SKAction.moveBy(x: drift, y: rise, duration: 0.55),
                            SKAction.sequence([
                                SKAction.wait(forDuration: 0.20),
                                SKAction.fadeOut(withDuration: 0.35),
                            ]),
                        ]),
                        SKAction.removeFromParent(),
                    ]))
                }
            },
            SKAction.wait(forDuration: 0.08),
        ]))
        emitter.run(spawnEmbers, withKey: "embers")

        // "BOARD ON FIRE!" label pinned above the board
        let fireLbl = makeLabel(text: "🔥 BOARD ON FIRE! 🔥",
                                size: max(6, size.width * 0.042),
                                color: SKColor(red: 1.0, green: 0.38, blue: 0.05, alpha: 1))
        fireLbl.name      = "fireBoardLabel"
        fireLbl.position  = CGPoint(x: 0, y: boardY + boardHalfH + 18)
        fireLbl.zPosition = 22
        fireLbl.alpha     = 0
        gameWorldNode.addChild(fireLbl)
        fireLbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.20),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.55, duration: 0.30),
                SKAction.fadeAlpha(to: 1.00, duration: 0.30),
            ])),
        ]))
    }

    // MARK: - Throwing

    private func throwBag(owner: BagOwner, startX: CGFloat, vx: CGFloat, vy: CGFloat, aiBomb: Bool = false) {
        // availableHoneyBags / availableBombBags / availableMagicBags / availableFireBags / availableGoldenBags
        // already decremented on arm.
        let useHoney  = owner == .player && honeyBagSelected
        let useBomb   = (owner == .player && bombBagSelected) || aiBomb
        let useMagic  = owner == .player && magicBagSelected
        let useFire   = owner == .player && fireBagSelected
        let useGolden = owner == .player && goldenBagSelected
        if useHoney {
            honeyBagsUsed += 1
            honeyBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if owner == .player && bombBagSelected {
            bombBagsUsed += 1
            bombBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if useMagic {
            magicBagsUsed += 1
            magicBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if useFire {
            fireBagsUsed += 1
            fireBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if useGolden {
            goldenBagsUsed += 1
            goldenBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        let bag = MiniGameBag(owner: owner, startX: startX, startY: throwLineY,
                              isHoney: useHoney, isBomb: useBomb, isMagic: useMagic,
                              isFire: useFire, isGolden: useGolden)
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

        // Thrower beat the gopher to the punch — gopher dives away.
        if let gopher = activeGopher {
            gopher.diveAway()
            activeGopher = nil
        }
    }

    // MARK: - AI

    private func aiThrow() {
        guard gameState == .aiTurn, aiBagsThrown < bagsPerPlayer else { return }

        let startX       = pendingAIStartX
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 60 frames

        // Base aim: hole with noise scaled by weather
        let noiseFactor: CGFloat = rainActive ? 3.4 : 2.5
        let noise = holeRadius * noiseFactor
        var aimX = holeCenter.x + CGFloat.random(in: -noise...noise)
        var aimY = holeCenter.y + CGFloat.random(in: -noise * 0.5...noise * 0.5)

        // Tom — mirrors player hole shots: when player has a bag in the hole,
        // strong chance to aim with tight precision and cancel those points.
        if selectedOpponent == .tom {
            let playerHoles = activeBags.filter { $0.owner == .player && $0.hasScored }.count
            if playerHoles > 0, Double.random(in: 0..<1) < 0.55 {
                let preciseNoise = holeRadius * 0.38
                aimX = holeCenter.x + CGFloat.random(in: -preciseNoise...preciseNoise)
                aimY = holeCenter.y + CGFloat.random(in: -preciseNoise * 0.5...preciseNoise * 0.5)
            }
        }

        // Jenny — high chance to aim directly at a player bag resting on the board.
        if selectedOpponent == .jenny {
            let targets = activeBags.filter {
                $0.owner == .player && $0.isGrounded && !$0.hasScored &&
                !$0.hasAppliedGroundScale && checkIsOnBoard($0)
            }
            if let target = targets.randomElement(), Double.random(in: 0..<1) < 0.85 {
                aimX = target.bx + CGFloat.random(in: -10...10)
                aimY = target.by + CGFloat.random(in: -10...10)
            }
        }

        let vx = (aimX - startX) / flightFrames
        let vy = (aimY - throwLineY) / flightFrames

        // Billy — adaptive noise that tightens as the player improves.
        // May also throw bomb bags to destroy player bags on the board or in the hole.
        if selectedOpponent == .billy {
            let billyNoise = holeRadius * billyNoiseFactor
            aimX = holeCenter.x + CGFloat.random(in: -billyNoise...billyNoise)
            aimY = holeCenter.y + CGFloat.random(in: -billyNoise * 0.5...billyNoise * 0.5)
            let billyVx = (aimX - startX) / flightFrames
            let billyVy = (aimY - throwLineY) / flightFrames

            let throwBomb = billyBombBagsRemaining > 0 && Double.random(in: 0..<1) < 0.20
            if throwBomb { billyBombBagsRemaining -= 1 }
            throwBag(owner: .ai, startX: startX, vx: billyVx, vy: billyVy, aiBomb: throwBomb)
            return
        }

        // Tree Spirit — drops magic bags straight down from above.
        // 50% aim near the hole; 50% fall on a random board spot.
        if selectedOpponent == .spirit {
            let targetX: CGFloat
            let targetY: CGFloat
            if Double.random(in: 0..<1) < 0.15 {
                let noise = holeRadius * 1.0
                targetX = holeCenter.x + CGFloat.random(in: -noise...noise)
                targetY = holeCenter.y + CGFloat.random(in: -noise * 0.4...noise * 0.4)
            } else {
                targetX = CGFloat.random(in: -boardHalfW * 0.80 ... boardHalfW * 0.80)
                targetY = CGFloat.random(in: (boardY - boardHalfH * 0.80) ... (boardY + boardHalfH * 0.80))
            }
            dropMagicBagFromAbove(targetX: targetX, targetY: targetY)
            return
        }

        throwBag(owner: .ai, startX: startX, vx: vx, vy: vy)
    }

    /// Creates a Spirit magic bag that materialises high above the board and falls straight down.
    private func dropMagicBagFromAbove(targetX: CGFloat, targetY: CGFloat) {
        guard gameState == .aiTurn, aiBagsThrown < bagsPerPlayer else { return }

        let bag = MiniGameBag(owner: .ai, startX: targetX, startY: targetY, isMagic: true)
        bag.bz   = 220          // materialise well above the board
        bag.vx   = CGFloat.random(in: -0.3...0.3)  // tiny flutter
        bag.vy   = 0
        bag.vz   = 0
        bag.rotV = CGFloat.random(in: -0.04...0.04)

        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)

        aiBagsThrown += 1
        lastThrower   = .ai
        gameState     = .resolving
        turnIndicator?.isHidden = true
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Tutorial overlay consumes all input — any tap advances it.
        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        // HUD help button re-presents the tutorial without restarting the round.
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

        // Quit-confirm modal consumes all input until resolved
        if confirmingQuit { handleButtonTap(at: loc); return }

        guard gameState == .playerTurn else {
            // Allow tapping game-over buttons in any state
            handleButtonTap(at: loc)
            return
        }

        // Swallow touches over UI to prevent a throw from starting.
        // Actions (selectSatchelItem, openPanel, etc.) fire once in touchesEnded.
        if handleButtonTap(at: loc, fireActions: false) { return }

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
    // Pass fireActions:false from touchesBegan to swallow satchel-item touches without
    // triggering selection — selection fires once in touchesEnded to avoid double-toggle.
    @discardableResult
    private func handleButtonTap(at location: CGPoint, fireActions: Bool = true) -> Bool {
        for node in nodes(at: location) {
            var n: SKNode? = node
            while let current = n {
                switch current.name {
                case "satchelButton":
                    if fireActions, !satchelOpen {
                        openSatchelPanel()
                    }
                    return true
                case "satchelCloseBtn":
                    if fireActions { closeSatchelPanel() }
                    return true
                case "satchelBackdrop", "satchelPanelBg":
                    return true  // swallow — panel stays open
                case let name where name?.hasPrefix("satchelItem_") == true:
                    if fireActions,
                       let name = name,
                       let type = ItemType(rawValue: String(name.dropFirst("satchelItem_".count))) {
                        selectSatchelItem(type)
                        closeSatchelPanel()
                    }
                    return true
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
                    playerScore = 0
                    aiScore     = 0
                    roundNumber = 0
                    if rainActive { deactivateRain() }
                    if tomFartActive { deactivateTomFart() }
                    rollWeatherScenarios()
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
            text: playerWon ? "YOU WIN!" : "\(opponentName) WINS!",
            size: fs * 0.7,
            color: playerWon
                ? SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1)
                : SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        title.position = CGPoint(x: 0, y: panelH * 0.28)
        panel.addChild(title)

        // Final score
        let scoreLbl = makeLabel(
            text: "YOU \(playerScore)  —  \(aiScore) \(opponentName)",
            size: fs * 0.60,
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

        // Spirit loss hint
        if !playerWon && selectedOpponent == .spirit {
            let hintLbl = makeLabel(
                text: "SPECIAL BAGS MAY HELP\nAGAINST SUCH A FOE...",
                size: max(5, fs * 0.52),
                color: SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1))
            hintLbl.numberOfLines = 2
            hintLbl.position = CGPoint(x: 0, y: -panelH * 0.18)
            panel.addChild(hintLbl)
        }

        // Play Again
        let playBtn = makeButton(label: "PLAY AGAIN",
                                 fg: .white,
                                 bg: SKColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1),
                                 size: CGSize(width: panelW * 0.60, height: fs * 1.8))
        playBtn.position = CGPoint(x: 0, y: -panelH * 0.30)
        playBtn.name = "playAgainBtn"
        panel.addChild(playBtn)

        // Exit
        let exitBtn = makeButton(label: "EXIT",
                                 fg: .white,
                                 bg: SKColor(red: 0.42, green: 0.10, blue: 0.10, alpha: 1),
                                 size: CGSize(width: panelW * 0.40, height: fs * 1.8))
        exitBtn.position = CGPoint(x: 0, y: -panelH * 0.43)
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
        else if net < 0 { text = "+\(abs(net)) \(opponentName)" }
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
        playerScoreLabel?.text = "YOU: \(playerScore) | \(opponentName): \(aiScore)"
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
            if fireBagSelected {
                turnIndicator?.color = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)  // orange — fire bag armed
            } else if honeyBagSelected {
                turnIndicator?.color = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)  // golden — honey bag armed
            } else {
                turnIndicator?.color = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
            }
            turnIndicator?.isHidden = false
        case .aiTurn:
            turnIndicator?.color = SKColor(red: 0.30, green: 0.50, blue: 0.90, alpha: 1)
            turnIndicator?.isHidden = selectedOpponent == .spirit
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
        if stormActive {
            windLabel?.text = "STORM | \(windText)"
            windLabel?.fontColor = SKColor(red: 0.95, green: 0.90, blue: 0.20, alpha: 1)
        } else if rainActive {
            windLabel?.text = "RAIN | \(windText)"
            windLabel?.fontColor = SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1)
        } else {
            windLabel?.text = windText
            windLabel?.fontColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // gold
        }
    }

    // MARK: - Rain

    private func rollWeatherScenarios() {
        guard selectedOpponent == .billy else { return }
        rollRainScenario()
        rollThunderstormScenario()
    }

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
        overlay.setScale(0.90)   // match board visual scale
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

    // MARK: - Thunderstorm

    private func rollThunderstormScenario() {
        stormStartRound = -1
        stormEndRound   = Int.max

        // Don't stack weather — rain takes precedence
        guard rainStartRound < 0 else { return }

        // 30% chance of thunderstorm this game
        guard Int.random(in: 0..<10) < 3 else { return }

        stormStartRound = Int.random(in: 1...2)
        let wholeGame = Bool.random()
        if !wholeGame {
            let duration = Int.random(in: 1...2)
            stormEndRound = stormStartRound + duration
        }
    }

    private func activateStorm() {
        stormActive = true
        addStormDarkOverlay()
        spawnStormParticles()
        scheduleNextLightningFlash()
        scheduleNextLightningStrike()
        showStormAnnouncement()
        updateWindLabel()

        guard stormAudioNode == nil,
              Bundle.main.url(forResource: "storm", withExtension: "mp3") != nil else { return }
        let audio = SKAudioNode(fileNamed: "storm.mp3")
        audio.autoplayLooped = true
        audio.isPositional   = false
        audio.run(SKAction.changeVolume(to: 0, duration: 0))
        addChild(audio)
        audio.run(SKAction.changeVolume(to: 0.70, duration: 1.2))
        stormAudioNode = audio
    }

    private func deactivateStorm() {
        stormActive = false
        removeAction(forKey: "stormFlash")
        removeAction(forKey: "stormStrike")

        if let audio = stormAudioNode {
            audio.run(SKAction.sequence([
                SKAction.changeVolume(to: 0, duration: 1.5),
                SKAction.removeFromParent(),
            ]))
            stormAudioNode = nil
        }

        stormDarkOverlay?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.8),
            SKAction.removeFromParent(),
        ]))
        stormDarkOverlay = nil

        stormParticleNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.6),
            SKAction.removeFromParent(),
        ]))
        stormParticleNode = nil

        stormFlashOverlay?.removeFromParent()
        stormFlashOverlay = nil

        let cleared = makeLabel(text: "STORM PASSED",
                                size: max(7, size.width * 0.055),
                                color: SKColor(red: 0.95, green: 0.90, blue: 0.50, alpha: 1))
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

    // MARK: - Tom's Fart Ability

    private func activateTomFart() {
        tomFartActive    = true
        fartWobbleTimer  = 0
        targetSpeed      = fartBaseSpeed * 2.2   // indicator moves ~2× faster

        // Green fog cloud centered over the board + hole area
        let fogContainer = SKNode()
        fogContainer.zPosition = 97   // above board, below chrome
        addChild(fogContainer)
        tomFartOverlay = fogContainer

        // Build several overlapping soft circles to simulate a cloudy fog
        let boardCenterY = boardY + (holeCenter.y - boardY) * 0.5
        let fogW = size.width * 0.70
        let fogH = size.height * 0.55
        for _ in 0..<6 {
            let blob = SKSpriteNode(
                color: SKColor(red: CGFloat.random(in: 0.20...0.35),
                               green: CGFloat.random(in: 0.55...0.78),
                               blue:  CGFloat.random(in: 0.10...0.22),
                               alpha: CGFloat.random(in: 0.18...0.32)),
                size: CGSize(width: fogW * CGFloat.random(in: 0.45...0.85),
                             height: fogH * CGFloat.random(in: 0.45...0.85)))
            blob.position = CGPoint(x: CGFloat.random(in: -fogW * 0.25...fogW * 0.25),
                                    y: boardCenterY + CGFloat.random(in: -fogH * 0.20...fogH * 0.20))
            fogContainer.addChild(blob)
            // Gently pulse each blob so the fog feels alive
            let pulseDur = Double.random(in: 0.6...1.2)
            blob.run(.repeatForever(.sequence([
                .fadeAlpha(to: blob.alpha * 0.55, duration: pulseDur),
                .fadeAlpha(to: blob.alpha, duration: pulseDur)
            ])))
        }
        fogContainer.alpha = 0
        fogContainer.run(.fadeIn(withDuration: 0.50))

        // Announcement banner
        showTomFartAnnouncement()

        // Sound — add fart.wav to Copy Bundle Resources to enable; silently skipped if absent
        if Bundle.main.url(forResource: "fart", withExtension: "wav") != nil {
            run(SKAction.playSoundFileNamed("fart.wav", waitForCompletion: false))
        } else {
            run(SKAction.playSoundFileNamed("gopher_pop.wav", waitForCompletion: false))
        }
    }

    private func deactivateTomFart() {
        tomFartActive = false
        targetSpeed   = fartBaseSpeed

        tomFartOverlay?.run(.sequence([
            .fadeOut(withDuration: 0.60),
            .removeFromParent()
        ]))
        tomFartOverlay = nil
    }

    private func showTomFartAnnouncement() {
        // Outer glow backing
        let glow = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.40, blue: 0.08, alpha: 0.72),
            size: CGSize(width: size.width * 0.76, height: size.height * 0.12))
        glow.position  = CGPoint(x: 0, y: size.height * 0.14)
        glow.zPosition = 810
        glow.alpha     = 0
        addChild(glow)

        let lbl = makeLabel(text: "TOMMY TOOTS! 💨",
                            size: max(7, size.width * 0.052),
                            color: SKColor(red: 0.58, green: 1.00, blue: 0.22, alpha: 1))
        lbl.position  = CGPoint(x: 0, y: size.height * 0.14)
        lbl.zPosition = 820
        lbl.alpha     = 0
        addChild(lbl)

        let seq = SKAction.sequence([
            .fadeIn(withDuration: 0.22),
            .scale(to: 1.08, duration: 0.12),
            .scale(to: 1.00, duration: 0.10),
            .wait(forDuration: 1.6),
            .fadeOut(withDuration: 0.38),
            .removeFromParent()
        ])
        lbl.run(seq)
        glow.run(seq.copy() as! SKAction)
    }

    private func addStormDarkOverlay() {
        // Moonlight tint: cool blue wash at low opacity so the scene stays bright
        let overlay = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.18, blue: 0.55, alpha: 0.32),
            size: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.zPosition = 95   // above game world, below storm particles
        overlay.alpha = 0
        addChild(overlay)
        stormDarkOverlay = overlay
        overlay.run(SKAction.fadeIn(withDuration: 0.8))
    }

    private func spawnStormParticles() {
        // Add directly to scene (not gameWorldNode) to avoid render-bounds expansion bug
        let container = SKNode()
        container.zPosition = 102
        addChild(container)
        stormParticleNode = container

        let w = size.width
        let h = size.height

        for _ in 0..<90 {
            let drop = SKSpriteNode(
                color: SKColor(red: 0.60, green: 0.65, blue: 0.85, alpha: 0.72),
                size: CGSize(width: 2, height: 12))
            drop.zRotation = -0.20   // steeper diagonal slant than normal rain

            drop.position = CGPoint(
                x: CGFloat.random(in: -w / 2 ... w / 2),
                y: CGFloat.random(in: -h / 2 ... h / 2))
            container.addChild(drop)

            let duration = TimeInterval(CGFloat.random(in: 0.12...0.28))
            let fallDist = h + 30
            let driftX   = fallDist * -0.20

            let resetAction = SKAction.customAction(withDuration: 0) { [weak drop] _, _ in
                drop?.position = CGPoint(
                    x: CGFloat.random(in: -w / 2 ... w / 2),
                    y: h / 2 + 15)
            }
            let cycle = SKAction.sequence([
                SKAction.moveBy(x: driftX, y: -fallDist, duration: duration),
                resetAction,
            ])
            let delay = SKAction.wait(forDuration: TimeInterval(CGFloat.random(in: 0...0.3)))
            drop.run(SKAction.sequence([delay, SKAction.repeatForever(cycle)]))
        }
    }

    // Self-scheduling flash so each interval is freshly randomised
    private func scheduleNextLightningFlash() {
        guard stormActive else { return }
        run(SKAction.sequence([
            SKAction.wait(forDuration: TimeInterval.random(in: 2.5...6.0)),
            SKAction.run { [weak self] in
                guard let self, self.stormActive else { return }
                self.triggerLightningFlash()
                self.scheduleNextLightningFlash()
            },
        ]), withKey: "stormFlash")
    }

    private func triggerLightningFlash() {
        if stormFlashOverlay == nil {
            let flash = SKSpriteNode(
                color: SKColor(red: 0.95, green: 0.95, blue: 0.78, alpha: 0),
                size: CGSize(width: size.width * 2, height: size.height * 2))
            flash.zPosition = 200
            addChild(flash)
            stormFlashOverlay = flash
        }
        guard let flash = stormFlashOverlay else { return }
        // Double-pulse mimics a real lightning strike
        flash.removeAllActions()
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.80, duration: 0.04),
            SKAction.fadeAlpha(to: 0.18, duration: 0.07),
            SKAction.fadeAlpha(to: 0.55, duration: 0.03),
            SKAction.fadeAlpha(to: 0.0,  duration: 0.28),
        ]))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // Self-scheduling strike so each interval is freshly randomised
    private func scheduleNextLightningStrike() {
        guard stormActive else { return }
        run(SKAction.sequence([
            SKAction.wait(forDuration: TimeInterval.random(in: 7.0...15.0)),
            SKAction.run { [weak self] in
                guard let self, self.stormActive else { return }
                self.triggerLightningStrike()
                self.scheduleNextLightningStrike()
            },
        ]), withKey: "stormStrike")
    }

    private func triggerLightningStrike() {
        // Only target grounded on-board bags that haven't already scored or fallen off
        let targets = activeBags.filter {
            $0.isGrounded && !$0.hasScored && !$0.hasAppliedGroundScale && checkIsOnBoard($0)
        }
        guard let target = targets.randomElement() else { return }

        spawnLightningBolt(at: CGPoint(x: target.bx, y: target.by))
        triggerLightningFlash()

        // Brief delay so the bolt is visible before the bag pops
        run(SKAction.wait(forDuration: 0.15)) { [weak self] in
            self?.zapBag(target)
        }
    }

    private func zapBag(_ bag: MiniGameBag) {
        activeBags.removeAll { $0 === bag }

        bag.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.4, duration: 0.08),
                SKAction.fadeAlpha(to: 0.9, duration: 0.08),
            ]),
            SKAction.group([
                SKAction.scale(to: 0.0, duration: 0.20),
                SKAction.fadeOut(withDuration: 0.20),
            ]),
            SKAction.removeFromParent(),
        ]))
        bag.shadow.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.22),
            SKAction.removeFromParent(),
        ]))

        let zapLabel = makeLabel(text: "ZAP!",
                                 size: max(8, size.width * 0.065),
                                 color: SKColor(red: 1.0, green: 0.95, blue: 0.20, alpha: 1))
        zapLabel.position  = CGPoint(x: bag.bx, y: bag.by + 20)
        zapLabel.zPosition = 300
        zapLabel.alpha     = 0
        addChild(zapLabel)
        zapLabel.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.10),
            SKAction.moveBy(x: 0, y: 30, duration: 0.60),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
    }

    private func spawnLightningBolt(at position: CGPoint) {
        let startY = size.height * 0.45
        let steps  = 6
        let stepH  = (startY - position.y) / CGFloat(steps)

        var points = [CGPoint(x: position.x, y: startY)]
        for i in 1..<steps {
            points.append(CGPoint(
                x: position.x + CGFloat.random(in: -18...18),
                y: startY - stepH * CGFloat(i)))
        }
        points.append(position)

        let path = CGMutablePath()
        path.move(to: points[0])
        for pt in points.dropFirst() { path.addLine(to: pt) }

        let bolt = SKShapeNode(path: path)
        bolt.strokeColor = SKColor(red: 1.0, green: 0.97, blue: 0.40, alpha: 1)
        bolt.lineWidth   = 3
        bolt.glowWidth   = 4
        bolt.zPosition   = 250
        addChild(bolt)

        bolt.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.08),
            SKAction.fadeAlpha(to: 0.5, duration: 0.08),
            SKAction.fadeOut(withDuration: 0.20),
            SKAction.removeFromParent(),
        ]))
    }

    private func showStormAnnouncement() {
        let lbl = makeLabel(text: "THUNDERSTORM!",
                            size: max(7, size.width * 0.056),
                            color: SKColor(red: 0.95, green: 0.90, blue: 0.20, alpha: 1))
        lbl.position  = CGPoint(x: 0, y: size.height * 0.12)
        lbl.zPosition = 800
        lbl.alpha     = 0
        addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.15),
            SKAction.wait(forDuration: 1.5),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - First-time Tutorial

    private func showFirstTimeTutorial() {
        presentTutorial(autoTriggered: true)
    }

    /// Presents the cornhole tutorial via the shared `TutorialOverlay`. On
    /// auto-trigger (first play, before the first round starts) we kick off
    /// `startRound()` after completion; on replay (HUD `?` button) we do nothing
    /// since the round is already in progress.
    private func presentTutorial(autoTriggered: Bool) {
        let steps: [TutorialStep] = [
            .card(title: "CORNHOLE",
                  body:  "FIRST PLAYER TO 11 POINTS WINS THE MATCH."),
            .card(title: "AIMING",
                  body:  "DRAG FROM THE BAG TO AIM. LONGER DRAGS THROW HARDER. RELEASE TO TOSS."),
            .card(title: "SCORING",
                  body:  "BAG IN THE HOLE = 3 POINTS. BAG ON THE BOARD = 1 POINT. CANCELLATION RULES APPLY EACH ROUND."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self = self else { return }
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.cornhole)
                self.startRound()
            }
        }
        addChild(overlay)
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

    // MARK: - Gopher

    private func maybeStartGopher(for owner: BagOwner) {
        clearGopher()
        guard Double.random(in: 0..<1) < gopherSpawnChance else { return }

        // Spawn near the front edge of the board so the gopher has a runway —
        // gives the thrower a visible warning + a brief reaction window.
        let spawnY = boardY - boardHalfH - 22
        guard spawnY > throwLineY + 20 else { return }   // not enough room

        let referenceX: CGFloat = owner == .player ? targetX : pendingAIStartX
        let jitter = targetRange * 0.5
        let rawX = referenceX + CGFloat.random(in: -jitter...jitter)
        let spawnX = min(max(rawX, -targetRange), targetRange)

        let gopher = GopherNode()
        gopher.position = CGPoint(x: spawnX, y: spawnY)
        gopher.zPosition = 18
        gameWorldNode.addChild(gopher)
        activeGopher = gopher

        run(SKAction.playSoundFileNamed("gopher_pop.wav", waitForCompletion: false))
        gopher.emerge(completion: {})
    }

    private func updateGopher(dt: CGFloat) {
        guard let gopher = activeGopher else { return }

        let targetXNow: CGFloat
        switch gameState {
        case .playerTurn: targetXNow = targetX
        case .aiTurn:     targetXNow = pendingAIStartX
        default:
            gopher.diveAway()
            activeGopher = nil
            return
        }

        let target = CGPoint(x: targetXNow, y: throwLineY)
        gopher.chase(toward: target, dt: dt)

        let dist = hypot(target.x - gopher.position.x, target.y - gopher.position.y)
        if dist < gopher.catchRadius {
            stealThrow(owner: gameState == .playerTurn ? .player : .ai, with: gopher)
        }
    }

    private func stealThrow(owner: BagOwner, with gopher: GopherNode) {
        run(SKAction.playSoundFileNamed("gopher_steal.wav", waitForCompletion: false))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        if let indicator = turnIndicator {
            indicator.removeAllActions()
            indicator.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 0.2, duration: 0.14),
                    SKAction.fadeOut(withDuration: 0.14),
                ]),
                SKAction.run { [weak indicator] in
                    indicator?.isHidden = true
                    indicator?.alpha = 1
                    indicator?.setScale(1)
                    let pulse = SKAction.sequence([
                        SKAction.scale(to: 1.18, duration: 0.55),
                        SKAction.scale(to: 1.00, duration: 0.55),
                    ])
                    indicator?.run(SKAction.repeatForever(pulse))
                },
            ]))
        }

        let stolen = makeLabel(text: "STOLEN!",
                               size: max(7, size.width * 0.055),
                               color: SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1))
        stolen.position  = CGPoint(x: gopher.position.x, y: gopher.position.y + 18)
        stolen.zPosition = 300
        stolen.alpha     = 0
        gameWorldNode.addChild(stolen)
        stolen.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.10),
            SKAction.moveBy(x: 0, y: 28, duration: 0.70),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))

        if owner == .player {
            playerBagsThrown += 1
            lastThrower = .player
        } else {
            aiBagsThrown += 1
            lastThrower = .ai
        }
        gameState = .resolving

        gopher.catchAndRetreat(completion: { [weak self] in
            self?.activeGopher = nil
        })
        activeGopher = nil

        removeAction(forKey: "pendingAIThrow")

        run(SKAction.wait(forDuration: 0.55)) { [weak self] in
            self?.handleTurnEnd()
        }
    }

    private func clearGopher() {
        activeGopher?.removeFromParent()
        activeGopher = nil
    }

    // MARK: - Crow

    private func scheduleCrow() {
        removeAction(forKey: "crowSchedule")
        guard gameState != .gameOver else { return }
        let delay = TimeInterval.random(in: 8.0...22.0)
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.spawnCrow() },
        ]), withKey: "crowSchedule")
    }

    private func spawnCrow() {
        guard crowNode == nil, gameState != .gameOver else { scheduleCrow(); return }
        crowFlyingRight = Bool.random()
        let startX: CGFloat = crowFlyingRight ? -(size.width * 0.65) : (size.width * 0.65)
        let endX:   CGFloat = crowFlyingRight ?  (size.width * 0.65) : -(size.width * 0.65)

        let crow = makeCrowSprite(facingRight: crowFlyingRight)
        crow.position  = CGPoint(x: startX, y: crowY)
        crow.zPosition = 16
        gameWorldNode.addChild(crow)
        crowNode = crow

        let flyDuration = TimeInterval(abs(endX - startX) / 175.0)
        crow.run(SKAction.sequence([
            SKAction.moveTo(x: endX, duration: flyDuration),
            SKAction.removeFromParent(),
            SKAction.run { [weak self, weak crow] in
                if self?.crowNode === crow { self?.crowNode = nil }
                self?.scheduleCrow()
            },
        ]), withKey: "crowFly")
    }

    private func makeCrowSprite(facingRight: Bool) -> SKSpriteNode {
        let ps = 5   // 25% bigger than original ps=4
        // 11 × 6 pixel grid — beak faces right; flip xScale for left-facing
        let grid: [[Int]] = [
            [0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0],
            [0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0],
            [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0],
        ]
        let cols = grid[0].count, rows = grid.count
        let imgW = CGFloat(cols * ps), imgH = CGFloat(rows * ps)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: imgW, height: imgH), false, 1.0)
        if let ctx = UIGraphicsGetCurrentContext() {
            ctx.setFillColor(UIColor(red: 0.10, green: 0.08, blue: 0.10, alpha: 1).cgColor)
            for row in 0..<rows {
                for col in 0..<cols where grid[row][col] == 1 {
                    ctx.fill(CGRect(x: CGFloat(col * ps), y: CGFloat(row * ps),
                                    width: CGFloat(ps), height: CGFloat(ps)))
                }
            }
        }
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest

        let sprite = SKSpriteNode(texture: tex, size: CGSize(width: imgW, height: imgH))
        if !facingRight { sprite.xScale = -1 }
        sprite.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleY(to: 0.55, duration: 0.13),
            SKAction.scaleY(to: 1.00, duration: 0.17),
        ])))
        return sprite
    }

    private func checkCrowCollisions() {
        guard let crow = crowNode else { return }
        let crowPos = crow.position
        for bag in activeBags {
            guard !bag.isGrounded, bag.bz > 2 else { continue }
            let visualY = bag.by + bag.bz * 0.5
            let dx = bag.bx - crowPos.x
            let dy = visualY - crowPos.y
            if dx * dx + dy * dy < 26 * 26 {
                crowHitByBag(bag)
                return
            }
        }
    }

    private func crowHitByBag(_ bag: MiniGameBag) {
        guard let crow = crowNode else { return }
        crowNode = nil
        removeAction(forKey: "crowSchedule")
        crow.removeAction(forKey: "crowFly")

        // Bag stops horizontally; gravity pulls it straight down next frame
        bag.vx = 0; bag.vy = 0; bag.vz = 0

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Rapid panic flap
        (crow as? SKSpriteNode)?.removeAllActions()
        (crow as? SKSpriteNode)?.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleY(to: 0.25, duration: 0.06),
            SKAction.scaleY(to: 1.00, duration: 0.06),
        ])))

        // Crow bolts upward and off-screen in the direction it was flying
        let escapeX: CGFloat = crowFlyingRight ? 190 : -190
        crow.run(SKAction.sequence([
            SKAction.moveBy(x: escapeX * 0.25, y: 55, duration: 0.20),
            SKAction.moveBy(x: escapeX * 0.75, y: 130, duration: 0.52),
            SKAction.removeFromParent(),
            SKAction.run { [weak self] in self?.scheduleCrow() },
        ]))

        // "SQUAWK!" callout
        let squawk = makeLabel(text: "SQUAWK!",
                               size: max(7, size.width * 0.048),
                               color: SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1))
        squawk.position  = CGPoint(x: crow.position.x, y: crow.position.y + 20)
        squawk.zPosition = 300
        squawk.alpha     = 0
        gameWorldNode.addChild(squawk)
        squawk.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.09),
            SKAction.moveBy(x: 0, y: 32, duration: 0.65),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Opponent Selection

    private func showOpponentPicker() {
        if let pre = preSelectedOpponent {
            selectedOpponent = pre
            switch pre {
            case .billy:  applyBillySettings()
            case .spirit: applySpiritSettings()
            default: break
            }
            rollWeatherScenarios()
            addOpponentPortrait()
            if TutorialManager.shared.hasSeen(TutorialManager.cornhole) {
                startRound()
            } else {
                showFirstTimeTutorial()
            }
            return
        }
        let configs: [OpponentConfig] = [
            OpponentConfig(name: "TOM",    imageName: "tom",
                           traitText: "TOPS YOUR HOLE SHOTS"),
            OpponentConfig(name: "JENNY",  imageName: "jenny",
                           traitText: "KNOCKS BAGS OFF BOARD"),
            OpponentConfig(name: "BILLY",  imageName: "billy",
                           traitText: "MATCHES YOUR SKILL • TO 21"),
            OpponentConfig(name: "SPIRIT", imageName: "spirit",
                           traitText: "DROPS MAGIC BAGS • TO 21"),
        ]
        let picker = OpponentPickerNode(opponents: configs, sceneSize: size)
        picker.zPosition = 3000
        picker.onSelected = { [weak self] index in
            guard let self else { return }
            switch index {
            case 0: self.selectedOpponent = .tom
            case 1: self.selectedOpponent = .jenny
            case 2:
                self.selectedOpponent = .billy
                self.applyBillySettings()
            default:
                self.selectedOpponent = .spirit
                self.applySpiritSettings()
            }
            self.rollWeatherScenarios()
            self.addOpponentPortrait()
            if TutorialManager.shared.hasSeen(TutorialManager.cornhole) {
                self.startRound()
            } else {
                self.showFirstTimeTutorial()
            }
        }
        addChild(picker)
    }

    /// Configures Tree Spirit game overrides: score to 21, no forced weather.
    private func applySpiritSettings() {
        winScore = 21
    }

    /// Configures all Billy-specific overrides after opponent selection.
    private func applyBillySettings() {
        winScore = 21
        // Force thunderstorm for the entire match — no random rain
        rainStartRound  = -1
        rainEndRound    = Int.max
        stormStartRound = 1
        stormEndRound   = Int.max
        billyNoiseFactor = computeBillyInitialNoise()
        billyBombBagsRemaining = computeBillyBombCount()
    }

    /// Computes Billy's initial noise factor from the player's career cornhole accuracy.
    /// Returns a value in [0.8, 3.5]: 3.5 = beginner, 0.8 = expert.
    private func computeBillyInitialNoise() -> CGFloat {
        let stats = CornholeStatsManager.shared
        let totalGames = stats.wins + stats.losses
        guard totalGames > 0 else { return 3.2 }
        // ~12 throw opportunities per game (4 bags × ~3 rounds avg)
        let rate = CGFloat(stats.cornholes) / (CGFloat(totalGames) * 12.0)
        let clamped = min(rate, 1.0)
        return max(1.4, 3.8 - clamped * 2.1)
    }

    /// Billy starts with more bomb bags when the player is more skilled (higher stakes).
    private func computeBillyBombCount() -> Int {
        if billyNoiseFactor > 2.8 { return 1 }
        if billyNoiseFactor > 1.8 { return 2 }
        return 3
    }

    private func addOpponentPortrait() {
        opponentPortrait?.removeFromParent()
        let name: String
        switch selectedOpponent {
        case .tom:    name = "tom"
        case .jenny:  name = "jenny"
        case .billy:  name = "billy"
        case .spirit: name = "spirit"
        }
        let tex  = SKTexture(imageNamed: name)
        tex.filteringMode = .nearest
        let bottomH = size.height * 0.09
        let portrait = SKSpriteNode(texture: tex, size: CGSize(width: 48, height: 48))
        portrait.position  = CGPoint(x: -size.width / 2 + 28,
                                     y: -size.height / 2 + bottomH / 2)
        portrait.zPosition = 650
        addChild(portrait)
        opponentPortrait = portrait
    }

    // MARK: - Pause / Resume

    private func pauseGame() {
        guard !isPausedGame, gameState != .gameOver else { return }
        isPausedGame = true
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
    }

    private func showPauseOverlay() {
        let W = size.width, H = size.height
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
        if tomFartActive { deactivateTomFart() }
        if playerWon { CornholeStatsManager.shared.recordWin() }
        else         { CornholeStatsManager.shared.recordLoss() }
        if playerWon && selectedOpponent == .tom    { CornholeStatsManager.shared.recordDefeatedTom() }
        if playerWon && selectedOpponent == .jenny  { CornholeStatsManager.shared.recordDefeatedJenny() }
        if playerWon && selectedOpponent == .billy  { bombBagsEarned  = 3 }
        if playerWon && selectedOpponent == .spirit { magicBagsEarned = 3 }
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        let transition = SKTransition.push(with: .down, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(prev, transition: transition)
    }
}
